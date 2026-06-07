// SPDX-License-Identifier: GPL-3.0

/// @title Shwouns DAO Proposals library
///
/// @notice Forked from NounsDAOProposals.sol. The propose/vote/state/cancel lifecycle
///         mirrors V4. The novel parts are queue → recordSnapshot → collect → finalize,
///         which replace V4's timelock-based execute, with per-proposal fund isolation.
///
/// @dev Brought to NounsDAOLogicV4 parity (minus the intentional treasury/timelock/fork
///      removals and client-ID attribution): signed proposals (per-signer EIP-712 digest +
///      ERC-1271), refundable votes, candidates, objection period, dynamic quorum, and
///      vote-by-signature are all implemented and hardened. Remaining upstream parity item:
///      proposal editing (the Updatable window).

pragma solidity ^0.8.19;

import { ShwounsDAOTypes, ShwounsDAOEvents, IShwounsTokenLike } from "./ShwounsDAOInterfaces.sol";
import { IShwounsVaultRegistry } from "../vault/IShwounsVaultRegistry.sol";
import { ShwounsVault } from "../vault/ShwounsVault.sol";
import { IProposalEscrow } from "./ProposalEscrow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

library ShwounsDAOProposals {
    using SafeERC20 for IERC20;

    /// @dev The 4-byte selector for ERC-20 transfer(address,uint256). Used to detect
    ///      ERC-20 funding requirements in a proposal's calldata.
    bytes4 internal constant ERC20_TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    /// @dev UUPS upgrade selectors. A DAOLogic self-upgrade must be a proposal's FINAL action (A9).
    bytes4 internal constant UPGRADE_TO_SELECTOR = bytes4(keccak256("upgradeTo(address)"));
    bytes4 internal constant UPGRADE_TO_AND_CALL_SELECTOR = bytes4(keccak256("upgradeToAndCall(address,bytes)"));

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the proposer's votes do not exceed the proposal threshold.
    error ProposerVotesBelowThreshold();
    /// @notice Thrown when a proposal has zero actions.
    error InvalidProposalActions();
    /// @notice Thrown when a proposal's action arrays differ in length.
    error ActionsArrayLengthMismatch();
    /// @notice Thrown when a proposal has more than 10 actions.
    error TooManyActions();
    /// @notice Thrown when the proposer already has a live proposal in flight.
    error ProposerAlreadyHasLiveProposal();
    /// @notice Thrown when a voter tries to vote twice on the same proposal.
    error CannotVoteTwice();
    /// @notice Thrown when a vote `support` value is greater than 2.
    error InvalidSupportValue();
    /// @notice Reserved: thrown when voting has closed (legacy guard).
    error VotingClosed();
    /// @notice Thrown when casting a vote outside the Active/ObjectionPeriod window.
    error VotingNotOpen();
    /// @notice Thrown when referencing a proposal id that was never created.
    error ProposalDoesNotExist();
    /// @notice Reserved: thrown when a proposal was already canceled (legacy guard).
    error ProposalAlreadyCanceled();
    /// @notice Thrown when a non-proposer/non-signer cancels a proposal still above threshold.
    error ProposerAboveThresholdAndNotVetoer();
    /// @notice Thrown when an action is attempted from an invalid proposal state.
    error InvalidProposalState();
    /// @notice Reserved: thrown when a proposal was already queued/settled (legacy guard).
    error AlreadyQueuedOrSettled();
    /// @notice Reserved: thrown when the snapshot phase has not started (legacy guard).
    error SnapshotPhaseNotStarted();
    /// @notice Reserved: thrown when the snapshot phase is incomplete (legacy guard).
    error SnapshotPhaseNotComplete();
    /// @notice Reserved: thrown when the collect phase is incomplete (legacy guard).
    error CollectPhaseNotComplete();
    /// @notice Reserved: thrown when a vault was already collected (legacy guard).
    error VaultAlreadyCollected();
    /// @notice Reserved: thrown when a vault was not snapshotted (legacy guard).
    error VaultNotSnapshotted();
    /// @notice Thrown when finalize is attempted but collected funds are below the requested amount.
    error InsufficientCollected();
    /// @notice Thrown when a top-up is zero, for an unrequested asset, or exceeds the shortfall.
    error InvalidTopUp();
    /// @notice Reserved: thrown when caller is not a Shwouns holder (legacy guard).
    error NotShwounsHolder();
    /// @notice Reserved: thrown when caller is neither proposer nor vetoer (legacy guard).
    error OnlyProposerOrVetoer();
    /// @notice Thrown when a vetoer-only action is called by another address.
    error OnlyVetoer();
    /// @notice Reserved: generic unauthorized guard.
    error NotAuthorized();
    /// @notice Thrown when a non-Against vote is cast during the objection period.
    error OnlyAgainstVotesDuringObjection();
    /// @notice Thrown when finalize/refund/rescue runs while another finalize is in flight.
    error AlreadyExecuting();
    /// @notice Thrown when queue is attempted before the ProposalEscrow implementation is set.
    error EscrowImplNotSet();
    /// @notice Thrown when rescue is attempted on a non-terminal proposal.
    error NotTerminal();
    /// @notice Thrown when the escrow at the predicted address is not the expected clone codehash.
    error EscrowCodehashMismatch();
    /// @notice Thrown when a DAOLogic self-upgrade action is not the proposal's final action.
    error UpgradeMustBeLastAction();
    /// @notice Thrown when a proposal requests a non-allowlisted ERC-20 (M-04).
    error AssetNotFundable();
    /// @notice Thrown when recordSnapshot runs before the queue-time vault-set freeze completes.
    error FreezeNotComplete();
    /// @notice Thrown when freezeVaults is called after the freeze is already complete.
    error FreezeAlreadyComplete();

    /// @dev M-05: max active vaults frozen within queue() itself. The remainder (for a set larger
    ///      than this) is paged via freezeVaults() across later txs, keeping per-tx work bounded.
    uint256 internal constant FREEZE_BATCH_AT_QUEUE = 256;

    /// @notice Residual asset kinds for rescueFromEscrow (A8).
    enum AssetKind { ETH, ERC20, ERC721, ERC1155 }

    // -------------------------------------------------------------------------
    // Re-emit events to enable indexer simplicity (library events bubble up)
    // -------------------------------------------------------------------------

    /// @notice Emitted when a proposal is created.
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    /// @notice Emitted on each vote cast (For/Against/Abstain) with the voter's weight and reason.
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);
    /// @notice Emitted when a proposal is canceled.
    event ProposalCanceled(uint256 id);
    /// @notice Emitted when a proposal is queued (escrow deployed, vault-set freeze begun).
    event ProposalQueued(uint256 id);
    /// @notice Emitted once per asset when the snapshot phase completes, with the total snapshotted.
    event ProposalSnapshotted(uint256 indexed id, address indexed asset, uint256 totalSnapshotBalance);
    /// @notice Emitted when the collect phase completes for a proposal.
    event ProposalCollected(uint256 indexed id);
    /// @notice Emitted when a proposal's actions execute successfully (terminal Executed).
    event ProposalExecuted(uint256 id);
    /// @notice Emitted when a proposal is vetoed.
    event ProposalVetoed(uint256 id);
    /// @notice Emitted per (proposal, vault, asset) when a non-zero balance is recorded at snapshot.
    event VaultSnapshotted(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 balance);
    /// @notice Emitted per (proposal, vault, asset) when an amount is actually pulled at collect.
    event AssetCollectedFromVault(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 amount);
    /// @notice Emitted when a vault's collect-time balance is below its snapshot share (a shortfall).
    event ShortfallRecorded(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 missingAmount);
    /// @notice Emitted when a last-minute For-flip starts the objection period.
    event ProposalObjectionPeriodSet(uint256 indexed proposalId, uint256 objectionPeriodEndBlock);

    // =========================================================================
    // Propose
    // =========================================================================

    /// @notice Create a proposal. The caller must hold votes strictly exceeding the proposal
    ///         threshold and have no other live proposal. Opens an Updatable window, then voting.
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action (GovernorBravo form).
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @return proposalId The id of the created proposal.
    function propose(
        ShwounsDAOTypes.Storage storage ds,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId) {
        _validateActionsAndThreshold(ds, targets, values, signatures, calldatas);
        _enforceOneLiveProposal(ds);

        ds.proposalCount++;
        proposalId = ds.proposalCount;
        _writeProposal(ds, proposalId, targets, values, signatures, calldatas);
        ds.latestProposalIds[msg.sender] = proposalId;

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            p.startBlock,
            p.endBlock,
            description
        );
    }

    /// @dev Validate action-array shape (equal lengths, 1..10 actions) AND that the proposer's prior
    ///      votes STRICTLY exceed the proposal threshold (`<=` reverts — matching Nouns — so a
    ///      threshold that rounds to 0 at low supply can't let a zero-vote address propose).
    function _validateActionsAndThreshold(
        ShwounsDAOTypes.Storage storage ds,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal view {
        if (targets.length != values.length ||
            targets.length != signatures.length ||
            targets.length != calldatas.length) revert ActionsArrayLengthMismatch();
        if (targets.length == 0) revert InvalidProposalActions();
        if (targets.length > 10) revert TooManyActions();

        uint256 totalSupply = ds.shwouns.totalSupply();
        uint256 threshold = bps2Uint(ds.proposalThresholdBPS, totalSupply);
        // Strictly greater than the threshold, matching Nouns (votes <= threshold reverts). With
        // `<` a threshold that rounds to 0 at low supply would let a zero-vote address propose.
        if (ds.shwouns.getPriorVotes(msg.sender, block.number - 1) <= threshold) {
            revert ProposerVotesBelowThreshold();
        }
    }

    /// @dev Revert if msg.sender already has a proposal in flight (Active/Pending/ObjectionPeriod/
    ///      Updatable) — at most one live proposal per proposer.
    function _enforceOneLiveProposal(ShwounsDAOTypes.Storage storage ds) internal view {
        uint256 latestProposalId = ds.latestProposalIds[msg.sender];
        if (latestProposalId == 0) return;
        ShwounsDAOTypes.ProposalState state_ = state(ds, latestProposalId);
        // A proposer may have at most one proposal in flight. "In flight" includes the
        // ObjectionPeriod (and the Updatable window, added with proposal editing).
        if (state_ == ShwounsDAOTypes.ProposalState.Active ||
            state_ == ShwounsDAOTypes.ProposalState.Pending ||
            state_ == ShwounsDAOTypes.ProposalState.ObjectionPeriod ||
            state_ == ShwounsDAOTypes.ProposalState.Updatable) {
            revert ProposerAlreadyHasLiveProposal();
        }
    }

    /// @notice Internal proposal-writer exposed `public` only for cross-library linking (A3 split);
    ///         not intended for external callers.
    /// @dev `public` so the ShwounsDAOSignatures library can reach it cross-library (A3 split).
    ///      In-library callers (propose) still reach it as a same-library JUMP, so the hot propose
    ///      path is unaffected; only the cold proposeBySigs path pays the delegatecall hop.
    /// @param proposalId The id to write.
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    function _writeProposal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) public {
        uint256 totalSupply = ds.shwouns.totalSupply();
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.proposalThreshold = bps2Uint(ds.proposalThresholdBPS, totalSupply);
        p.quorumVotes = bps2Uint(ds.quorumVotesBPS, totalSupply);
        p.targets = targets;
        p.values = values;
        p.signatures = signatures;
        p.calldatas = calldatas;
        // The proposal is editable (Updatable) until updatePeriodEndBlock; voting opens after the
        // update window closes, then the voting delay. With an updatable period of 0 this reduces
        // to the previous behavior (startBlock = creationBlock + votingDelay).
        uint256 updatePeriodEnd = block.number + ds.proposalUpdatablePeriodInBlocks;
        p.updatePeriodEndBlock = updatePeriodEnd;
        p.startBlock = updatePeriodEnd + ds.votingDelay;
        p.endBlock = p.startBlock + ds.votingPeriod;
        p.totalSupply = totalSupply;
        p.creationBlock = block.number;
    }

    /// @notice Cross-library entry for ShwounsDAOSignatures.proposeBySigs: validate actions (NO
    ///         proposer-threshold check — proposeBySigs enforces threshold via combined signer
    ///         power), bump the counter, write the proposal, and emit ProposalCreated. Mirrors the
    ///         propose() tail.
    /// @dev `public` so proposeBySigs reaches it as a DELEGATECALL in its own frame — the 9-arg
    ///      ProposalCreated emit is too stack-heavy to inline into proposeBySigs under via_ir, but
    ///      compiles cleanly here (same shape as propose). `msg.sender` is preserved across the
    ///      delegatecall, so the emitted proposer is the original caller.
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @return proposalId The id of the created proposal.
    function createForSigners(
        ShwounsDAOTypes.Storage storage ds,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256 proposalId) {
        _validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);
        ds.proposalCount++;
        proposalId = ds.proposalCount;
        _writeProposal(ds, proposalId, targets, values, signatures, calldatas);
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        emit ProposalCreated(
            proposalId, msg.sender, targets, values, signatures, calldatas, p.startBlock, p.endBlock, description
        );
    }

    // =========================================================================
    // Vote
    // =========================================================================

    /// @notice Cast a vote on a proposal.
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    function castVote(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint8 support
    ) external {
        _castVoteInternal(ds, msg.sender, proposalId, support, "");
    }

    /// @notice Cast a vote on a proposal with an attached reason string.
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    /// @param reason A free-text reason emitted in the VoteCast event.
    function castVoteWithReason(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external {
        _castVoteInternal(ds, msg.sender, proposalId, support, reason);
    }

    /// @notice Cast a vote via an EIP-712 signature (gasless / relayed voting). The recovered
    ///         signer is the voter. Routes through the same internal path as castVote so the
    ///         objection-period and dynamic-quorum logic apply identically. ECDSA-only (Nouns
    ///         parity for ballots).
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    /// @param v The ECDSA signature `v` component.
    /// @param r The ECDSA signature `r` component.
    /// @param s The ECDSA signature `s` component.
    function castVoteBySig(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = ECDSA.toTypedDataHash(
            _domainSeparator(ds),
            keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))
        );
        address voter = ecrecover(digest, v, r, s);
        if (voter == address(0)) revert SigInvalid();
        _castVoteInternal(ds, voter, proposalId, support, "");
    }

    /// @dev Shared vote path for all cast variants. Allows any support while Active; only Against
    ///      during ObjectionPeriod; reverts otherwise. Records the receipt at the proposal's
    ///      start-block voting weight (no double-voting), tallies it, and — only from the Active
    ///      phase on a For vote — may trigger the objection period.
    function _castVoteInternal(
        ShwounsDAOTypes.Storage storage ds,
        address voter,
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) internal {
        if (support > 2) revert InvalidSupportValue();

        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        if (s == ShwounsDAOTypes.ProposalState.Active) {
            // any support allowed
        } else if (s == ShwounsDAOTypes.ProposalState.ObjectionPeriod) {
            if (support != 0) revert OnlyAgainstVotesDuringObjection();
        } else {
            revert VotingNotOpen();
        }

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        ShwounsDAOTypes.Receipt storage receipt = p.receipts[voter];
        if (receipt.hasVoted) revert CannotVoteTwice();

        uint96 votes = ds.shwouns.getPriorVotes(voter, p.startBlock - 1);
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        if (support == 0) p.againstVotes += votes;
        else if (support == 1) p.forVotes += votes;
        else if (support == 2) p.abstainVotes += votes;

        emit VoteCast(voter, proposalId, support, votes, reason);

        // Trigger objection period if conditions met (only during Active phase, not in
        // an existing ObjectionPeriod).
        if (s == ShwounsDAOTypes.ProposalState.Active && support == 1) {
            _maybeStartObjectionPeriod(ds, proposalId);
        }
    }

    /// @dev Start the objection period iff a For vote lands in the last-minute window AND the
    ///      proposal is currently passing (For > Against AND For >= quorum). Extends voting by
    ///      objectionPeriodDurationInBlocks, during which only Against votes are accepted. No-op if
    ///      already started, the window is disabled, or the conditions aren't met.
    function _maybeStartObjectionPeriod(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) internal {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        if (p.objectionPeriodEndBlock > 0) return;
        if (ds.lastMinuteWindowInBlocks == 0) return;
        if (block.number + ds.lastMinuteWindowInBlocks <= p.endBlock) return; // not yet in window
        if (p.forVotes <= p.againstVotes) return; // still failing on majority
        if (p.forVotes < quorumVotes(ds, proposalId)) return; // still failing on quorum

        p.objectionPeriodEndBlock = uint64(p.endBlock + ds.objectionPeriodDurationInBlocks);
        emit ProposalObjectionPeriodSet(proposalId, p.objectionPeriodEndBlock);
    }

    // =========================================================================
    // State
    // =========================================================================

    /// @notice The current lifecycle state of a proposal (see ProposalState).
    /// @param proposalId The proposal to query.
    /// @return The computed proposal state.
    function state(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) public view returns (ShwounsDAOTypes.ProposalState) {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        if (p.id == 0) revert ProposalDoesNotExist();
        // Highest precedence (review §3): a proposal mid-finalize is Executing — a distinct
        // transient state observed BEFORE any terminal flag. terminal `executed` is not yet set
        // during execution, and cancel()/veto() explicitly reject Executing, so contradictory
        // terminal combinations are unreachable. Setting `executed` before the calls (the v5
        // mistake) would have let a reentrant rescue pass its terminal gate mid-execution.
        if (ds.executing && ds.activeProposalId == proposalId) {
            return ShwounsDAOTypes.ProposalState.Executing;
        }
        if (p.vetoed) return ShwounsDAOTypes.ProposalState.Vetoed;
        if (p.canceled) return ShwounsDAOTypes.ProposalState.Canceled;
        if (p.executed) return ShwounsDAOTypes.ProposalState.Executed;

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        // Advanced lifecycle states: only reachable once queue() has run.
        if (ss.finalized) return ShwounsDAOTypes.ProposalState.Executed;
        if (ss.queued) {
            // Snapshot phase: complete when every frozen vault has been paged. A zero-funding
            // proposal has snapshotTargetCount == 0, so this is satisfied immediately (C3).
            if (ss.snapshotProgress < ss.snapshotTargetCount) {
                return ShwounsDAOTypes.ProposalState.Queued;
            }
            // Collect phase: complete when every snapshotted vault has been paged. When no vault
            // held the requested asset (or there were no assets), snapshottedVaults is empty, so
            // this is satisfied immediately and the proposal is finalizable (C3).
            if (ss.collectProgress < ss.snapshottedVaults.length) {
                return ShwounsDAOTypes.ProposalState.Snapshotted;
            }
            return ShwounsDAOTypes.ProposalState.Collected;
        }

        // Pre-queue states
        if (block.number <= p.updatePeriodEndBlock) return ShwounsDAOTypes.ProposalState.Updatable;
        if (block.number <= p.startBlock) return ShwounsDAOTypes.ProposalState.Pending;
        if (block.number <= p.endBlock) return ShwounsDAOTypes.ProposalState.Active;
        if (p.objectionPeriodEndBlock > 0 && block.number <= p.objectionPeriodEndBlock) {
            return ShwounsDAOTypes.ProposalState.ObjectionPeriod;
        }
        if (p.forVotes <= p.againstVotes || p.forVotes < quorumVotes(ds, proposalId)) {
            return ShwounsDAOTypes.ProposalState.Defeated;
        }
        // Passed. If it was never queued before the queue deadline (voting end + queue period),
        // it has Expired. Shwouns policy choice (Nouns leaves unqueued Succeeded indefinite).
        uint256 votingEnd = p.objectionPeriodEndBlock > 0 ? p.objectionPeriodEndBlock : p.endBlock;
        if (block.number > votingEnd + ds.proposalQueuePeriodInBlocks) {
            return ShwounsDAOTypes.ProposalState.Expired;
        }
        return ShwounsDAOTypes.ProposalState.Succeeded;
    }

    /// @dev True once queued, the snapshot phase is finished, and every snapshotted vault has been
    ///      collected. Zero-snapshot proposals (empty snapshottedVaults) complete immediately (C3).
    function _isCollectComplete(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) internal view returns (bool) {
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        // Complete once queued, the snapshot phase has finished, and every snapshotted vault has
        // been collected. Zero-snapshot proposals (empty snapshottedVaults) complete as soon as
        // the snapshot phase finishes (C3) — collectProgress (0) >= length (0).
        return ss.queued
            && ss.snapshotProgress >= ss.snapshotTargetCount
            && ss.collectProgress >= ss.snapshottedVaults.length;
    }

    /// @notice Flat, mapping-free view of a proposal (for indexers/UIs). Includes the current
    ///         dynamic quorum, computed state, signers, and snapshot/collect progress.
    /// @param proposalId The proposal to query.
    /// @return c The condensed proposal view.
    function proposals(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) external view returns (ShwounsDAOTypes.ProposalCondensed memory c) {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        if (p.id == 0) revert ProposalDoesNotExist();
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        c.id = p.id;
        c.proposer = p.proposer;
        c.proposalThreshold = p.proposalThreshold;
        c.quorumVotes = quorumVotes(ds, proposalId);
        c.startBlock = p.startBlock;
        c.endBlock = p.endBlock;
        c.updatePeriodEndBlock = p.updatePeriodEndBlock;
        c.objectionPeriodEndBlock = p.objectionPeriodEndBlock;
        c.forVotes = p.forVotes;
        c.againstVotes = p.againstVotes;
        c.abstainVotes = p.abstainVotes;
        c.canceled = p.canceled;
        c.vetoed = p.vetoed;
        c.executed = p.executed;
        c.totalSupply = p.totalSupply;
        c.creationBlock = p.creationBlock;
        c.signers = p.signers;
        c.snapshotTargetCount = ss.snapshotTargetCount;
        c.snapshotProgress = ss.snapshotProgress;
        c.collectProgress = ss.collectProgress;
        c.state = state(ds, proposalId);
    }

    // =========================================================================
    // Cancel / Veto
    // =========================================================================

    /// @notice Cancel a proposal. Callable by the proposer/any co-signer at will, or by anyone once
    ///         the combined proposer+signer voting power has fallen to or below the threshold.
    ///         Rejected at terminal states and while Executing. Funded proposals route to refund().
    /// @param proposalId The proposal to cancel.
    function cancel(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        // H-01: cancel is NOT blocked after funds move — a funded Canceled proposal routes into the
        // contribution refund path (refund()), so funds are never stranded. Cancel is rejected only
        // at a terminal state and while the proposal is Executing (a reentrant callback could
        // otherwise satisfy the cancel threshold mid-finalize and write a contradictory flag —
        // review §6/§7).
        if (
            s == ShwounsDAOTypes.ProposalState.Canceled ||
            s == ShwounsDAOTypes.ProposalState.Defeated ||
            s == ShwounsDAOTypes.ProposalState.Expired ||
            s == ShwounsDAOTypes.ProposalState.Executed ||
            s == ShwounsDAOTypes.ProposalState.Vetoed ||
            s == ShwounsDAOTypes.ProposalState.Executing
        ) revert InvalidProposalState();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        address proposer = p.proposer;

        // The proposer or ANY co-signer may cancel at will. Otherwise anyone may cancel only once
        // the combined voting power behind the proposal (proposer + all signers) has fallen to or
        // below its threshold.
        uint256 votes = ds.shwouns.getPriorVotes(proposer, block.number - 1);
        bool msgSenderIsProposer = (msg.sender == proposer);
        address[] memory signers = p.signers;
        for (uint256 i = 0; i < signers.length; i++) {
            msgSenderIsProposer = msgSenderIsProposer || (msg.sender == signers[i]);
            votes += ds.shwouns.getPriorVotes(signers[i], block.number - 1);
        }
        if (!(msgSenderIsProposer || votes <= p.proposalThreshold)) {
            revert ProposerAboveThresholdAndNotVetoer();
        }

        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    /// @notice Veto a proposal (emergency brake). Vetoer only. Rejected at Executed/Executing.
    ///         Funded proposals route to refund().
    /// @param proposalId The proposal to veto.
    function veto(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        if (msg.sender != ds.vetoer) revert OnlyVetoer();
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        // The veto is an emergency brake and stays available even after funds are moving (H-01:
        // funded → refundable). It is rejected only at the terminal Executed state and while the
        // proposal is mid-finalize (Executing) — a vetoer may be a contract and could otherwise
        // veto from inside an action callback, writing a contradictory terminal flag (review §7).
        if (s == ShwounsDAOTypes.ProposalState.Executed || s == ShwounsDAOTypes.ProposalState.Executing) {
            revert InvalidProposalState();
        }
        ds._proposals[proposalId].vetoed = true;
        emit ProposalVetoed(proposalId);
    }

    // =========================================================================
    // Queue — transitions Succeeded → Queued; locks snapshot target + asset list
    // =========================================================================

    /// @notice Queue a Succeeded proposal: extract its requested assets, validate any self-upgrade is
    ///         last, deploy its deterministic escrow (CREATE2), and begin freezing the active vault set.
    /// @param proposalId The Succeeded proposal to queue.
    function queue(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Succeeded) revert InvalidProposalState();
        if (ds.proposalEscrowImplementation == address(0)) revert EscrowImplNotSet();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        // Extract assets + per-asset requested amounts from the proposal's actions.
        _extractAssetsAndAmounts(ds, proposalId, p.targets, p.values, p.signatures, p.calldatas);

        // A9: a DAOLogic self-upgrade must be the proposal's FINAL action, so no later action runs
        // under a possibly-incompatible new implementation within the same finalize frame.
        _validateUpgradeActionsAreLast(p.targets, p.signatures, p.calldatas);

        // Deploy this proposal's escrow EAGERLY at queue (A1). Deterministic EIP-1167 clone,
        // CREATE2 salt = proposalId, deployer = this DAOLogic proxy (the library runs in the
        // facade's context). ALL of the proposal's actions execute from this unique single-use
        // escrow at finalize, and collect/topUp route funds into it — isolating the proposal's
        // assets (and any stray output asset) to an identity only this proposal can drive. Even a
        // pure-governance (zero-funding) proposal gets one, because it too executes via the escrow.
        Clones.cloneDeterministic(ds.proposalEscrowImplementation, bytes32(proposalId));

        // C1: freeze the active vault-ID SET at queue time. recordSnapshot pages over this
        // stable copy, so the live registry active-set changing underneath us (deposits/
        // withdrawals via markActive/markPossiblyInactive) cannot skip, duplicate, or brick
        // iteration. Guarantee: "vault-set frozen at queue; balances sampled during snapshot
        // paging" — NOT a historical balance checkpoint.
        //
        // Only frozen when the proposal actually requests funds. A pure-governance proposal
        // (no ETH/ERC-20 requested → no assets) skips the snapshot phase entirely (C3):
        // snapshotTargetCount stays 0, so it is immediately Collected and finalizable.
        //
        // NOTE (scale): copies the full active set into storage in one tx. Fine for the
        // current/near-term active-set size; a paged-freeze variant is the follow-up if the
        // active set ever approaches block-gas limits.
        if (ss.assets.length > 0) {
            // M-05: snapshot the freeze TARGET (active-set length) at queue, then freeze a bounded
            // first batch. The active set is append-only (M-02), so indices [0, target) are stable
            // and the remainder can be paged via freezeVaults across later txs — keeping per-tx work
            // bounded (no whole-set copy that could exceed block gas). recordSnapshot is gated until
            // the freeze completes. A small set (<= FREEZE_BATCH_AT_QUEUE) freezes fully here.
            ss.snapshotTargetCount = ds.vaultRegistry.activeVaultsLength();
            _freezeBatch(ds, ss, FREEZE_BATCH_AT_QUEUE);
        }
        ss.queued = true;

        emit ProposalQueued(proposalId);
    }

    /// @notice Page the queue-time vault-set freeze for a set larger than FREEZE_BATCH_AT_QUEUE.
    ///         Copies the next `batchSize` active-vault indices (within [0, snapshotTargetCount))
    ///         into the proposal's frozen list. recordSnapshot reverts until this completes.
    /// @param proposalId The Queued proposal whose freeze to advance.
    /// @param batchSize The number of additional vault indices to freeze this call.
    function freezeVaults(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Queued) revert InvalidProposalState();
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        if (ss.freezeProgress >= ss.snapshotTargetCount) revert FreezeAlreadyComplete();
        _freezeBatch(ds, ss, batchSize);
    }

    /// @dev Copy [freezeProgress, min(freezeProgress+batchSize, snapshotTargetCount)) of the live
    ///      active set into frozenVaultIds. Append-only (M-02) makes these indices stable.
    function _freezeBatch(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.SnapshotState storage ss,
        uint256 batchSize
    ) internal {
        uint256 start = ss.freezeProgress;
        uint256 end = start + batchSize;
        if (end > ss.snapshotTargetCount) end = ss.snapshotTargetCount;
        for (uint256 i = start; i < end; i++) {
            ss.frozenVaultIds.push(ds.vaultRegistry.activeVaultAt(i));
        }
        ss.freezeProgress = end;
    }

    /// @notice Build the calldata an action actually executes with. GovernorBravo-style actions
    ///         may carry the function as a `signature` string with argument-only `calldata`; the
    ///         executed calldata is then the 4-byte selector of that signature prepended to the
    ///         args. With an empty signature, calldata is used verbatim. Both `finalize` and
    ///         asset extraction MUST use this, or signature-form actions are mis-executed and
    ///         invisible to snapshot/collect.
    function _fullCalldata(string memory signature, bytes memory data) internal pure returns (bytes memory) {
        if (bytes(signature).length == 0) return data;
        return abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
    }

    /// @dev Derive the proposal's requested assets + per-asset amounts at queue time: ETH from the
    ///      sum of values[], and ERC-20s from any `transfer(to,amount)` action (both raw-calldata and
    ///      GovernorBravo signature-string encodings). Each ERC-20 must be on the M-04 fundable
    ///      allowlist (ETH is always fundable); a non-allowlisted ERC-20 reverts the queue.
    function _extractAssetsAndAmounts(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal {
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        // Always include ETH (address(0)). Sum values[].
        uint256 totalETH = 0;
        for (uint256 i = 0; i < values.length; i++) {
            totalETH += values[i];
        }
        if (totalETH > 0) {
            ss.assets.push(address(0));
            ss.requestedAmount[address(0)] = totalETH;
        }

        // Detect ERC-20 transfer() calls, accounting for both the selector-in-calldata and the
        // GovernorBravo signature-string action encodings.
        for (uint256 i = 0; i < targets.length; i++) {
            bytes memory cd = _fullCalldata(signatures[i], calldatas[i]);
            if (cd.length < 68) continue; // 4 (selector) + 32 (recipient) + 32 (amount)
            bytes4 sel;
            assembly { sel := mload(add(cd, 32)) }
            if (sel != ERC20_TRANSFER_SELECTOR) continue;

            // Decode (recipient, amount) from calldata starting at byte 4
            uint256 amount;
            assembly { amount := mload(add(cd, 68)) }

            address asset = targets[i];
            if (ss.requestedAmount[asset] == 0) {
                // M-04 fundable-asset allowlist: only DAO-curated ERC-20s may fund a proposal
                // (ETH/address(0) is always fundable and handled above). Rejects rebasing/
                // fee-on-transfer tokens that can't be exactly accounted.
                if (!ds.fundableAsset[asset]) revert AssetNotFundable();
                ss.assets.push(asset);
            }
            ss.requestedAmount[asset] += amount;
        }
    }

    /// @dev A9: if any action is a DAOLogic self-upgrade (upgradeTo / upgradeToAndCall targeting
    ///      this proxy), it must be the LAST action. Recognizes both raw-calldata and signature
    ///      forms via _fullCalldata — the same encoding queue-time extraction and execute() use.
    function _validateUpgradeActionsAreLast(
        address[] memory targets,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal view {
        uint256 n = targets.length;
        for (uint256 i = 0; i < n; i++) {
            if (targets[i] != address(this)) continue;
            bytes memory cd = _fullCalldata(signatures[i], calldatas[i]);
            if (cd.length < 4) continue;
            bytes4 sel;
            assembly { sel := mload(add(cd, 32)) }
            if ((sel == UPGRADE_TO_SELECTOR || sel == UPGRADE_TO_AND_CALL_SELECTOR) && i != n - 1) {
                revert UpgradeMustBeLastAction();
            }
        }
    }

    // =========================================================================
    // recordSnapshot — paged: snapshots active vaults' balances per asset
    // =========================================================================

    /// @notice Page the snapshot phase: record each frozen vault's per-asset balance. Sets a vault's
    ///         snapshot from its balance at the moment its page is processed (not a queue-time freeze).
    /// @param proposalId The Queued proposal to snapshot.
    /// @param batchSize The number of frozen vaults to process this call.
    function recordSnapshot(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) external {
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        if (s != ShwounsDAOTypes.ProposalState.Queued) revert InvalidProposalState();

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        // M-05: the vault-set freeze must be complete before any balance is sampled, so iteration
        // pages over a fully-frozen, stable membership.
        if (ss.freezeProgress < ss.snapshotTargetCount) revert FreezeNotComplete();
        uint256 start = ss.snapshotProgress;
        uint256 end = start + batchSize;
        if (end > ss.snapshotTargetCount) end = ss.snapshotTargetCount;

        for (uint256 i = start; i < end; i++) {
            // C1: page over the queue-time frozen set, never the live registry active-set.
            uint256 shwounId = ss.frozenVaultIds[i];
            address vault = ds.vaultRegistry.vaultOf(shwounId);

            bool hasAnyBalance = false;
            for (uint256 j = 0; j < ss.assets.length; j++) {
                address asset = ss.assets[j];
                uint256 balance = asset == address(0)
                    ? vault.balance
                    : IERC20(asset).balanceOf(vault);
                if (balance == 0) continue;

                ss.vaultSnapshot[shwounId][asset] = balance;
                ss.totalSnapshotBalance[asset] += balance;
                hasAnyBalance = true;
                emit VaultSnapshotted(proposalId, shwounId, asset, balance);
            }
            if (hasAnyBalance) {
                ss.snapshottedVaults.push(shwounId);
            }
        }

        ss.snapshotProgress = end;

        if (end == ss.snapshotTargetCount) {
            for (uint256 j = 0; j < ss.assets.length; j++) {
                emit ProposalSnapshotted(proposalId, ss.assets[j], ss.totalSnapshotBalance[ss.assets[j]]);
            }
        }
    }

    // =========================================================================
    // collect — paged: pulls each vault's pro-rata share into DAOLogic
    // =========================================================================

    /// @notice Page the collect phase: pull each snapshotted vault's pro-rata share into the
    ///         proposal's escrow. Shortfalls (owner withdrew since snapshot) are accepted and logged.
    /// @param proposalId The Snapshotted proposal to collect for.
    /// @param batchSize The number of snapshotted vaults to process this call.
    function collect(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Snapshotted) revert InvalidProposalState();

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        // C2: page strictly over the recorded snapshotted-vault list. Callers cannot supply
        // arbitrary vault IDs to advance collectProgress without pulling from real vaults —
        // which previously let an attacker force a proposal to Collected and DoS collection.
        uint256 start = ss.collectProgress;
        uint256 end = start + batchSize;
        if (end > ss.snapshottedVaults.length) end = ss.snapshottedVaults.length;

        // Pull straight into THIS proposal's escrow (per-proposal custody), never the shared
        // facade. The escrow is the deterministic CREATE2 address deployed at queue.
        address escrow = escrowAddressOf(ds, proposalId);
        for (uint256 i = start; i < end; i++) {
            _collectFromVault(ds, ss, proposalId, ss.snapshottedVaults[i], escrow);
        }
        ss.collectProgress = end;

        if (_isCollectComplete(ds, proposalId)) {
            emit ProposalCollected(proposalId);
        }
    }

    /// @dev Collect one vault's contribution across every requested asset into the proposal's escrow.
    function _collectFromVault(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.SnapshotState storage ss,
        uint256 proposalId,
        uint256 shwounId,
        address escrow
    ) internal {
        address vault = ds.vaultRegistry.vaultOf(shwounId);
        uint256 assetCount = ss.assets.length;
        for (uint256 j = 0; j < assetCount; j++) {
            _collectAsset(ss, proposalId, shwounId, vault, ss.assets[j], escrow);
        }
    }

    /// @dev Pull one (vault, asset) pro-rata share into the escrow: share = ceil(requested ×
    ///      snapshotBalance / total), capped by the vault's current balance (a withdrawal since
    ///      snapshot logs a ShortfallRecorded) and by the proposal's still-outstanding amount (so the
    ///      ceiling rounding can't over-collect). Credits the ACTUAL balance delta the escrow received
    ///      (M-04) to both the per-asset ledger (`collected`) and the per-vault tally (`pulled`, for
    ///      refunds), never the requested pull — so a fee/rebasing token can't overstate collection.
    function _collectAsset(
        ShwounsDAOTypes.SnapshotState storage ss,
        uint256 proposalId,
        uint256 shwounId,
        address vault,
        address asset,
        address escrow
    ) internal {
        uint256 snapshotBalance = ss.vaultSnapshot[shwounId][asset];
        if (snapshotBalance == 0) return;

        uint256 total = ss.totalSnapshotBalance[asset];
        // Pro-rata share of the requested amount, rounded UP. Ceiling matters: with floored
        // shares the per-vault dust sums to a few wei BELOW `requested`, which the all-or-nothing
        // finalize gate would then reject for a fully-funded proposal. Rounding up lets the
        // collection reach `requested` exactly (see the `outstanding` cap below).
        uint256 share = (ss.requestedAmount[asset] * snapshotBalance + total - 1) / total;

        uint256 currentBalance = asset == address(0)
            ? vault.balance
            : IERC20(asset).balanceOf(vault);

        uint256 actual = share;
        if (currentBalance < actual) {
            // The vault was (partly) drained since snapshot — a genuine shortfall for this vault.
            emit ShortfallRecorded(proposalId, shwounId, asset, actual - currentBalance);
            actual = currentBalance;
        }
        // Never pull more than is still outstanding for this proposal: caps the ceiling
        // over-collection so total collected lands exactly on `requested` (not a few wei over),
        // and guards the subtraction below.
        uint256 outstanding = ss.requestedAmount[asset] > ss.collected[asset]
            ? ss.requestedAmount[asset] - ss.collected[asset]
            : 0;
        if (actual > outstanding) actual = outstanding;

        if (actual > 0) {
            // M-04: credit the ACTUAL amount the escrow received (balance delta), never the
            // requested pull. For an allowlisted exact-transfer token this equals `actual`; a
            // fee/rebasing token would credit less, leaving the proposal under-collected so
            // finalize's solvency check blocks it — rather than overstating collection.
            uint256 balBefore = asset == address(0) ? escrow.balance : IERC20(asset).balanceOf(escrow);
            ShwounsVault(payable(vault)).pullProRata(proposalId, asset, escrow, actual);
            uint256 received =
                (asset == address(0) ? escrow.balance : IERC20(asset).balanceOf(escrow)) - balBefore;
            ss.collected[asset] += received; // C4: per-proposal ledger (isolates this proposal's funds)
            ss.pulled[shwounId][asset] += received; // M-03: per-vault actual contribution (for refunds)
            emit AssetCollectedFromVault(proposalId, shwounId, asset, received);
        }
    }

    // =========================================================================
    // finalize — makes the actual target.call(s) with accumulated funds
    // =========================================================================

    /// @notice Execute a fully-Collected proposal's actions from its escrow (all-or-nothing solvency
    ///         check, single global execution lock, retryable if a target reverts). Sets terminal
    ///         Executed last. The facade allocates the voter reward pool immediately after.
    /// @param proposalId The Collected proposal to finalize.
    function finalize(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        // Global execution lock FIRST (review §4: `require(!_executing)`). Only one proposal may
        // execute at a time, and no nested finalize — of this OR any other proposal — can run while
        // one is in flight. This is the C-01 fix: a recipient re-entering finalize hits this lock.
        if (ds.executing) revert AlreadyExecuting();
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        // Review §3: finalize is unavailable once the contribution refund has begun (a stuck
        // Collected proposal being unwound by governance can't also execute).
        if (ss.refundStarted) revert InvalidProposalState();
        address escrow = escrowAddressOf(ds, proposalId);

        // C4 all-or-nothing ledger gate + a solvency recheck against ACTUAL escrow balances
        // immediately before the lock (review §4). The escrow holds ONLY this proposal's funds, so
        // a check against its real balance can never draw on another proposal's money; any
        // shortfall (a negative rebase, or funds moved out between collect and finalize) BLOCKS
        // execution rather than executing under-funded — retry after a top-up, or unwind via refund.
        _requireSolvent(ss, escrow);

        // EFFECT before INTERACTION (CEI): set the lock + activeProposalId (→ the transient
        // Executing status). This — NOT p.executed — is the reentrancy "effect". During execution
        // the status is Executing, so BOTH a nested finalize (Collected gate + this lock) AND a
        // nested rescue (terminal gate, added in §A8) revert.
        ds.executing = true;
        ds.activeProposalId = proposalId;

        // Have the escrow execute EVERYTHING from its own identity and balance — both value-bearing
        // and governance actions (C-02: an `approve` here is granted by the escrow over the escrow's
        // own balance, never the shared pool). execute() bubbles any action's revert (DAOLogic must
        // NOT catch it) → atomic EVM rollback of the lock, the transient status, and every earlier
        // action; finalize stays retryable.
        _executeViaEscrow(ds._proposals[proposalId], escrow);

        // No external call happens between execute returning and these writes → no reentrancy
        // window. Clear the lock/authentication FIRST, then commit terminal Executed LAST
        // (round-6 finding 1 — setting Executed before the calls would let a reentrant rescue pass
        // its terminal gate mid-execution).
        ds.executing = false;
        ds.activeProposalId = 0;
        ss.finalized = true;
        ds._proposals[proposalId].executed = true;
        emit ProposalExecuted(proposalId);
    }

    /// @dev Ledger + actual-balance solvency check for every requested asset, against the escrow.
    function _requireSolvent(
        ShwounsDAOTypes.SnapshotState storage ss,
        address escrow
    ) internal view {
        for (uint256 j = 0; j < ss.assets.length; j++) {
            address asset = ss.assets[j];
            if (ss.collected[asset] < ss.requestedAmount[asset]) revert InsufficientCollected();
            uint256 bal = asset == address(0) ? escrow.balance : IERC20(asset).balanceOf(escrow);
            if (bal < ss.requestedAmount[asset]) revert InsufficientCollected();
        }
    }

    /// @dev Build the proposal's action list (GovernorBravo signature-form expanded to final
    ///      calldata via _fullCalldata) and have the escrow execute it.
    function _executeViaEscrow(
        ShwounsDAOTypes.Proposal storage p,
        address escrow
    ) internal {
        uint256 n = p.targets.length;
        address[] memory targets = new address[](n);
        uint256[] memory values = new uint256[](n);
        bytes[] memory cds = new bytes[](n);
        for (uint256 i = 0; i < n; i++) {
            targets[i] = p.targets[i];
            values[i] = p.values[i];
            cds[i] = _fullCalldata(p.signatures[i], p.calldatas[i]);
        }
        IProposalEscrow(escrow).execute(targets, values, cds);
    }

    // =========================================================================
    // Escrow address derivation + executor authentication (A1-A3)
    // =========================================================================

    /// @notice The deterministic escrow address for a proposal. EIP-1167 clone of the locked
    ///         implementation, CREATE2 salt = proposalId, deployer = this DAOLogic proxy (the
    ///         library executes in the facade's context, so `address(this)` is the proxy).
    function escrowAddressOf(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) internal view returns (address) {
        return Clones.predictDeterministicAddress(
            ds.proposalEscrowImplementation, bytes32(proposalId), address(this)
        );
    }

    /// @notice The runtime codehash every escrow clone must have. Well-defined ONLY because escrows
    ///         are identical-runtime EIP-1167 clones of one locked implementation (A3.4) — the
    ///         clone runtime embeds the impl address and nothing else. A non-clone contract forced
    ///         to a predicted address fails this check.
    function _expectedEscrowCodehash(address impl) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(hex"363d3d373d3d3d363d73", impl, hex"5af43d82803e903d91602b57fd5bf3")
        );
    }

    /// @notice The canonical executor-authentication predicate (review §5). True iff ALL hold:
    ///         (1) execution is in progress; (2) there is an active proposal that (3) is in the
    ///         Executing status; (4) `candidate` is exactly that proposal's deterministic escrow
    ///         address; and (5) the candidate's code is the expected clone codehash. It never trusts
    ///         a caller-supplied proposalId, escrow storage, tx.origin, or the escrow's self-report.
    /// @param candidate The address to authenticate (typically a governed contract's `msg.sender`).
    /// @return True iff `candidate` is the active proposal's escrow during its finalize frame.
    function isActiveExecutor(
        ShwounsDAOTypes.Storage storage ds,
        address candidate
    ) public view returns (bool) {
        if (!ds.executing) return false;
        uint256 pid = ds.activeProposalId;
        if (pid == 0) return false;
        if (state(ds, pid) != ShwounsDAOTypes.ProposalState.Executing) return false;
        if (candidate != escrowAddressOf(ds, pid)) return false;
        if (candidate.codehash != _expectedEscrowCodehash(ds.proposalEscrowImplementation)) return false;
        return true;
    }

    /// @notice Emitted when someone tops up a proposal's collected ledger to cover a shortfall.
    event ProposalToppedUp(uint256 indexed proposalId, address indexed asset, uint256 amount);

    /// @notice Top up a proposal's per-asset collected ledger so an under-collected (shortfall)
    ///         proposal can reach full funding and finalize (C4 / D2). Anyone may contribute: ETH
    ///         as msg.value (asset == address(0)); ERC-20s pulled via prior approval. Restricted
    ///         to assets the proposal actually requested, so funds can't be stranded.
    /// @dev These library functions run in the facade's context (internal linkage), so msg.value /
    ///      msg.sender are the facade call's; the facade's topUp wrapper is payable.
    /// @param proposalId The Collected proposal to top up.
    /// @param asset The asset to contribute; `address(0)` for native ETH (sent as msg.value).
    /// @param amount The amount to contribute (capped at the outstanding shortfall).
    function topUp(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address asset,
        uint256 amount
    ) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        if (amount == 0 || ss.requestedAmount[asset] == 0) revert InvalidTopUp();
        // L-02: cap at the outstanding shortfall — reject excess so over-funding can't be stranded.
        uint256 outstanding = ss.requestedAmount[asset] > ss.collected[asset]
            ? ss.requestedAmount[asset] - ss.collected[asset]
            : 0;
        if (amount > outstanding) revert InvalidTopUp();

        // Route into the proposal's escrow (per-proposal custody) and credit the ACTUAL delta (M-04).
        address escrow = escrowAddressOf(ds, proposalId);
        if (asset == address(0)) {
            if (msg.value != amount) revert InvalidTopUp();
            uint256 balBefore = escrow.balance;
            (bool ok, ) = escrow.call{ value: amount }("");
            if (!ok) revert InvalidTopUp();
            ss.collected[asset] += escrow.balance - balBefore;
        } else {
            if (msg.value != 0) revert InvalidTopUp();
            uint256 balBefore = IERC20(asset).balanceOf(escrow);
            IERC20(asset).safeTransferFrom(msg.sender, escrow, amount);
            ss.collected[asset] += IERC20(asset).balanceOf(escrow) - balBefore;
        }
        emit ProposalToppedUp(proposalId, asset, amount);
    }

    // =========================================================================
    // EIP-712 ballot constants (castVoteBySig). The proposal/update typehashes + the signed-proposals
    // and proposal-editing family moved to ShwounsDAOSignatures (A3 — EIP-170 split).
    // =========================================================================

    /// @dev EIP-712 typehashes. Pinned at compile time. DOMAIN_TYPEHASH/DOMAIN_NAME_HASH back
    ///      _domainSeparator (shared with ShwounsDAOSignatures); BALLOT_TYPEHASH backs castVoteBySig.
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 internal constant DOMAIN_NAME_HASH = keccak256("ShwounsDAO");

    /// @notice Thrown when a vote-by-sig recovers the zero address (malformed ECDSA signature).
    /// @dev Used by castVoteBySig (ecrecover returning address(0)). The proposal-signature errors
    ///      live in ShwounsDAOSignatures.
    error SigInvalid();

    /// @dev Same as _validateActionsAndThreshold but without the proposer-threshold check
    ///      (proposeBySigs enforces threshold differently — via combined signer power).
    /// @notice Validate a proposal's action arrays (lengths, count 1..10) WITHOUT a proposer-threshold
    ///         check. Exposed `public` only for cross-library linking (A3 split); not for external use.
    /// @dev `public` so ShwounsDAOSignatures can reach it cross-library (A3 split).
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    function _validateActionsAndThreshold_skip(
        ShwounsDAOTypes.Storage storage,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) public pure {
        if (targets.length != values.length ||
            targets.length != signatures.length ||
            targets.length != calldatas.length) revert ActionsArrayLengthMismatch();
        if (targets.length == 0) revert InvalidProposalActions();
        if (targets.length > 10) revert TooManyActions();
    }

    /// @notice The EIP-712 domain separator for ballot/proposal signatures. Exposed `public` only for
    ///         cross-library linking (A3 split); not intended for external callers.
    /// @dev `public` so ShwounsDAOSignatures can reach it cross-library (A3 split). castVoteBySig
    ///      (this library) reaches it as a same-library JUMP, so the ballot path is unaffected.
    /// @return The EIP-712 domain separator bound to this proxy + chain id.
    function _domainSeparator(ShwounsDAOTypes.Storage storage) public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, DOMAIN_NAME_HASH, block.chainid, address(this)));
    }

    // =========================================================================
    // Contribution refund (H-01, M-03) — paged, by ACTUAL per-vault contribution
    // =========================================================================

    /// @notice Emitted per (proposal, asset) when a vault's actual contribution is refunded to it.
    event StuckProposalRefunded(uint256 indexed proposalId, address indexed asset, uint256 amount);
    /// @notice Emitted after each refund page, reporting cursor progress over snapshotted vaults.
    event ProposalRefundProgress(uint256 indexed proposalId, uint256 refundProgress, uint256 total);
    /// @notice Emitted when the final refund page completes (terminal — enables residual rescue).
    event ProposalRefunded(uint256 indexed proposalId);

    /// @notice Thrown when a refund is attempted on a proposal already fully refunded.
    error AlreadyRefunded();

    /// @notice Permissionless contribution refund for a funded but DEAD proposal — Canceled or
    ///         Vetoed (H-01: cancel/veto are never blocked after funds move; the funds route here).
    ///         Pages over snapshotted vaults, returning each vault's ACTUAL contribution (M-03) back
    ///         to THAT vault from the escrow (F4 — the vault's receive() never reverts). Permissionless
    ///         is safe — destinations are the vaults themselves (from the registry), never the caller.
    ///         (A Collected proposal whose finalize is stuck uses the admin refundStuckProposal
    ///         instead, so a live proposal can't be permissionlessly forced into refund.)
    /// @param proposalId The Canceled or Vetoed (and funded) proposal to refund.
    /// @param batchSize The number of snapshotted vaults to refund this call.
    function refund(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) external {
        if (ds.executing) revert AlreadyExecuting();
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        if (s != ShwounsDAOTypes.ProposalState.Canceled && s != ShwounsDAOTypes.ProposalState.Vetoed) {
            revert InvalidProposalState();
        }
        _refundPaged(ds, proposalId, batchSize);
    }

    /// @notice Admin/governance last-resort refund for a Collected proposal whose finalize never
    ///         succeeds. Same paged, by-actual-contribution mechanics as refund(); kept admin-gated
    ///         (facade) so a live Collected proposal can't be permissionlessly forced into refund
    ///         (which would grief its finalize).
    /// @param proposalId The stuck Collected proposal to unwind.
    /// @param batchSize The number of snapshotted vaults to refund this call.
    function refundStuckProposal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) external {
        if (ds.executing) revert AlreadyExecuting();
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();
        _refundPaged(ds, proposalId, batchSize);
    }

    /// @dev Paged refund engine. Returns each snapshotted vault's ACTUAL pulled amount, for every
    ///      recorded asset (ss.assets — never a caller-supplied list, so no asset is omitted), back to
    ///      that vault. The cursor advances only after a page's transfers all succeed (a
    ///      reverted page rolls back atomically and does not advance), and `refunded` is committed
    ///      only after the FINAL page — so rescue's terminal gate opens only once every contribution
    ///      has been returned.
    function _refundPaged(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) internal {
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        if (ss.refunded) revert AlreadyRefunded();
        ss.refundStarted = true; // H-01: blocks finalize from here on

        address escrow = escrowAddressOf(ds, proposalId);
        uint256 n = ss.snapshottedVaults.length;
        uint256 start = ss.refundProgress;
        uint256 end = start + batchSize;
        if (end > n) end = n;

        for (uint256 i = start; i < end; i++) {
            _refundVault(ds, ss, escrow, proposalId, ss.snapshottedVaults[i]);
        }
        ss.refundProgress = end;
        emit ProposalRefundProgress(proposalId, end, n);

        if (end == n) {
            ss.refunded = true; // terminal — committed only after the final transfer (review §3)
            ss.finalized = true; // cannot finalize() again; surfaces as Executed for Collected
            emit ProposalRefunded(proposalId);
        }
    }

    /// @dev Refund one vault's actual contribution across every recorded asset, back to THAT VAULT
    ///      (not the current Noun owner), out of the escrow. Zeroes each pulled entry before transfer
    ///      so a re-page cannot double-refund (and a revert rolls the zeroing back atomically).
    /// @dev F4 (refund DoS): the contribution came FROM the vault, so it returns TO the vault. The
    ///      vault's receive() never reverts (ShwounsVault), so no recipient can brick the paged refund
    ///      or the terminal `refunded` flag (which gates rescueFromEscrow) — unlike pushing ETH to the
    ///      current Noun owner, who could be a contract that rejects ETH. The owner controls the vault
    ///      and can withdraw() the returned funds; a Noun that changed hands since the contribution no
    ///      longer mis-pays a new owner. (Benign: an ETH refund re-triggers the vault's markActive →
    ///      re-adds to the append-only active set, a no-op if present; recordSnapshot skips zero
    ///      balances. ERC-20 refunds don't hit receive(), so they don't re-add.)
    function _refundVault(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.SnapshotState storage ss,
        address escrow,
        uint256 proposalId,
        uint256 shwounId
    ) internal {
        address vault = ds.vaultRegistry.vaultOf(shwounId);
        uint256 assetCount = ss.assets.length;
        for (uint256 j = 0; j < assetCount; j++) {
            address asset = ss.assets[j];
            uint256 amt = ss.pulled[shwounId][asset];
            if (amt == 0) continue;
            ss.pulled[shwounId][asset] = 0;
            IProposalEscrow(escrow).payOut(asset, vault, amt);
            emit StuckProposalRefunded(proposalId, asset, amt);
        }
    }

    // =========================================================================
    // Residual recovery — permissionless, strictly terminal-gated (A8)
    // =========================================================================

    /// @notice Emitted when stray residual assets are swept from a terminal proposal's escrow to GR.
    event EscrowResidualRescued(
        uint256 indexed proposalId, uint8 kind, address indexed asset, uint256 tokenId, uint256 amount
    );

    /// @notice Recover stray residual assets left in a proposal's escrow, sending them to the
    ///         immutable GovernanceRewards sink. Permissionless but STRICTLY terminal-gated: only
    ///         after the proposal has reached a terminal state (Executed — committed by a successful
    ///         finalize OR by the refund path), and never while any execution is in flight. Before
    ///         terminal the escrow holds live proposal funding awaiting execution/refund, so
    ///         permissionless rescue is barred (it would be fund theft); during execution the status
    ///         is Executing (not Executed), so a reentrant rescue of the active proposal reverts here
    ///         (round-6 finding 1). The escrow performs a typed transfer to its own immutable sink —
    ///         never an arbitrary call, never a caller-supplied recipient, never touching auth.
    /// @param proposalId The terminal proposal whose escrow to sweep.
    /// @param kind The residual asset kind (ETH / ERC20 / ERC721 / ERC1155).
    /// @param asset The token contract (ignored for ETH).
    /// @param tokenId The token id (ERC-721/1155 only).
    /// @param amount The amount (ERC-1155 only).
    function rescueFromEscrow(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        AssetKind kind,
        address asset,
        uint256 tokenId,
        uint256 amount
    ) external {
        if (ds.executing) revert AlreadyExecuting(); // no recovery while a finalize is in flight
        // Terminal gate (review §8): a successful finalize committed Executed, OR the paged refund
        // committed completion (`refunded`). For a Canceled/Vetoed-then-refunded proposal, state()
        // still surfaces Canceled/Vetoed, so the refunded flag is the terminal signal.
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Executed
            && !ds._snapshotState[proposalId].refunded) {
            revert NotTerminal();
        }

        // Recompute the escrow address and verify its codehash (review §8): only a genuine clone at
        // the predicted address is driven.
        address escrow = escrowAddressOf(ds, proposalId);
        if (escrow.codehash != _expectedEscrowCodehash(ds.proposalEscrowImplementation)) {
            revert EscrowCodehashMismatch();
        }

        if (kind == AssetKind.ETH) {
            IProposalEscrow(escrow).sweepETHToSink();
        } else if (kind == AssetKind.ERC20) {
            IProposalEscrow(escrow).sweepERC20ToSink(asset);
        } else if (kind == AssetKind.ERC721) {
            IProposalEscrow(escrow).sweepERC721ToSink(asset, tokenId);
        } else {
            IProposalEscrow(escrow).sweepERC1155ToSink(asset, tokenId, amount);
        }
        emit EscrowResidualRescued(proposalId, uint8(kind), asset, tokenId, amount);
    }

    // =========================================================================
    // Dynamic quorum — V4-style "more against votes → higher quorum"
    // =========================================================================

    /// @notice Compute the quorum required for a proposal, given against-votes accumulated.
    ///         When checkpoints are configured, uses dynamic quorum: minBPS + (coefficient × againstBPS / 1e6).
    ///         When no checkpoints exist, falls back to the fixed `quorumVotesBPS` recorded at creation.
    /// @param proposalId The proposal whose quorum to compute.
    /// @return The required quorum in absolute votes.
    function quorumVotes(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) public view returns (uint256) {
        ShwounsDAOTypes.Proposal storage proposal = ds._proposals[proposalId];
        uint256 len = ds.quorumParamsCheckpoints.length;
        // Fall back to the fixed quorum captured at creation when there are no dynamic-quorum
        // checkpoints, OR when this proposal predates the first checkpoint. Without the second
        // clause, _getDynamicQuorumParamsAt returns all-zero params for a pre-first-checkpoint
        // block → a quorum of 0, letting an older proposal pass on a single FOR vote the moment
        // the DAO sets its first dynamic-quorum checkpoint (retroactive-zero bug).
        if (len == 0 || proposal.creationBlock < ds.quorumParamsCheckpoints[0].fromBlock) {
            return proposal.quorumVotes;
        }
        ShwounsDAOTypes.DynamicQuorumParams memory params =
            _getDynamicQuorumParamsAt(ds, proposal.creationBlock);
        return _dynamicQuorumVotes(proposal.againstVotes, proposal.totalSupply, params);
    }

    /// @dev Dynamic quorum (V4 parity): quorumBPS = min(maxQuorumVotesBPS, minQuorumVotesBPS +
    ///      coefficient × againstVotesBPS / 1e6), returned in absolute votes. More Against → higher
    ///      quorum, clamped to the configured max.
    function _dynamicQuorumVotes(
        uint256 againstVotes,
        uint256 totalSupply,
        ShwounsDAOTypes.DynamicQuorumParams memory params
    ) internal pure returns (uint256) {
        if (totalSupply == 0) return 0;
        uint256 againstVotesBPS = (10000 * againstVotes) / totalSupply;
        uint256 quorumAdjustmentBPS = (uint256(params.quorumCoefficient) * againstVotesBPS) / 1e6;
        uint256 adjustedQuorumBPS = uint256(params.minQuorumVotesBPS) + quorumAdjustmentBPS;
        uint256 finalBPS = adjustedQuorumBPS < uint256(params.maxQuorumVotesBPS)
            ? adjustedQuorumBPS
            : uint256(params.maxQuorumVotesBPS);
        return (totalSupply * finalBPS) / 10000;
    }

    /// @notice The dynamic-quorum params in effect at a given block (public view; Nouns parity).
    /// @param blockNumber The block to resolve params at.
    /// @return The dynamic-quorum params active at `blockNumber` (zeroed if before the first checkpoint).
    function getDynamicQuorumParamsAt(
        ShwounsDAOTypes.Storage storage ds,
        uint256 blockNumber
    ) external view returns (ShwounsDAOTypes.DynamicQuorumParams memory) {
        if (ds.quorumParamsCheckpoints.length == 0) {
            return ShwounsDAOTypes.DynamicQuorumParams(0, 0, 0);
        }
        return _getDynamicQuorumParamsAt(ds, blockNumber);
    }

    /// @dev Binary-search the quorum-params checkpoints for the entry in effect at `blockNumber`;
    ///      returns zeroed params for a block before the first checkpoint (callers fall back to the
    ///      fixed quorum recorded at proposal creation).
    function _getDynamicQuorumParamsAt(
        ShwounsDAOTypes.Storage storage ds,
        uint256 blockNumber
    ) internal view returns (ShwounsDAOTypes.DynamicQuorumParams memory) {
        uint32 bn = uint32(blockNumber);
        uint256 len = ds.quorumParamsCheckpoints.length;

        if (ds.quorumParamsCheckpoints[len - 1].fromBlock <= bn) {
            return ds.quorumParamsCheckpoints[len - 1].params;
        }

        if (ds.quorumParamsCheckpoints[0].fromBlock > bn) {
            // Block is older than the first checkpoint; treat as no dynamic params.
            return ShwounsDAOTypes.DynamicQuorumParams({
                minQuorumVotesBPS: 0,
                maxQuorumVotesBPS: 0,
                quorumCoefficient: 0
            });
        }

        // Binary search
        uint256 lower = 0;
        uint256 upper = len - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2;
            ShwounsDAOTypes.DynamicQuorumParamsCheckpoint memory cp = ds.quorumParamsCheckpoints[center];
            if (cp.fromBlock == bn) return cp.params;
            else if (cp.fromBlock < bn) lower = center;
            else upper = center - 1;
        }
        return ds.quorumParamsCheckpoints[lower].params;
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @notice Compute `bps` basis points of `number` (floored). Exposed `public` only for
    ///         cross-library linking (A3 split); not intended for external callers.
    /// @dev `public` so ShwounsDAOSignatures can reach it cross-library (A3 split).
    /// @param bps The basis points (1/10000).
    /// @param number The base value.
    /// @return The floored product `number * bps / 10000`.
    function bps2Uint(uint256 bps, uint256 number) public pure returns (uint256) {
        return (number * bps) / 10000;
    }
}
