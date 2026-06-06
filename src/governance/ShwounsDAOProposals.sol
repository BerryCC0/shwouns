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

    error ProposerVotesBelowThreshold();
    error InvalidProposalActions();
    error ActionsArrayLengthMismatch();
    error TooManyActions();
    error ProposerAlreadyHasLiveProposal();
    error CannotVoteTwice();
    error InvalidSupportValue();
    error VotingClosed();
    error VotingNotOpen();
    error ProposalDoesNotExist();
    error ProposalAlreadyCanceled();
    error ProposerAboveThresholdAndNotVetoer();
    error InvalidProposalState();
    error AlreadyQueuedOrSettled();
    error SnapshotPhaseNotStarted();
    error SnapshotPhaseNotComplete();
    error CollectPhaseNotComplete();
    error VaultAlreadyCollected();
    error VaultNotSnapshotted();
    error InsufficientCollected();
    error InvalidTopUp();
    error NotShwounsHolder();
    error OnlyProposerOrVetoer();
    error OnlyVetoer();
    error NotAuthorized();
    error OnlyAgainstVotesDuringObjection();
    error AlreadyExecuting();
    error EscrowImplNotSet();
    error NotTerminal();
    error EscrowCodehashMismatch();
    error UpgradeMustBeLastAction();
    error AssetNotFundable();

    /// @notice Residual asset kinds for rescueFromEscrow (A8).
    enum AssetKind { ETH, ERC20, ERC721, ERC1155 }

    // -------------------------------------------------------------------------
    // Re-emit events to enable indexer simplicity (library events bubble up)
    // -------------------------------------------------------------------------

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
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);
    event ProposalCanceled(uint256 id);
    event ProposalQueued(uint256 id);
    event ProposalSnapshotted(uint256 indexed id, address indexed asset, uint256 totalSnapshotBalance);
    event ProposalCollected(uint256 indexed id);
    event ProposalExecuted(uint256 id);
    event ProposalVetoed(uint256 id);
    event VaultSnapshotted(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 balance);
    event AssetCollectedFromVault(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 amount);
    event ShortfallRecorded(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 missingAmount);
    event ProposalObjectionPeriodSet(uint256 indexed proposalId, uint256 objectionPeriodEndBlock);

    // =========================================================================
    // Propose
    // =========================================================================

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

    function _writeProposal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal {
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

    // =========================================================================
    // Vote
    // =========================================================================

    function castVote(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint8 support
    ) external {
        _castVoteInternal(ds, msg.sender, proposalId, support, "");
    }

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

    function cancel(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        // Cannot cancel at a terminal state, nor once funds have been collected into the DAO
        // (a stuck Collected proposal is unwound via refundStuckProposal, not cancel), nor while
        // the proposal is Executing — a reentrant callback could otherwise satisfy the cancel
        // threshold mid-finalize and write a contradictory terminal flag (review §6/§7).
        if (
            s == ShwounsDAOTypes.ProposalState.Canceled ||
            s == ShwounsDAOTypes.ProposalState.Defeated ||
            s == ShwounsDAOTypes.ProposalState.Expired ||
            s == ShwounsDAOTypes.ProposalState.Executed ||
            s == ShwounsDAOTypes.ProposalState.Vetoed ||
            s == ShwounsDAOTypes.ProposalState.Executing ||
            s == ShwounsDAOTypes.ProposalState.Collected
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
            ss.frozenVaultIds = ds.vaultRegistry.activeVaults();
            ss.snapshotTargetCount = ss.frozenVaultIds.length;
        }
        ss.queued = true;

        emit ProposalQueued(proposalId);
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

    function recordSnapshot(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        uint256 batchSize
    ) external {
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        if (s != ShwounsDAOTypes.ProposalState.Queued) revert InvalidProposalState();

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
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
            emit AssetCollectedFromVault(proposalId, shwounId, asset, received);
        }
    }

    // =========================================================================
    // finalize — makes the actual target.call(s) with accumulated funds
    // =========================================================================

    function finalize(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        // Global execution lock FIRST (review §4: `require(!_executing)`). Only one proposal may
        // execute at a time, and no nested finalize — of this OR any other proposal — can run while
        // one is in flight. This is the C-01 fix: a recipient re-entering finalize hits this lock.
        if (ds.executing) revert AlreadyExecuting();
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
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
    // Signed proposals (proposeBySigs) — EIP-712 multi-Noun co-signing
    // =========================================================================

    /// @dev EIP-712 typehashes. Pinned at compile time.
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 internal constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
    );
    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 internal constant UPDATE_PROPOSAL_TYPEHASH = keccak256(
        "UpdateProposal(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
    );
    bytes32 internal constant DOMAIN_NAME_HASH = keccak256("ShwounsDAO");

    event SignatureCancelled(address indexed signer, bytes sig);
    event ProposalCreatedWithSigners(uint256 indexed id, address[] signers);
    event ProposalUpdated(
        uint256 indexed id, address indexed proposer, address[] targets, uint256[] values,
        string[] signatures, bytes[] calldatas, string description, string updateMessage
    );
    event ProposalTransactionsUpdated(
        uint256 indexed id, address indexed proposer, address[] targets, uint256[] values,
        string[] signatures, bytes[] calldatas, string updateMessage
    );
    event ProposalDescriptionUpdated(
        uint256 indexed id, address indexed proposer, string description, string updateMessage
    );

    error SigExpired();
    error SigCancelled();
    error SigInvalid();
    error SignersBelowThreshold();
    error CanOnlyEditUpdatableProposals();
    error OnlyProposerCanEdit();
    error ProposerCannotUpdateProposalWithSigners();
    error SignerCountMismatch();

    /// @notice Create a proposal co-signed by multiple Shwoun holders. `msg.sender` is the
    ///         proposer and contributes its own votes; the signers' combined voting power plus the
    ///         proposer's must STRICTLY exceed the proposal threshold. Each signature binds the
    ///         proposer, the proposal actions, and that signer's own expiry, and is verified via
    ///         ERC-1271 (so smart-contract wallets can co-sign). Mirrors NounsDAOProposals.
    function proposeBySigs(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId) {
        if (proposerSignatures.length == 0) revert SignersBelowThreshold();
        _validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);

        // Create the proposal BEFORE verifying signatures. This makes signer de-duplication free:
        // a repeated signer's latestProposalIds already points at this just-created (Pending)
        // proposal, so _enforceOneLiveProposalFor reverts. proposer = msg.sender (set by _writeProposal).
        ds.proposalCount++;
        proposalId = ds.proposalCount;
        _writeProposal(ds, proposalId, targets, values, signatures, calldatas);

        (uint256 votes, address[] memory signers) = _verifySignersAndCountVotes(
            ds, proposerSignatures, targets, values, signatures, calldatas, description, proposalId
        );
        if (signers.length == 0) revert SignersBelowThreshold();
        // Strictly greater than the threshold (Nouns parity), same as the normal propose() path.
        if (votes <= bps2Uint(ds.proposalThresholdBPS, ds.shwouns.totalSupply())) {
            revert SignersBelowThreshold();
        }

        ds._proposals[proposalId].signers = signers;

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        emit ProposalCreated(
            proposalId, msg.sender, targets, values, signatures, calldatas, p.startBlock, p.endBlock, description
        );
        emit ProposalCreatedWithSigners(proposalId, signers);
    }

    /// @dev Verify each signer's signature, enforce one-live-proposal per signer (which also
    ///      de-duplicates signers against the just-created proposal), count the votes of signers
    ///      with voting power, then add the proposer (msg.sender) the same way. Returns the trimmed
    ///      signer set and total backing votes.
    function _verifySignersAndCountVotes(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        uint256 proposalId
    ) internal returns (uint256 votes, address[] memory signers) {
        bytes memory encodeData =
            _calcProposalEncodeData(msg.sender, targets, values, signatures, calldatas, description);

        signers = new address[](proposerSignatures.length);
        uint256 numSigners = 0;
        for (uint256 i = 0; i < proposerSignatures.length; i++) {
            _verifyProposalSignature(ds, PROPOSAL_TYPEHASH, encodeData, proposerSignatures[i]);

            address signer = proposerSignatures[i].signer;
            _enforceOneLiveProposalFor(ds, signer); // checkNoActiveProp + signer de-dup

            uint256 signerVotes = ds.shwouns.getPriorVotes(signer, block.number - 1);
            if (signerVotes == 0) continue;

            signers[numSigners++] = signer;
            ds.latestProposalIds[signer] = proposalId;
            votes += signerVotes;
        }
        // Trim the signer array to the entries actually used.
        assembly { mstore(signers, numSigners) }

        _enforceOneLiveProposalFor(ds, msg.sender);
        ds.latestProposalIds[msg.sender] = proposalId;
        votes += ds.shwouns.getPriorVotes(msg.sender, block.number - 1);
    }

    function _enforceOneLiveProposalFor(ShwounsDAOTypes.Storage storage ds, address proposer) internal view {
        if (ds.latestProposalIds[proposer] == 0) return;
        ShwounsDAOTypes.ProposalState s = state(ds, ds.latestProposalIds[proposer]);
        if (s == ShwounsDAOTypes.ProposalState.Active ||
            s == ShwounsDAOTypes.ProposalState.Pending ||
            s == ShwounsDAOTypes.ProposalState.ObjectionPeriod ||
            s == ShwounsDAOTypes.ProposalState.Updatable) {
            revert ProposerAlreadyHasLiveProposal();
        }
    }

    /// @notice Allow a signer to invalidate a specific signature. After cancellation,
    ///         proposeBySigs will reject that sig.
    function cancelSig(ShwounsDAOTypes.Storage storage ds, bytes calldata sig) external {
        ds.cancelledSigs[msg.sender][keccak256(sig)] = true;
        emit SignatureCancelled(msg.sender, sig);
    }

    // =========================================================================
    // Proposal editing (Updatable window) — Nouns parity
    // =========================================================================

    /// @dev A proposal may be edited only while Updatable, only by its proposer, and (for the
    ///      non-sig path) only if it has no co-signers (those must use updateProposalBySigs).
    function _checkProposalUpdatable(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        ShwounsDAOTypes.Proposal storage proposal
    ) internal view {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Updatable)
            revert CanOnlyEditUpdatableProposals();
        if (msg.sender != proposal.proposer) revert OnlyProposerCanEdit();
        if (proposal.signers.length > 0) revert ProposerCannotUpdateProposalWithSigners();
    }

    function updateProposal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        string memory updateMessage
    ) external {
        _updateProposalTransactionsInternal(ds, proposalId, targets, values, signatures, calldatas);
        emit ProposalUpdated(proposalId, msg.sender, targets, values, signatures, calldatas, description, updateMessage);
    }

    function updateProposalTransactions(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory updateMessage
    ) external {
        _updateProposalTransactionsInternal(ds, proposalId, targets, values, signatures, calldatas);
        emit ProposalTransactionsUpdated(proposalId, msg.sender, targets, values, signatures, calldatas, updateMessage);
    }

    function _updateProposalTransactionsInternal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal {
        _validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        _checkProposalUpdatable(ds, proposalId, p);
        p.targets = targets;
        p.values = values;
        p.signatures = signatures;
        p.calldatas = calldatas;
    }

    function updateProposalDescription(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        string calldata description,
        string calldata updateMessage
    ) external {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        _checkProposalUpdatable(ds, proposalId, p);
        emit ProposalDescriptionUpdated(proposalId, msg.sender, description, updateMessage);
    }

    /// @notice Edit a co-signed proposal during its Updatable window. The proposer submits and ALL
    ///         original signers must re-sign the update (same set, same order). Signatures bind the
    ///         proposalId via UPDATE_PROPOSAL_TYPEHASH.
    function updateProposalBySigs(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        string memory updateMessage
    ) external {
        _validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);
        if (proposerSignatures.length == 0) revert SignersBelowThreshold();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Updatable)
            revert CanOnlyEditUpdatableProposals();
        if (msg.sender != p.proposer) revert OnlyProposerCanEdit();

        address[] memory signers = p.signers;
        if (proposerSignatures.length != signers.length) revert SignerCountMismatch();

        bytes memory encodeData = abi.encodePacked(
            proposalId, _calcProposalEncodeData(msg.sender, targets, values, signatures, calldatas, description)
        );
        for (uint256 i = 0; i < proposerSignatures.length; i++) {
            _verifyProposalSignature(ds, UPDATE_PROPOSAL_TYPEHASH, encodeData, proposerSignatures[i]);
            // Assume the same signer set in the same order (avoids an O(n^2) membership search).
            if (signers[i] != proposerSignatures[i].signer) revert OnlyProposerCanEdit();
        }

        p.targets = targets;
        p.values = values;
        p.signatures = signatures;
        p.calldatas = calldatas;
        emit ProposalUpdated(proposalId, msg.sender, targets, values, signatures, calldatas, description, updateMessage);
    }

    /// @dev Same as _validateActionsAndThreshold but without the proposer-threshold check
    ///      (proposeBySigs enforces threshold differently — via combined signer power).
    function _validateActionsAndThreshold_skip(
        ShwounsDAOTypes.Storage storage,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal pure {
        if (targets.length != values.length ||
            targets.length != signatures.length ||
            targets.length != calldatas.length) revert ActionsArrayLengthMismatch();
        if (targets.length == 0) revert InvalidProposalActions();
        if (targets.length > 10) revert TooManyActions();
    }

    function _domainSeparator(ShwounsDAOTypes.Storage storage) internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, DOMAIN_NAME_HASH, block.chainid, address(this)));
    }

    /// @dev EIP-712 proposal encoding (Nouns parity). Binds the PROPOSER plus the proposal
    ///      actions; the per-signer expiry is folded in by _sigDigest. Earlier this hard-coded
    ///      proposer = address(0) and expiry = 0, so neither was bound — a relayer could swap the
    ///      submitter or the expiry while keeping a valid signature.
    function _calcProposalEncodeData(
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal pure returns (bytes memory) {
        return abi.encode(
            proposer,
            keccak256(abi.encodePacked(targets)),
            keccak256(abi.encodePacked(values)),
            _hashStringArray(signatures),
            _hashBytesArray(calldatas),
            keccak256(bytes(description))
        );
    }

    /// @dev The typed-data digest a given signer signs: binds the proposal encoding AND that
    ///      signer's own expiry, so the expiry is cryptographically committed (not malleable).
    function _sigDigest(
        ShwounsDAOTypes.Storage storage ds,
        bytes32 typehash,
        bytes memory encodeData,
        uint256 expirationTimestamp
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encodePacked(typehash, encodeData, expirationTimestamp));
        return ECDSA.toTypedDataHash(_domainSeparator(ds), structHash);
    }

    /// @dev Verify one signer's signature: not cancelled, valid (ERC-1271 via SignatureChecker so
    ///      contract wallets can co-sign), and not expired. `typehash` selects propose vs update.
    function _verifyProposalSignature(
        ShwounsDAOTypes.Storage storage ds,
        bytes32 typehash,
        bytes memory encodeData,
        ShwounsDAOTypes.ProposerSignature memory ps
    ) internal view {
        if (ds.cancelledSigs[ps.signer][keccak256(ps.sig)]) revert SigCancelled();
        bytes32 digest = _sigDigest(ds, typehash, encodeData, ps.expirationTimestamp);
        if (!SignatureChecker.isValidSignatureNow(ps.signer, digest, ps.sig)) revert SigInvalid();
        if (block.timestamp > ps.expirationTimestamp) revert SigExpired();
    }

    function _hashStringArray(string[] memory arr) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            hashes[i] = keccak256(bytes(arr[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _hashBytesArray(bytes[] memory arr) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            hashes[i] = keccak256(arr[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @notice Compute the EIP-712 digest a signer signs for a proposal. Off-chain UIs call this
    ///         to build the signing payload. ABI CHANGED vs the earlier unsound version: it now
    ///         takes the `proposer` (the address that will submit proposeBySigs) and the signer's
    ///         `expirationTimestamp`, both of which are bound into the digest.
    function proposalDigest(
        ShwounsDAOTypes.Storage storage ds,
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        uint256 expirationTimestamp
    ) external view returns (bytes32) {
        bytes memory encodeData =
            _calcProposalEncodeData(proposer, targets, values, signatures, calldatas, description);
        return _sigDigest(ds, PROPOSAL_TYPEHASH, encodeData, expirationTimestamp);
    }

    // =========================================================================
    // Refund a stuck proposal — last-resort recovery if finalize() never succeeds
    // =========================================================================

    event StuckProposalRefunded(uint256 indexed proposalId, address indexed asset, uint256 totalRefunded);

    /// @notice Distribute the funds the proposal's escrow holds (from collect()) back to the
    ///         snapshotted vaults' current owners, pro-rata to their snapshot share.
    /// @dev Only callable from facade via admin path. Marks the proposal as finalized to prevent
    ///      double-spend. Iterates snapshottedVaults; the per-vault actually-pulled refund + paging
    ///      redesign (M-03) lands in §C. Here the funds simply come from the per-proposal escrow.
    function refundStuckProposal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] calldata assetsToRefund
    ) external {
        // No recovery while a finalize is in flight (review §6 — reject refund globally while the
        // execution lock is held; the active proposal is itself unreachable here since its state is
        // Executing, not Collected).
        if (ds.executing) revert AlreadyExecuting();
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();

        address escrow = escrowAddressOf(ds, proposalId);
        for (uint256 a = 0; a < assetsToRefund.length; a++) {
            address asset = assetsToRefund[a];
            uint256 distributed = _refundAsset(ds, ss, escrow, asset);
            emit StuckProposalRefunded(proposalId, asset, distributed);
        }

        ss.finalized = true; // mark as terminal — cannot finalize() again
        ds._proposals[proposalId].executed = true; // surface as Executed in state()
    }

    /// @dev Distribute one asset's collected total, pro-rata by snapshot share, to the current Noun
    ///      owners, paying out of the proposal's escrow. Distributes only what was ACTUALLY
    ///      collected (never the snapshot-derived requested amount). Zeroes the ledger to bar any
    ///      double refund. Returns the amount distributed.
    function _refundAsset(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.SnapshotState storage ss,
        address escrow,
        address asset
    ) internal returns (uint256 distributed) {
        uint256 total = ss.totalSnapshotBalance[asset];
        uint256 collectedTotal = ss.collected[asset];
        if (total == 0 || collectedTotal == 0) return 0;
        uint256 vaultCount = ss.snapshottedVaults.length;
        for (uint256 i = 0; i < vaultCount; i++) {
            uint256 shwounId = ss.snapshottedVaults[i];
            uint256 snap = ss.vaultSnapshot[shwounId][asset];
            if (snap == 0) continue;
            uint256 share = (collectedTotal * snap) / total;
            if (share == 0) continue;
            IProposalEscrow(escrow).payOut(asset, ds.shwouns.ownerOf(shwounId), share);
            distributed += share;
        }
        ss.collected[asset] = 0; // drained — prevent any double refund
    }

    // =========================================================================
    // Residual recovery — permissionless, strictly terminal-gated (A8)
    // =========================================================================

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
    function rescueFromEscrow(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        AssetKind kind,
        address asset,
        uint256 tokenId,
        uint256 amount
    ) external {
        if (ds.executing) revert AlreadyExecuting(); // no recovery while a finalize is in flight
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Executed) revert NotTerminal();

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
    function getDynamicQuorumParamsAt(
        ShwounsDAOTypes.Storage storage ds,
        uint256 blockNumber
    ) external view returns (ShwounsDAOTypes.DynamicQuorumParams memory) {
        if (ds.quorumParamsCheckpoints.length == 0) {
            return ShwounsDAOTypes.DynamicQuorumParams(0, 0, 0);
        }
        return _getDynamicQuorumParamsAt(ds, blockNumber);
    }

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

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
    }
}
