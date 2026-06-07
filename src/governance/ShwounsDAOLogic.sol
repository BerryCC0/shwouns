// SPDX-License-Identifier: GPL-3.0

/// @title Shwouns DAO Logic — facade contract
///
/// @notice Thin facade over ShwounsDAOProposals library. Holds the canonical storage
///         (NounsDAO-style Storage struct accessed via the library). External entry
///         points delegate to the library where the real logic lives.
///
/// @dev MVP: governance lifecycle only. Admin / candidates / signed proposals /
///      objection period land in follow-up turns.

pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { ShwounsDAOTypes, ShwounsDAOEvents, ShwounsDAOStorage, IShwounsTokenLike } from "./ShwounsDAOInterfaces.sol";
import { ShwounsDAOProposals } from "./ShwounsDAOProposals.sol";
import { ShwounsDAOSignatures } from "./ShwounsDAOSignatures.sol";
import { ShwounsDAOQuorum } from "./ShwounsDAOQuorum.sol";
import { IShwounsVaultRegistry } from "../vault/IShwounsVaultRegistry.sol";

/// @notice Minimal interface to GR for the wiring this contract needs.
interface IGovernanceRewardsForDAO {
    /// @notice Reserve a proposal's voter reward pool (called inside finalize).
    /// @param proposalId The finalized proposal.
    function allocateProposalReward(uint256 proposalId) external;

    /// @notice Refund a voter's gas for a refundable vote (capped by GR).
    /// @param voter The voter to refund.
    /// @param amount The requested refund amount.
    function refundGas(address voter, uint256 amount) external;
}

contract ShwounsDAOLogic is ShwounsDAOStorage, ShwounsDAOEvents, Initializable, UUPSUpgradeable {
    using ShwounsDAOProposals for ShwounsDAOTypes.Storage;
    using ShwounsDAOSignatures for ShwounsDAOTypes.Storage;
    using ShwounsDAOQuorum for ShwounsDAOTypes.Storage;

    /// @notice GovernanceRewards reference (Phase 5). Settable once by admin, locked after.
    /// @notice GovernanceRewards reference (Phase 5). Settable once by admin, then locked.
    IGovernanceRewardsForDAO public governanceRewards;
    /// @notice True once `governanceRewards` has been set, after which it can never change.
    bool public governanceRewardsLocked;

    /// @notice Emitted once when the GovernanceRewards reference is set and locked.
    event GovernanceRewardsSet(address indexed gr);

    /// @notice Thrown when an admin-gated function is called by neither the admin nor active escrow.
    error OnlyAdmin();
    /// @notice Thrown when a setter or initialize is given a zero address.
    error InvalidAddress();
    /// @notice Thrown when a one-time setter is called after it has been locked.
    error AlreadyLocked();
    /// @notice Thrown when minQuorumVotesBPS is out of bounds.
    error InvalidMinQuorumVotesBPS();
    /// @notice Thrown when maxQuorumVotesBPS is out of bounds.
    error InvalidMaxQuorumVotesBPS();
    /// @notice Thrown when minQuorumVotesBPS exceeds maxQuorumVotesBPS.
    error MinQuorumBPSGreaterThanMaxQuorumBPS();

    // Dynamic-quorum BPS bounds (Nouns parity, from NounsDAOAdmin).
    /// @notice Lower bound for minQuorumVotesBPS (200 = 2%).
    uint16 public constant MIN_QUORUM_VOTES_BPS_LOWER_BOUND = 200;
    /// @notice Upper bound for minQuorumVotesBPS (2000 = 20%).
    uint16 public constant MIN_QUORUM_VOTES_BPS_UPPER_BOUND = 2_000;
    /// @notice Upper bound for maxQuorumVotesBPS (6000 = 60%).
    uint16 public constant MAX_QUORUM_VOTES_BPS_UPPER_BOUND = 6_000;

    // Admin parameter bounds (Nouns parity; 12-second blocks).
    /// @notice Lower bound for proposalThresholdBPS.
    uint256 public constant MIN_PROPOSAL_THRESHOLD_BPS = 1;
    /// @notice Upper bound for proposalThresholdBPS (1000 = 10%).
    uint256 public constant MAX_PROPOSAL_THRESHOLD_BPS = 1_000;      // 10%
    /// @notice Lower bound for votingPeriod (~1 day in 12s blocks).
    uint256 public constant MIN_VOTING_PERIOD_BLOCKS = 7_200;       // 1 day
    /// @notice Upper bound for votingPeriod (~2 weeks).
    uint256 public constant MAX_VOTING_PERIOD_BLOCKS = 100_800;     // 2 weeks
    /// @notice Lower bound for votingDelay (1 block).
    uint256 public constant MIN_VOTING_DELAY_BLOCKS = 1;
    /// @notice Upper bound for votingDelay (~2 weeks).
    uint256 public constant MAX_VOTING_DELAY_BLOCKS = 100_800;      // 2 weeks
    /// @notice Upper bound for the Updatable (proposal-editing) period (~7 days).
    uint256 public constant MAX_UPDATABLE_PERIOD_BLOCKS = 50_400;   // 7 days
    /// @notice Upper bound for the post-vote queue window (~7 days).
    uint256 public constant MAX_QUEUE_PERIOD_BLOCKS = 50_400;       // 7 days
    /// @notice Upper bound for the objection-period duration (~7 days).
    uint256 public constant MAX_OBJECTION_PERIOD_BLOCKS = 50_400;   // 7 days
    /// @notice Upper bound for the last-minute window (~7 days).
    uint256 public constant MAX_LAST_MINUTE_WINDOW_BLOCKS = 50_400; // 7 days

    /// @notice Thrown when votingPeriod is out of bounds.
    error InvalidVotingPeriod();
    /// @notice Thrown when votingDelay is out of bounds.
    error InvalidVotingDelay();
    /// @notice Thrown when proposalThresholdBPS is out of bounds.
    error InvalidProposalThresholdBPS();
    /// @notice Thrown when an updatable/queue/objection/last-minute period is out of bounds.
    error InvalidPeriod();

    /// @notice The maximum number of actions per proposal.
    /// @return The max actions (10).
    function proposalMaxOperations() public pure returns (uint256) { return 10; }

    /// @notice Admin gate. Accepts the structural admin OR the currently-authenticated active
    ///         proposal escrow (A5) — so an approved governance action, executing from its escrow,
    ///         can change DAO parameters / admin within its own finalize frame, while no other
    ///         caller (stale, forged, or cross-proposal) ever passes.
    modifier onlyAdmin() {
        if (msg.sender != ds.admin && !ds.isActiveExecutor(msg.sender)) revert OnlyAdmin();
        _;
    }

    /// @dev Bounds-check the governance params at `initialize` (and any future use): votingPeriod,
    ///      votingDelay, proposalThresholdBPS within their MIN/MAX, updatable period within MAX, and a
    ///      nonzero queue period (a zero queue window would Expire proposals the instant voting ends).
    function _validateGovParams(ShwounsDAOTypes.ShwounsDAOParams calldata p) internal pure {
        if (p.votingPeriod < MIN_VOTING_PERIOD_BLOCKS || p.votingPeriod > MAX_VOTING_PERIOD_BLOCKS)
            revert InvalidVotingPeriod();
        if (p.votingDelay < MIN_VOTING_DELAY_BLOCKS || p.votingDelay > MAX_VOTING_DELAY_BLOCKS)
            revert InvalidVotingDelay();
        if (p.proposalThresholdBPS < MIN_PROPOSAL_THRESHOLD_BPS || p.proposalThresholdBPS > MAX_PROPOSAL_THRESHOLD_BPS)
            revert InvalidProposalThresholdBPS();
        if (p.proposalUpdatablePeriodInBlocks > MAX_UPDATABLE_PERIOD_BLOCKS) revert InvalidPeriod();
        // A queue window of 0 would expire proposals the moment voting ends.
        if (p.proposalQueuePeriodInBlocks == 0 || p.proposalQueuePeriodInBlocks > MAX_QUEUE_PERIOD_BLOCKS)
            revert InvalidPeriod();
    }

    /// @notice Initialize the DAO. Deployed via UUPS proxy. Validates all governance params and
    ///         seeds the first dynamic-quorum checkpoint so dynamic quorum is live from block 0.
    /// @param admin_ The initial admin (the Bootstrap coordinator, later handed to the DAO itself).
    /// @param vetoer_ The initial vetoer (renounceable).
    /// @param shwouns_ The Shwouns token (voting-power source).
    /// @param vaultRegistry_ The vault registry (active-set + per-vault deployment).
    /// @param params Governance params (votingDelay/Period, thresholdBPS, updatable/queue periods).
    /// @param quorumParams The seed dynamic-quorum params (min/max BPS + coefficient).
    function initialize(
        address admin_,
        address vetoer_,
        IShwounsTokenLike shwouns_,
        IShwounsVaultRegistry vaultRegistry_,
        ShwounsDAOTypes.ShwounsDAOParams calldata params,
        ShwounsDAOTypes.DynamicQuorumParams calldata quorumParams
    ) external initializer {
        if (admin_ == address(0) || address(shwouns_) == address(0) || address(vaultRegistry_) == address(0))
            revert InvalidAddress();
        _validateGovParams(params);
        __UUPSUpgradeable_init();

        ds.admin = admin_;
        ds.vetoer = vetoer_;
        ds.shwouns = shwouns_;
        ds.vaultRegistry = vaultRegistry_;
        ds.votingDelay = params.votingDelay;
        ds.votingPeriod = params.votingPeriod;
        ds.proposalThresholdBPS = params.proposalThresholdBPS;
        ds.proposalUpdatablePeriodInBlocks = params.proposalUpdatablePeriodInBlocks;
        ds.proposalQueuePeriodInBlocks = params.proposalQueuePeriodInBlocks;

        // Seed the first dynamic-quorum checkpoint (bounds-checked). Legacy fixed-quorum fallback
        // tracks the seed's minimum (only ever used for a hypothetical pre-checkpoint proposal).
        // Calls the library directly (not the onlyAdmin facade wrapper), so the bounds checks still
        // run during init without the admin gate.
        ds.setDynamicQuorumParams(
            quorumParams.minQuorumVotesBPS, quorumParams.maxQuorumVotesBPS, quorumParams.quorumCoefficient
        );
        ds.quorumVotesBPS = quorumParams.minQuorumVotesBPS;
    }

    /// @notice Thrown when a UUPS upgrade is attempted by anything other than the active executor.
    error NotActiveExecutor();

    /// @notice UUPS upgrade authorization (A9). DAOLogic upgrades flow ONLY through an authenticated
    ///         active proposal escrow — never a standing admin/EOA — so the "self-upgrade is the
    ///         final action" (validated at queue) and "the old finalize frame clears authentication"
    ///         invariants always hold. A direct, non-executor upgradeTo reverts.
    function _authorizeUpgrade(address) internal view override {
        if (!ds.isActiveExecutor(msg.sender)) revert NotActiveExecutor();
    }

    // -------------------------------------------------------------------------
    // Propose
    // -------------------------------------------------------------------------

    /// @notice Create a proposal (see {ShwounsDAOProposals-propose}).
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @return The new proposal id.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        return ds.propose(targets, values, signatures, calldatas, description);
    }

    /// @notice Create a multi-Noun co-signed proposal (see {ShwounsDAOSignatures-proposeBySigs}).
    /// @param proposerSignatures The co-signers' EIP-712 signatures.
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @return The new proposal id.
    function proposeBySigs(
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        return ds.proposeBySigs(proposerSignatures, targets, values, signatures, calldatas, description);
    }

    /// @notice Invalidate one of your proposal signatures so proposeBySigs will reject it.
    /// @param sig The exact signature bytes to cancel.
    function cancelSig(bytes calldata sig) external {
        ds.cancelSig(sig);
    }

    // -- Proposal editing (Updatable window) --

    /// @notice Edit a proposal's actions + description in its Updatable window (proposer, no signers).
    /// @param proposalId The proposal to edit.
    /// @param targets The new action target addresses.
    /// @param values The new ETH value for each action.
    /// @param signatures The new function signature strings for each action.
    /// @param calldatas The new calldata (or args) for each action.
    /// @param description The new proposal description.
    /// @param updateMessage A human-readable note describing the edit.
    function updateProposal(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        string memory updateMessage
    ) external {
        ds.updateProposal(proposalId, targets, values, signatures, calldatas, description, updateMessage);
    }

    /// @notice Edit only a proposal's transactions in its Updatable window.
    /// @param proposalId The proposal to edit.
    /// @param targets The new action target addresses.
    /// @param values The new ETH value for each action.
    /// @param signatures The new function signature strings for each action.
    /// @param calldatas The new calldata (or args) for each action.
    /// @param updateMessage A human-readable note describing the edit.
    function updateProposalTransactions(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory updateMessage
    ) external {
        ds.updateProposalTransactions(proposalId, targets, values, signatures, calldatas, updateMessage);
    }

    /// @notice Edit only a proposal's description in its Updatable window.
    /// @param proposalId The proposal to edit.
    /// @param description The new proposal description.
    /// @param updateMessage A human-readable note describing the edit.
    function updateProposalDescription(
        uint256 proposalId,
        string calldata description,
        string calldata updateMessage
    ) external {
        ds.updateProposalDescription(proposalId, description, updateMessage);
    }

    /// @notice Edit a co-signed proposal in its Updatable window (all original signers must re-sign).
    /// @param proposalId The proposal to edit.
    /// @param proposerSignatures Re-signatures from every original signer (same set, same order).
    /// @param targets The new action target addresses.
    /// @param values The new ETH value for each action.
    /// @param signatures The new function signature strings for each action.
    /// @param calldatas The new calldata (or args) for each action.
    /// @param description The new proposal description.
    /// @param updateMessage A human-readable note describing the edit.
    function updateProposalBySigs(
        uint256 proposalId,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        string memory updateMessage
    ) external {
        ds.updateProposalBySigs(
            proposalId,
            proposerSignatures,
            ShwounsDAOSignatures.ProposalTxs(targets, values, signatures, calldatas),
            description,
            updateMessage
        );
    }

    /// @notice Compute the EIP-712 digest a co-signer signs (see {ShwounsDAOSignatures-proposalDigest}).
    /// @param proposer The address that will submit proposeBySigs.
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @param expirationTimestamp The signer's signature expiry.
    /// @return The EIP-712 typed-data digest to sign.
    function proposalDigest(
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        uint256 expirationTimestamp
    ) external view returns (bytes32) {
        return ds.proposalDigest(proposer, targets, values, signatures, calldatas, description, expirationTimestamp);
    }

    /// @notice Whether a signer has cancelled a given signature hash.
    /// @param signer The signer.
    /// @param sigHash The keccak hash of the signature bytes.
    /// @return True if cancelled.
    function isSigCancelled(address signer, bytes32 sigHash) external view returns (bool) {
        return ds.cancelledSigs[signer][sigHash];
    }

    /// @notice The co-signers of a proposal (empty for a normal propose()).
    /// @param proposalId The proposal id.
    /// @return The signer addresses.
    function proposalSigners(uint256 proposalId) external view returns (address[] memory) {
        return ds._proposals[proposalId].signers;
    }

    // -------------------------------------------------------------------------
    // Vote
    // -------------------------------------------------------------------------

    /// @notice Cast a vote on a proposal.
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    function castVote(uint256 proposalId, uint8 support) external {
        ds.castVote(proposalId, support);
    }

    /// @notice Cast a vote with an attached reason string.
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    /// @param reason A free-text reason emitted in the VoteCast event.
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        ds.castVoteWithReason(proposalId, support, reason);
    }

    /// @notice Cast a vote with an EIP-712 signature (gasless / relayed). Recovered signer = voter.
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    /// @param v The ECDSA signature `v` component.
    /// @param r The ECDSA signature `r` component.
    /// @param s The ECDSA signature `s` component.
    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external {
        ds.castVoteBySig(proposalId, support, v, r, s);
    }

    // -------------------------------------------------------------------------
    // State + getters
    // -------------------------------------------------------------------------

    /// @notice The current lifecycle state of a proposal.
    /// @param proposalId The proposal id.
    /// @return The proposal state.
    function state(uint256 proposalId) external view returns (ShwounsDAOTypes.ProposalState) {
        return ds.state(proposalId);
    }

    /// @notice A voter's receipt (hasVoted, support, votes) as a struct.
    /// @param proposalId The proposal id.
    /// @param voter The voter address.
    /// @return The voter's receipt.
    function getReceipt(uint256 proposalId, address voter) external view returns (ShwounsDAOTypes.Receipt memory) {
        return ds._proposals[proposalId].receipts[voter];
    }

    /// @notice Receipt as unpacked tuple — used by GovernanceRewards which doesn't want the struct dependency.
    /// @param proposalId The proposal id.
    /// @param voter The voter address.
    /// @return hasVoted Whether the voter voted.
    /// @return support The vote (0=Against, 1=For, 2=Abstain).
    /// @return votes The recorded voting weight.
    function getReceiptUnpacked(uint256 proposalId, address voter)
        external
        view
        returns (bool hasVoted, uint8 support, uint96 votes)
    {
        ShwounsDAOTypes.Receipt memory r = ds._proposals[proposalId].receipts[voter];
        return (r.hasVoted, r.support, r.votes);
    }

    /// @notice For/Against/Abstain vote totals for a proposal. Used by GovernanceRewards.
    /// @param proposalId The proposal id.
    /// @return forVotes Total For votes.
    /// @return againstVotes Total Against votes.
    /// @return abstainVotes Total Abstain votes.
    function proposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        return (p.forVotes, p.againstVotes, p.abstainVotes);
    }

    /// @notice The number of proposals created so far (also the latest proposal id).
    /// @return The proposal count.
    function proposalCount() external view returns (uint256) {
        return ds.proposalCount;
    }

    /// @notice The Shwouns token (voting-power source).
    /// @return The token.
    function shwouns() external view returns (IShwounsTokenLike) {
        return ds.shwouns;
    }

    /// @notice The vault registry (active-set + per-vault deployment).
    /// @return The registry.
    function vaultRegistry() external view returns (IShwounsVaultRegistry) {
        return ds.vaultRegistry;
    }

    /// @notice The voting delay, in blocks (Updatable window end → voting start).
    /// @return The voting delay in blocks.
    function votingDelay() external view returns (uint256) { return ds.votingDelay; }
    /// @notice The voting period, in blocks.
    /// @return The voting period in blocks.
    function votingPeriod() external view returns (uint256) { return ds.votingPeriod; }
    /// @notice The proposal threshold, in BPS of total supply.
    /// @return The proposal threshold BPS.
    function proposalThresholdBPS() external view returns (uint256) { return ds.proposalThresholdBPS; }
    /// @notice The legacy fixed-quorum BPS (fallback for pre-first-checkpoint proposals).
    /// @return The fixed quorum BPS.
    function quorumVotesBPS() external view returns (uint256) { return ds.quorumVotesBPS; }
    /// @notice The current admin (the DAO itself post-handoff).
    /// @return The admin address.
    function admin() external view returns (address) { return ds.admin; }
    /// @notice The current vetoer (zero once veto power is burned).
    /// @return The vetoer address.
    function vetoer() external view returns (address) { return ds.vetoer; }

    /// @notice A proposal's action arrays.
    /// @param proposalId The proposal id.
    /// @return targets The action target addresses.
    /// @return values The ETH value for each action.
    /// @return signatures The function signature strings for each action.
    /// @return calldatas The calldata (or args) for each action.
    function getActions(uint256 proposalId) external view returns (
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /// @notice Snapshot-phase paging progress for a proposal.
    /// @param proposalId The proposal id.
    /// @return progress Vaults snapshotted so far.
    /// @return target Total vaults to snapshot (frozen at queue).
    function snapshotProgress(uint256 proposalId) external view returns (uint256 progress, uint256 target) {
        return (ds._snapshotState[proposalId].snapshotProgress, ds._snapshotState[proposalId].snapshotTargetCount);
    }

    /// @notice Collect-phase paging progress for a proposal.
    /// @param proposalId The proposal id.
    /// @return progress Vaults collected so far.
    /// @return target Total snapshotted vaults to collect from.
    function collectProgress(uint256 proposalId) external view returns (uint256 progress, uint256 target) {
        return (
            ds._snapshotState[proposalId].collectProgress,
            ds._snapshotState[proposalId].snapshottedVaults.length
        );
    }

    /// @notice The assets (ETH at index 0, then ERC-20s) a proposal requests funding in.
    /// @param proposalId The proposal id.
    /// @return The asset addresses.
    function assetsForProposal(uint256 proposalId) external view returns (address[] memory) {
        return ds._snapshotState[proposalId].assets;
    }

    // -------------------------------------------------------------------------
    // Cancel / Veto
    // -------------------------------------------------------------------------

    /// @notice Cancel a proposal (see {ShwounsDAOProposals-cancel}).
    /// @param proposalId The proposal to cancel.
    function cancel(uint256 proposalId) external { ds.cancel(proposalId); }
    /// @notice Veto a proposal — vetoer only (see {ShwounsDAOProposals-veto}).
    /// @param proposalId The proposal to veto.
    function veto(uint256 proposalId) external { ds.veto(proposalId); }

    // -------------------------------------------------------------------------
    // Queue → recordSnapshot → collect → finalize
    // -------------------------------------------------------------------------

    /// @notice Queue a Succeeded proposal (see {ShwounsDAOProposals-queue}).
    /// @param proposalId The Succeeded proposal to queue.
    function queue(uint256 proposalId) external {
        ds.queue(proposalId);
    }

    /// @notice Page the queue-time vault-set freeze (M-05). Needed only for a set larger than the
    ///         batch frozen within queue(); small sets are fully frozen at queue and skip this.
    /// @param proposalId The Queued proposal whose freeze to advance.
    /// @param batchSize The number of additional vault indices to freeze this call.
    function freezeVaults(uint256 proposalId, uint256 batchSize) external {
        ds.freezeVaults(proposalId, batchSize);
    }

    /// @notice Page the snapshot phase (see {ShwounsDAOProposals-recordSnapshot}).
    /// @param proposalId The Queued proposal to snapshot.
    /// @param batchSize The number of frozen vaults to process this call.
    function recordSnapshot(uint256 proposalId, uint256 batchSize) external {
        ds.recordSnapshot(proposalId, batchSize);
    }

    /// @notice Pull pro-rata from the next `batchSize` snapshotted vaults into this proposal's
    ///         collected ledger. Paged strictly over the recorded snapshotted-vault list — no
    ///         caller-supplied vault IDs (C2).
    /// @param proposalId The Snapshotted proposal to collect for.
    /// @param batchSize The number of snapshotted vaults to process this call.
    function collect(uint256 proposalId, uint256 batchSize) external {
        ds.collect(proposalId, batchSize);
    }

    /// @notice Top up an under-collected proposal so it can finalize. ETH via msg.value, ERC-20
    ///         via prior approval; restricted to assets the proposal requested (C4 / D2).
    /// @param proposalId The Collected proposal to top up.
    /// @param asset The asset to contribute; `address(0)` for ETH (sent as msg.value).
    /// @param amount The amount to contribute (capped at the outstanding shortfall).
    function topUp(uint256 proposalId, address asset, uint256 amount) external payable {
        ds.topUp(proposalId, asset, amount);
    }

    /// @notice Finalize a Collected proposal (executes its actions, then allocates the reward pool).
    /// @param proposalId The Collected proposal to finalize.
    function finalize(uint256 proposalId) external {
        ds.finalize(proposalId);
        // Reward allocation occurs only AFTER terminal Executed is committed (review §4). Wrapped
        // in try/catch so a misconfigured GR doesn't brick finalize.
        if (address(governanceRewards) != address(0)) {
            try governanceRewards.allocateProposalReward(proposalId) {} catch {}
        }
    }

    // -------------------------------------------------------------------------
    // Execution model — per-proposal escrow + executor authentication (A1-A5)
    // -------------------------------------------------------------------------

    /// @notice Thrown when setting the ProposalEscrow implementation after it has been locked.
    error EscrowImplLocked();

    /// @notice Emitted once when the ProposalEscrow implementation is set and locked.
    event ProposalEscrowImplementationSet(address indexed impl);

    /// @notice Set the ProposalEscrow implementation (the EIP-1167 clone source). One-shot: set at
    ///         bootstrap, then permanently locked. Every proposal's escrow is a deterministic clone
    ///         of this implementation, and both the predicted escrow address and the expected clone
    ///         codehash derive from it — so it must never change once any proposal has queued.
    /// @param impl The ProposalEscrow implementation address (the clone source); locked after this call.
    function setProposalEscrowImplementation(address impl) external onlyAdmin {
        if (ds.proposalEscrowImplementationLocked) revert EscrowImplLocked();
        if (impl == address(0)) revert InvalidAddress();
        ds.proposalEscrowImplementation = impl;
        ds.proposalEscrowImplementationLocked = true;
        emit ProposalEscrowImplementationSet(impl);
    }

    /// @notice The locked ProposalEscrow implementation (clone source).
    /// @return The implementation address.
    function proposalEscrowImplementation() external view returns (address) {
        return ds.proposalEscrowImplementation;
    }

    /// @notice Whether the ProposalEscrow implementation has been set + permanently locked. Read by
    ///         the Bootstrap finalize prechecks (the storage field exists in `ds` but had no facade
    ///         getter).
    /// @return True once the implementation is set and locked.
    function proposalEscrowImplementationLocked() external view returns (bool) {
        return ds.proposalEscrowImplementationLocked;
    }

    /// @notice The deterministic escrow address for a proposal (clone of the locked impl, CREATE2
    ///         salt = proposalId, deployer = this proxy). Well-defined before the escrow is deployed.
    /// @param proposalId The proposal id.
    /// @return The proposal's escrow address.
    function escrowAddressOf(uint256 proposalId) external view returns (address) {
        return ds.escrowAddressOf(proposalId);
    }

    /// @notice The canonical executor-authentication result, read by governed contracts (via the
    ///         GovernanceAuthRegistry, §A5) and by this contract's own onlyAdmin gate.
    /// @param candidate The address to authenticate.
    /// @return True iff `candidate` is the active proposal's escrow during its finalize frame.
    function isActiveExecutor(address candidate) external view returns (bool) {
        return ds.isActiveExecutor(candidate);
    }

    /// @notice The global execution lock and the proposal currently Executing (0 = none). Exposed
    ///         for off-chain observers and the storage/auth invariant tests.
    /// @return True while a finalize is mid-flight.
    function executing() external view returns (bool) {
        return ds.executing;
    }

    /// @notice The proposal currently executing under the lock (0 = none).
    /// @return The active proposal id.
    function activeProposalId() external view returns (uint256) {
        return ds.activeProposalId;
    }

    /// @notice Emitted when an ERC-20 is added to or removed from the fundable-asset allowlist.
    event FundableAssetSet(address indexed asset, bool fundable);

    /// @notice DAO-curated allowlist of fundable ERC-20 assets (M-04). A proposal that requests a
    ///         non-allowlisted ERC-20 is rejected at queue. ETH (address(0)) is always fundable.
    ///         Governable (admin = DAO, callable from the active escrow).
    /// @param asset The ERC-20 to allow or disallow (must be nonzero; ETH is always fundable).
    /// @param fundable True to allow the asset, false to disallow.
    function setFundableAsset(address asset, bool fundable) external onlyAdmin {
        if (asset == address(0)) revert InvalidAddress(); // ETH is always fundable; don't key it
        ds.fundableAsset[asset] = fundable;
        emit FundableAssetSet(asset, fundable);
    }

    /// @notice Whether an asset may fund a proposal (ETH is always fundable).
    /// @param asset The asset to check.
    /// @return True if fundable.
    function isFundableAsset(address asset) external view returns (bool) {
        return asset == address(0) || ds.fundableAsset[asset];
    }

    /// @notice Cast a vote AND get gas refunded by GovernanceRewards (capped at GR's
    ///         maxRefundPerVote). Voters who don't care about gas refunds can use the
    ///         regular castVote().
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    function castRefundableVote(uint256 proposalId, uint8 support) external {
        uint256 startGas = gasleft();
        ds.castVote(proposalId, support);
        if (address(governanceRewards) != address(0)) {
            uint256 gasUsed = startGas - gasleft() + 30_000; // 30k buffer for the refund call
            uint256 refund = gasUsed * tx.gasprice;
            try governanceRewards.refundGas(msg.sender, refund) {} catch {}
        }
    }

    /// @notice castRefundableVote with an attached reason string.
    /// @param proposalId The proposal to vote on.
    /// @param support The vote: 0=Against, 1=For, 2=Abstain.
    /// @param reason A free-text reason emitted in the VoteCast event.
    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        uint256 startGas = gasleft();
        ds.castVoteWithReason(proposalId, support, reason);
        if (address(governanceRewards) != address(0)) {
            uint256 gasUsed = startGas - gasleft() + 30_000;
            uint256 refund = gasUsed * tx.gasprice;
            try governanceRewards.refundGas(msg.sender, refund) {} catch {}
        }
    }

    // -------------------------------------------------------------------------
    // Admin functions
    // -------------------------------------------------------------------------

    /// @notice Set the voting delay (blocks). Admin/governance only; bounds-checked.
    /// @param newVotingDelay The new voting delay in blocks.
    function setVotingDelay(uint256 newVotingDelay) external onlyAdmin {
        if (newVotingDelay < MIN_VOTING_DELAY_BLOCKS || newVotingDelay > MAX_VOTING_DELAY_BLOCKS)
            revert InvalidVotingDelay();
        uint256 oldVotingDelay = ds.votingDelay;
        ds.votingDelay = newVotingDelay;
        emit VotingDelaySet(oldVotingDelay, newVotingDelay);
    }

    /// @notice Set the voting period (blocks). Admin/governance only; bounds-checked.
    /// @param newVotingPeriod The new voting period in blocks.
    function setVotingPeriod(uint256 newVotingPeriod) external onlyAdmin {
        if (newVotingPeriod < MIN_VOTING_PERIOD_BLOCKS || newVotingPeriod > MAX_VOTING_PERIOD_BLOCKS)
            revert InvalidVotingPeriod();
        uint256 oldVotingPeriod = ds.votingPeriod;
        ds.votingPeriod = newVotingPeriod;
        emit VotingPeriodSet(oldVotingPeriod, newVotingPeriod);
    }

    /// @notice Set the proposal threshold (BPS of total supply). Admin/governance only; bounds-checked.
    /// @param newProposalThresholdBPS The new threshold in BPS.
    function setProposalThresholdBPS(uint256 newProposalThresholdBPS) external onlyAdmin {
        if (newProposalThresholdBPS < MIN_PROPOSAL_THRESHOLD_BPS || newProposalThresholdBPS > MAX_PROPOSAL_THRESHOLD_BPS)
            revert InvalidProposalThresholdBPS();
        uint256 oldProposalThresholdBPS = ds.proposalThresholdBPS;
        ds.proposalThresholdBPS = newProposalThresholdBPS;
        emit ProposalThresholdBPSSet(oldProposalThresholdBPS, newProposalThresholdBPS);
    }

    /// @notice Legacy fixed-quorum BPS — only a fallback for proposals created before the first
    ///         dynamic-quorum checkpoint. initialize() seeds a checkpoint, so this is inert in
    ///         normal operation; dynamic quorum is the source of truth.
    /// @param newQuorumVotesBPS The new fixed quorum, in BPS of total supply.
    function setQuorumVotesBPS(uint256 newQuorumVotesBPS) external onlyAdmin {
        ds.quorumVotesBPS = newQuorumVotesBPS;
    }

    /// @notice Set the last-minute window (blocks) that can trigger an objection period. Admin only.
    /// @param newLastMinuteWindowInBlocks The new last-minute window in blocks.
    function setLastMinuteWindowInBlocks(uint32 newLastMinuteWindowInBlocks) external onlyAdmin {
        if (newLastMinuteWindowInBlocks > MAX_LAST_MINUTE_WINDOW_BLOCKS) revert InvalidPeriod();
        ds.lastMinuteWindowInBlocks = newLastMinuteWindowInBlocks;
    }

    /// @notice Set the Updatable (proposal-editing) window (blocks). Admin/governance only.
    /// @param newPeriod The new updatable period in blocks (0 = no edit window).
    function setProposalUpdatablePeriodInBlocks(uint256 newPeriod) external onlyAdmin {
        if (newPeriod > MAX_UPDATABLE_PERIOD_BLOCKS) revert InvalidPeriod();
        ds.proposalUpdatablePeriodInBlocks = newPeriod;
    }

    /// @notice Set the post-vote queue window (blocks) before a Succeeded proposal Expires. Admin only.
    /// @param newPeriod The new queue period in blocks (must be nonzero).
    function setProposalQueuePeriodInBlocks(uint256 newPeriod) external onlyAdmin {
        if (newPeriod == 0 || newPeriod > MAX_QUEUE_PERIOD_BLOCKS) revert InvalidPeriod();
        ds.proposalQueuePeriodInBlocks = newPeriod;
    }

    /// @notice The Updatable (proposal-editing) window, in blocks.
    /// @return The updatable period in blocks.
    function proposalUpdatablePeriodInBlocks() external view returns (uint256) { return ds.proposalUpdatablePeriodInBlocks; }
    /// @notice The post-vote queue window, in blocks.
    /// @return The queue period in blocks.
    function proposalQueuePeriodInBlocks() external view returns (uint256) { return ds.proposalQueuePeriodInBlocks; }

    /// @notice Set the GovernanceRewards contract. Callable once.
    /// @param _gr The GovernanceRewards address.
    function setGovernanceRewards(address _gr) external onlyAdmin {
        if (governanceRewardsLocked) revert AlreadyLocked();
        if (_gr == address(0)) revert InvalidAddress();
        governanceRewards = IGovernanceRewardsForDAO(_gr);
        governanceRewardsLocked = true;
        emit GovernanceRewardsSet(_gr);
    }

    /// @notice Set how long the objection period extends voting (blocks). Admin/governance only.
    /// @param newObjectionPeriodDurationInBlocks The new objection-period duration in blocks.
    function setObjectionPeriodDurationInBlocks(uint32 newObjectionPeriodDurationInBlocks) external onlyAdmin {
        if (newObjectionPeriodDurationInBlocks > MAX_OBJECTION_PERIOD_BLOCKS) revert InvalidPeriod();
        ds.objectionPeriodDurationInBlocks = newObjectionPeriodDurationInBlocks;
    }

    /// @notice The last-minute window, in blocks.
    /// @return The last-minute window in blocks.
    function lastMinuteWindowInBlocks() external view returns (uint32) { return ds.lastMinuteWindowInBlocks; }
    /// @notice The objection-period duration, in blocks.
    /// @return The objection-period duration in blocks.
    function objectionPeriodDurationInBlocks() external view returns (uint32) { return ds.objectionPeriodDurationInBlocks; }

    // -- Admin transfer (two-step) --

    /// @notice Thrown when a pending-admin transfer targets an address that is neither the DAO nor zero.
    error AdminMustBeDAOOrZero();

    /// @notice A10.5: a pending admin may only be the DAO itself (address(this)) or address(0) —
    ///         never an EOA. The bootstrap handoff uses setAdminToDAO (direct); this two-step path
    ///         remains only for governance and is structurally barred from installing an EOA admin.
    /// @param newPendingAdmin The proposed admin — must be the DAO itself (address(this)) or zero.
    function setPendingAdmin(address newPendingAdmin) external onlyAdmin {
        if (newPendingAdmin != address(this) && newPendingAdmin != address(0)) revert AdminMustBeDAOOrZero();
        address oldPendingAdmin = ds.pendingAdmin;
        ds.pendingAdmin = newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /// @notice One-shot direct admin handoff to the DAO itself (A10.4). The DAO proxy can't submit
    ///         acceptAdmin autonomously, so the bootstrap coordinator (the current admin) calls this
    ///         to set the admin to the DAO directly. Afterwards the admin is the DAO, so admin
    ///         functions are reachable only through governance (an authenticated proposal escrow) —
    ///         no permanent EOA.
    function setAdminToDAO() external onlyAdmin {
        address oldAdmin = ds.admin;
        ds.admin = address(this);
        ds.pendingAdmin = address(0);
        emit NewAdmin(oldAdmin, address(this));
    }

    /// @notice Accept a pending admin transfer. Callable only by the pending admin.
    function acceptAdmin() external {
        if (msg.sender != ds.pendingAdmin) revert OnlyAdmin();
        address oldAdmin = ds.admin;
        address oldPendingAdmin = ds.pendingAdmin;
        ds.admin = ds.pendingAdmin;
        ds.pendingAdmin = address(0);
        emit NewAdmin(oldAdmin, ds.admin);
        emit NewPendingAdmin(oldPendingAdmin, address(0));
    }

    // -- Vetoer transfer (two-step) --

    /// @notice Propose a new vetoer (two-step). Callable only by the current vetoer.
    /// @param newPendingVetoer The proposed new vetoer.
    function setPendingVetoer(address newPendingVetoer) external {
        if (msg.sender != ds.vetoer) revert OnlyAdmin();
        ds.pendingVetoer = newPendingVetoer;
    }

    /// @notice Accept a pending vetoer transfer. Callable only by the pending vetoer.
    function acceptVetoer() external {
        if (msg.sender != ds.pendingVetoer) revert OnlyAdmin();
        address oldVetoer = ds.vetoer;
        ds.vetoer = ds.pendingVetoer;
        ds.pendingVetoer = address(0);
        emit NewVetoer(oldVetoer, ds.vetoer);
    }

    /// @notice Renounce the veto authority permanently. Once called, no veto possible.
    function burnVetoPower() external {
        if (msg.sender != ds.vetoer) revert OnlyAdmin();
        address oldVetoer = ds.vetoer;
        ds.vetoer = address(0);
        ds.pendingVetoer = address(0);
        emit NewVetoer(oldVetoer, address(0));
    }

    // -- Dynamic quorum params — checkpoint-admin lives in ShwounsDAOQuorum (audit F1: shrink the
    //    facade below EIP-170). These are thin onlyAdmin wrappers; the hot-path quorum COMPUTE
    //    (quorumVotes / getDynamicQuorumParamsAt) stays in ShwounsDAOProposals (see below). --

    /// @notice Set all three dynamic-quorum params (writes a checkpoint). Admin/governance only.
    /// @param newMinQuorumVotesBPS New minimum quorum, in BPS (200..2000).
    /// @param newMaxQuorumVotesBPS New maximum quorum, in BPS (<= 6000).
    /// @param newQuorumCoefficient New coefficient scaling quorum by against-vote share (1e6 fixed-point).
    function setDynamicQuorumParams(
        uint16 newMinQuorumVotesBPS,
        uint16 newMaxQuorumVotesBPS,
        uint32 newQuorumCoefficient
    ) external onlyAdmin {
        ds.setDynamicQuorumParams(newMinQuorumVotesBPS, newMaxQuorumVotesBPS, newQuorumCoefficient);
    }

    /// @notice Update only the minimum quorum BPS. Admin/governance only.
    /// @param newMinQuorumVotesBPS New minimum quorum, in BPS (200..2000).
    function setMinQuorumVotesBPS(uint16 newMinQuorumVotesBPS) external onlyAdmin {
        ds.setMinQuorumVotesBPS(newMinQuorumVotesBPS);
    }

    /// @notice Update only the maximum quorum BPS. Admin/governance only.
    /// @param newMaxQuorumVotesBPS New maximum quorum, in BPS (<= 6000).
    function setMaxQuorumVotesBPS(uint16 newMaxQuorumVotesBPS) external onlyAdmin {
        ds.setMaxQuorumVotesBPS(newMaxQuorumVotesBPS);
    }

    /// @notice Update only the quorum coefficient. Admin/governance only.
    /// @param newQuorumCoefficient New coefficient scaling quorum by against-vote share (1e6 fixed-point).
    function setQuorumCoefficient(uint32 newQuorumCoefficient) external onlyAdmin {
        ds.setQuorumCoefficient(newQuorumCoefficient);
    }

    /// @notice Current minimum quorum in absolute votes (minQuorumVotesBPS of total supply).
    /// @return The minimum quorum in votes.
    function minQuorumVotes() external view returns (uint256) {
        return ds.minQuorumVotes();
    }

    /// @notice Current maximum quorum in absolute votes (maxQuorumVotesBPS of total supply).
    /// @return The maximum quorum in votes.
    function maxQuorumVotes() external view returns (uint256) {
        return ds.maxQuorumVotes();
    }

    /// @notice The quorum (in votes) required for a proposal, accounting for dynamic quorum and
    ///         the fixed-quorum fallback for proposals created before the first checkpoint.
    /// @param proposalId The proposal id.
    /// @return The required quorum in votes.
    function quorumVotes(uint256 proposalId) external view returns (uint256) {
        return ds.quorumVotes(proposalId);
    }

    /// @notice Flat, mapping-free view of a proposal (id, votes, lifecycle, signers, state).
    /// @param proposalId The proposal id.
    /// @return The condensed proposal view.
    function proposals(uint256 proposalId) external view returns (ShwounsDAOTypes.ProposalCondensed memory) {
        return ds.proposals(proposalId);
    }

    /// @notice The current proposal threshold in absolute votes (proposalThresholdBPS of supply).
    /// @return The proposal threshold in votes.
    function proposalThreshold() external view returns (uint256) {
        return (ds.shwouns.totalSupply() * ds.proposalThresholdBPS) / 10000;
    }

    /// @notice The number of dynamic-quorum checkpoints recorded.
    /// @return The checkpoint count.
    function getDynamicQuorumParamsCheckpointCount() external view returns (uint256) {
        return ds.quorumParamsCheckpoints.length;
    }

    /// @notice The dynamic-quorum params in effect at a given block.
    /// @param blockNumber The block to resolve params at.
    /// @return The params active at that block.
    function getDynamicQuorumParamsAt(uint256 blockNumber)
        external
        view
        returns (ShwounsDAOTypes.DynamicQuorumParams memory)
    {
        return ds.getDynamicQuorumParamsAt(blockNumber);
    }

    /// @notice A dynamic-quorum checkpoint by index.
    /// @param index The checkpoint index.
    /// @return The checkpoint (fromBlock + params).
    function getDynamicQuorumParamsCheckpoint(uint256 index)
        external
        view
        returns (ShwounsDAOTypes.DynamicQuorumParamsCheckpoint memory)
    {
        return ds.quorumParamsCheckpoints[index];
    }

    // -------------------------------------------------------------------------
    // Stuck-fund recovery
    // -------------------------------------------------------------------------

    /// @notice Admin/governance last-resort refund for a Collected proposal whose finalize never
    ///         succeeds. Paged; returns each vault's ACTUAL contribution (M-03) back to THAT vault
    ///         (F4 — the vault's receive() never reverts, so no recipient can brick the unwind; the
    ///         Noun owner controls the vault and can withdraw()).
    /// @dev Only callable by admin (typically DAOLogic itself via another proposal's finalize). The
    ///      stuck-proposal must be in Collected state.
    /// @param proposalId The stuck Collected proposal to unwind.
    /// @param batchSize The number of snapshotted vaults to refund this call.
    function refundStuckProposal(uint256 proposalId, uint256 batchSize) external onlyAdmin {
        ds.refundStuckProposal(proposalId, batchSize);
    }

    /// @notice Permissionless contribution refund for a funded Canceled or Vetoed proposal (H-01).
    ///         Returns each snapshotted vault's actual contribution back to that vault (F4); paged.
    /// @param proposalId The Canceled or Vetoed (and funded) proposal to refund.
    /// @param batchSize The number of snapshotted vaults to refund this call.
    function refund(uint256 proposalId, uint256 batchSize) external {
        ds.refund(proposalId, batchSize);
    }

    /// @notice Recover stray residual assets from a TERMINAL proposal's escrow to the immutable
    ///         GovernanceRewards sink (A8). Permissionless — settled — but strictly terminal-gated
    ///         in the library (only after Executed; never mid-execution). ETH ignores asset/tokenId/
    ///         amount; ERC-20 uses `asset`; ERC-721 uses `asset`+`tokenId`; ERC-1155 uses
    ///         `asset`+`tokenId`(id)+`amount`.
    /// @param proposalId The terminal proposal whose escrow to sweep.
    /// @param kind The residual asset kind (ETH / ERC20 / ERC721 / ERC1155).
    /// @param asset The token contract (ignored for ETH).
    /// @param tokenId The token id (ERC-721/1155 only).
    /// @param amount The amount (ERC-1155 only).
    function rescueFromEscrow(
        uint256 proposalId,
        ShwounsDAOProposals.AssetKind kind,
        address asset,
        uint256 tokenId,
        uint256 amount
    ) external {
        ds.rescueFromEscrow(proposalId, kind, asset, tokenId, amount);
    }

    // -------------------------------------------------------------------------
    // Receive ETH (proposals can have value > 0; DAOLogic accumulates funds via collect)
    // -------------------------------------------------------------------------

    receive() external payable {}
}
