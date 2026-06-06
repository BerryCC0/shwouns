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
import { IShwounsVaultRegistry } from "../vault/IShwounsVaultRegistry.sol";

/// @notice Minimal interface to GR for the wiring this contract needs.
interface IGovernanceRewardsForDAO {
    function allocateProposalReward(uint256 proposalId) external;
    function refundGas(address voter, uint256 amount) external;
}

contract ShwounsDAOLogic is ShwounsDAOStorage, ShwounsDAOEvents, Initializable, UUPSUpgradeable {
    using ShwounsDAOProposals for ShwounsDAOTypes.Storage;

    /// @notice GovernanceRewards reference (Phase 5). Settable once by admin, locked after.
    IGovernanceRewardsForDAO public governanceRewards;
    bool public governanceRewardsLocked;

    event GovernanceRewardsSet(address indexed gr);

    error OnlyAdmin();
    error InvalidAddress();
    error AlreadyLocked();
    error InvalidMinQuorumVotesBPS();
    error InvalidMaxQuorumVotesBPS();
    error MinQuorumBPSGreaterThanMaxQuorumBPS();

    // Dynamic-quorum BPS bounds (Nouns parity, from NounsDAOAdmin).
    uint16 public constant MIN_QUORUM_VOTES_BPS_LOWER_BOUND = 200;
    uint16 public constant MIN_QUORUM_VOTES_BPS_UPPER_BOUND = 2_000;
    uint16 public constant MAX_QUORUM_VOTES_BPS_UPPER_BOUND = 6_000;

    // Admin parameter bounds (Nouns parity; 12-second blocks).
    uint256 public constant MIN_PROPOSAL_THRESHOLD_BPS = 1;
    uint256 public constant MAX_PROPOSAL_THRESHOLD_BPS = 1_000;      // 10%
    uint256 public constant MIN_VOTING_PERIOD_BLOCKS = 7_200;       // 1 day
    uint256 public constant MAX_VOTING_PERIOD_BLOCKS = 100_800;     // 2 weeks
    uint256 public constant MIN_VOTING_DELAY_BLOCKS = 1;
    uint256 public constant MAX_VOTING_DELAY_BLOCKS = 100_800;      // 2 weeks
    uint256 public constant MAX_UPDATABLE_PERIOD_BLOCKS = 50_400;   // 7 days
    uint256 public constant MAX_QUEUE_PERIOD_BLOCKS = 50_400;       // 7 days
    uint256 public constant MAX_OBJECTION_PERIOD_BLOCKS = 50_400;   // 7 days
    uint256 public constant MAX_LAST_MINUTE_WINDOW_BLOCKS = 50_400; // 7 days

    error InvalidVotingPeriod();
    error InvalidVotingDelay();
    error InvalidProposalThresholdBPS();
    error InvalidPeriod();

    /// @notice The maximum number of actions per proposal.
    function proposalMaxOperations() public pure returns (uint256) { return 10; }

    /// @notice Admin gate. Accepts the structural admin OR the currently-authenticated active
    ///         proposal escrow (A5) — so an approved governance action, executing from its escrow,
    ///         can change DAO parameters / admin within its own finalize frame, while no other
    ///         caller (stale, forged, or cross-proposal) ever passes.
    modifier onlyAdmin() {
        if (msg.sender != ds.admin && !ds.isActiveExecutor(msg.sender)) revert OnlyAdmin();
        _;
    }

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
        _setDynamicQuorumParams(
            quorumParams.minQuorumVotesBPS, quorumParams.maxQuorumVotesBPS, quorumParams.quorumCoefficient
        );
        ds.quorumVotesBPS = quorumParams.minQuorumVotesBPS;
    }

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

    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        return ds.propose(targets, values, signatures, calldatas, description);
    }

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

    function cancelSig(bytes calldata sig) external {
        ds.cancelSig(sig);
    }

    // -- Proposal editing (Updatable window) --

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

    function updateProposalDescription(
        uint256 proposalId,
        string calldata description,
        string calldata updateMessage
    ) external {
        ds.updateProposalDescription(proposalId, description, updateMessage);
    }

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
        ds.updateProposalBySigs(proposalId, proposerSignatures, targets, values, signatures, calldatas, description, updateMessage);
    }

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

    function isSigCancelled(address signer, bytes32 sigHash) external view returns (bool) {
        return ds.cancelledSigs[signer][sigHash];
    }

    function proposalSigners(uint256 proposalId) external view returns (address[] memory) {
        return ds._proposals[proposalId].signers;
    }

    // -------------------------------------------------------------------------
    // Vote
    // -------------------------------------------------------------------------

    function castVote(uint256 proposalId, uint8 support) external {
        ds.castVote(proposalId, support);
    }

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        ds.castVoteWithReason(proposalId, support, reason);
    }

    /// @notice Cast a vote with an EIP-712 signature (gasless / relayed). Recovered signer = voter.
    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external {
        ds.castVoteBySig(proposalId, support, v, r, s);
    }

    // -------------------------------------------------------------------------
    // State + getters
    // -------------------------------------------------------------------------

    function state(uint256 proposalId) external view returns (ShwounsDAOTypes.ProposalState) {
        return ds.state(proposalId);
    }

    function getReceipt(uint256 proposalId, address voter) external view returns (ShwounsDAOTypes.Receipt memory) {
        return ds._proposals[proposalId].receipts[voter];
    }

    /// @notice Receipt as unpacked tuple — used by GovernanceRewards which doesn't want the struct dependency.
    function getReceiptUnpacked(uint256 proposalId, address voter)
        external
        view
        returns (bool hasVoted, uint8 support, uint96 votes)
    {
        ShwounsDAOTypes.Receipt memory r = ds._proposals[proposalId].receipts[voter];
        return (r.hasVoted, r.support, r.votes);
    }

    /// @notice For/Against/Abstain vote totals for a proposal. Used by GovernanceRewards.
    function proposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        return (p.forVotes, p.againstVotes, p.abstainVotes);
    }

    function proposalCount() external view returns (uint256) {
        return ds.proposalCount;
    }

    function shwouns() external view returns (IShwounsTokenLike) {
        return ds.shwouns;
    }

    function vaultRegistry() external view returns (IShwounsVaultRegistry) {
        return ds.vaultRegistry;
    }

    function votingDelay() external view returns (uint256) { return ds.votingDelay; }
    function votingPeriod() external view returns (uint256) { return ds.votingPeriod; }
    function proposalThresholdBPS() external view returns (uint256) { return ds.proposalThresholdBPS; }
    function quorumVotesBPS() external view returns (uint256) { return ds.quorumVotesBPS; }
    function admin() external view returns (address) { return ds.admin; }
    function vetoer() external view returns (address) { return ds.vetoer; }

    function getActions(uint256 proposalId) external view returns (
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function snapshotProgress(uint256 proposalId) external view returns (uint256 progress, uint256 target) {
        return (ds._snapshotState[proposalId].snapshotProgress, ds._snapshotState[proposalId].snapshotTargetCount);
    }

    function collectProgress(uint256 proposalId) external view returns (uint256 progress, uint256 target) {
        return (
            ds._snapshotState[proposalId].collectProgress,
            ds._snapshotState[proposalId].snapshottedVaults.length
        );
    }

    function assetsForProposal(uint256 proposalId) external view returns (address[] memory) {
        return ds._snapshotState[proposalId].assets;
    }

    // -------------------------------------------------------------------------
    // Cancel / Veto
    // -------------------------------------------------------------------------

    function cancel(uint256 proposalId) external { ds.cancel(proposalId); }
    function veto(uint256 proposalId) external { ds.veto(proposalId); }

    // -------------------------------------------------------------------------
    // Queue → recordSnapshot → collect → finalize
    // -------------------------------------------------------------------------

    function queue(uint256 proposalId) external {
        ds.queue(proposalId);
    }

    function recordSnapshot(uint256 proposalId, uint256 batchSize) external {
        ds.recordSnapshot(proposalId, batchSize);
    }

    /// @notice Pull pro-rata from the next `batchSize` snapshotted vaults into this proposal's
    ///         collected ledger. Paged strictly over the recorded snapshotted-vault list — no
    ///         caller-supplied vault IDs (C2).
    function collect(uint256 proposalId, uint256 batchSize) external {
        ds.collect(proposalId, batchSize);
    }

    /// @notice Top up an under-collected proposal so it can finalize. ETH via msg.value, ERC-20
    ///         via prior approval; restricted to assets the proposal requested (C4 / D2).
    function topUp(uint256 proposalId, address asset, uint256 amount) external payable {
        ds.topUp(proposalId, asset, amount);
    }

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

    error EscrowImplLocked();

    event ProposalEscrowImplementationSet(address indexed impl);

    /// @notice Set the ProposalEscrow implementation (the EIP-1167 clone source). One-shot: set at
    ///         bootstrap, then permanently locked. Every proposal's escrow is a deterministic clone
    ///         of this implementation, and both the predicted escrow address and the expected clone
    ///         codehash derive from it — so it must never change once any proposal has queued.
    function setProposalEscrowImplementation(address impl) external onlyAdmin {
        if (ds.proposalEscrowImplementationLocked) revert EscrowImplLocked();
        if (impl == address(0)) revert InvalidAddress();
        ds.proposalEscrowImplementation = impl;
        ds.proposalEscrowImplementationLocked = true;
        emit ProposalEscrowImplementationSet(impl);
    }

    function proposalEscrowImplementation() external view returns (address) {
        return ds.proposalEscrowImplementation;
    }

    /// @notice The deterministic escrow address for a proposal (clone of the locked impl, CREATE2
    ///         salt = proposalId, deployer = this proxy). Well-defined before the escrow is deployed.
    function escrowAddressOf(uint256 proposalId) external view returns (address) {
        return ds.escrowAddressOf(proposalId);
    }

    /// @notice The canonical executor-authentication result, read by governed contracts (via the
    ///         GovernanceAuthRegistry, §A5) and by this contract's own onlyAdmin gate.
    function isActiveExecutor(address candidate) external view returns (bool) {
        return ds.isActiveExecutor(candidate);
    }

    /// @notice The global execution lock and the proposal currently Executing (0 = none). Exposed
    ///         for off-chain observers and the storage/auth invariant tests.
    function executing() external view returns (bool) {
        return ds.executing;
    }

    function activeProposalId() external view returns (uint256) {
        return ds.activeProposalId;
    }

    /// @notice Cast a vote AND get gas refunded by GovernanceRewards (capped at GR's
    ///         maxRefundPerVote). Voters who don't care about gas refunds can use the
    ///         regular castVote().
    function castRefundableVote(uint256 proposalId, uint8 support) external {
        uint256 startGas = gasleft();
        ds.castVote(proposalId, support);
        if (address(governanceRewards) != address(0)) {
            uint256 gasUsed = startGas - gasleft() + 30_000; // 30k buffer for the refund call
            uint256 refund = gasUsed * tx.gasprice;
            try governanceRewards.refundGas(msg.sender, refund) {} catch {}
        }
    }

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

    function setVotingDelay(uint256 newVotingDelay) external onlyAdmin {
        if (newVotingDelay < MIN_VOTING_DELAY_BLOCKS || newVotingDelay > MAX_VOTING_DELAY_BLOCKS)
            revert InvalidVotingDelay();
        uint256 oldVotingDelay = ds.votingDelay;
        ds.votingDelay = newVotingDelay;
        emit VotingDelaySet(oldVotingDelay, newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) external onlyAdmin {
        if (newVotingPeriod < MIN_VOTING_PERIOD_BLOCKS || newVotingPeriod > MAX_VOTING_PERIOD_BLOCKS)
            revert InvalidVotingPeriod();
        uint256 oldVotingPeriod = ds.votingPeriod;
        ds.votingPeriod = newVotingPeriod;
        emit VotingPeriodSet(oldVotingPeriod, newVotingPeriod);
    }

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
    function setQuorumVotesBPS(uint256 newQuorumVotesBPS) external onlyAdmin {
        ds.quorumVotesBPS = newQuorumVotesBPS;
    }

    function setLastMinuteWindowInBlocks(uint32 newLastMinuteWindowInBlocks) external onlyAdmin {
        if (newLastMinuteWindowInBlocks > MAX_LAST_MINUTE_WINDOW_BLOCKS) revert InvalidPeriod();
        ds.lastMinuteWindowInBlocks = newLastMinuteWindowInBlocks;
    }

    function setProposalUpdatablePeriodInBlocks(uint256 newPeriod) external onlyAdmin {
        if (newPeriod > MAX_UPDATABLE_PERIOD_BLOCKS) revert InvalidPeriod();
        ds.proposalUpdatablePeriodInBlocks = newPeriod;
    }

    function setProposalQueuePeriodInBlocks(uint256 newPeriod) external onlyAdmin {
        if (newPeriod == 0 || newPeriod > MAX_QUEUE_PERIOD_BLOCKS) revert InvalidPeriod();
        ds.proposalQueuePeriodInBlocks = newPeriod;
    }

    function proposalUpdatablePeriodInBlocks() external view returns (uint256) { return ds.proposalUpdatablePeriodInBlocks; }
    function proposalQueuePeriodInBlocks() external view returns (uint256) { return ds.proposalQueuePeriodInBlocks; }

    /// @notice Set the GovernanceRewards contract. Callable once.
    function setGovernanceRewards(address _gr) external onlyAdmin {
        if (governanceRewardsLocked) revert AlreadyLocked();
        if (_gr == address(0)) revert InvalidAddress();
        governanceRewards = IGovernanceRewardsForDAO(_gr);
        governanceRewardsLocked = true;
        emit GovernanceRewardsSet(_gr);
    }

    function setObjectionPeriodDurationInBlocks(uint32 newObjectionPeriodDurationInBlocks) external onlyAdmin {
        if (newObjectionPeriodDurationInBlocks > MAX_OBJECTION_PERIOD_BLOCKS) revert InvalidPeriod();
        ds.objectionPeriodDurationInBlocks = newObjectionPeriodDurationInBlocks;
    }

    function lastMinuteWindowInBlocks() external view returns (uint32) { return ds.lastMinuteWindowInBlocks; }
    function objectionPeriodDurationInBlocks() external view returns (uint32) { return ds.objectionPeriodDurationInBlocks; }

    // -- Admin transfer (two-step) --

    function setPendingAdmin(address newPendingAdmin) external onlyAdmin {
        address oldPendingAdmin = ds.pendingAdmin;
        ds.pendingAdmin = newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

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

    function setPendingVetoer(address newPendingVetoer) external {
        if (msg.sender != ds.vetoer) revert OnlyAdmin();
        ds.pendingVetoer = newPendingVetoer;
    }

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

    // -- Dynamic quorum params --

    function setDynamicQuorumParams(
        uint16 newMinQuorumVotesBPS,
        uint16 newMaxQuorumVotesBPS,
        uint32 newQuorumCoefficient
    ) public onlyAdmin {
        _setDynamicQuorumParams(newMinQuorumVotesBPS, newMaxQuorumVotesBPS, newQuorumCoefficient);
    }

    /// @dev Bounds-checked checkpoint write. Internal so initialize() can seed before `admin` is
    ///      effectively the caller (avoids the onlyAdmin gate during construction).
    function _setDynamicQuorumParams(
        uint16 newMinQuorumVotesBPS,
        uint16 newMaxQuorumVotesBPS,
        uint32 newQuorumCoefficient
    ) internal {
        if (
            newMinQuorumVotesBPS < MIN_QUORUM_VOTES_BPS_LOWER_BOUND ||
            newMinQuorumVotesBPS > MIN_QUORUM_VOTES_BPS_UPPER_BOUND
        ) revert InvalidMinQuorumVotesBPS();
        if (newMaxQuorumVotesBPS > MAX_QUORUM_VOTES_BPS_UPPER_BOUND) revert InvalidMaxQuorumVotesBPS();
        if (newMinQuorumVotesBPS > newMaxQuorumVotesBPS) revert MinQuorumBPSGreaterThanMaxQuorumBPS();

        ShwounsDAOTypes.DynamicQuorumParams memory old = _latestDynamicQuorumParams();
        _writeQuorumParamsCheckpoint(
            ShwounsDAOTypes.DynamicQuorumParams({
                minQuorumVotesBPS: newMinQuorumVotesBPS,
                maxQuorumVotesBPS: newMaxQuorumVotesBPS,
                quorumCoefficient: newQuorumCoefficient
            })
        );
        emit MinQuorumVotesBPSSet(old.minQuorumVotesBPS, newMinQuorumVotesBPS);
        emit MaxQuorumVotesBPSSet(old.maxQuorumVotesBPS, newMaxQuorumVotesBPS);
        emit QuorumCoefficientSet(old.quorumCoefficient, newQuorumCoefficient);
    }

    function _latestDynamicQuorumParams()
        internal
        view
        returns (ShwounsDAOTypes.DynamicQuorumParams memory)
    {
        uint256 len = ds.quorumParamsCheckpoints.length;
        if (len == 0) return ShwounsDAOTypes.DynamicQuorumParams(0, 0, 0);
        return ds.quorumParamsCheckpoints[len - 1].params;
    }

    // -- Individual dynamic-quorum setters (V4 parity; each writes a new checkpoint via the
    //    bounds-checked combined setter, leaving the other two params unchanged) --

    function setMinQuorumVotesBPS(uint16 newMinQuorumVotesBPS) external {
        ShwounsDAOTypes.DynamicQuorumParams memory p = _latestDynamicQuorumParams();
        setDynamicQuorumParams(newMinQuorumVotesBPS, p.maxQuorumVotesBPS, p.quorumCoefficient);
    }

    function setMaxQuorumVotesBPS(uint16 newMaxQuorumVotesBPS) external {
        ShwounsDAOTypes.DynamicQuorumParams memory p = _latestDynamicQuorumParams();
        setDynamicQuorumParams(p.minQuorumVotesBPS, newMaxQuorumVotesBPS, p.quorumCoefficient);
    }

    function setQuorumCoefficient(uint32 newQuorumCoefficient) external {
        ShwounsDAOTypes.DynamicQuorumParams memory p = _latestDynamicQuorumParams();
        setDynamicQuorumParams(p.minQuorumVotesBPS, p.maxQuorumVotesBPS, newQuorumCoefficient);
    }

    /// @notice Current minimum quorum in absolute votes (minQuorumVotesBPS of total supply).
    function minQuorumVotes() external view returns (uint256) {
        return (ds.shwouns.totalSupply() * _latestDynamicQuorumParams().minQuorumVotesBPS) / 10000;
    }

    /// @notice Current maximum quorum in absolute votes (maxQuorumVotesBPS of total supply).
    function maxQuorumVotes() external view returns (uint256) {
        return (ds.shwouns.totalSupply() * _latestDynamicQuorumParams().maxQuorumVotesBPS) / 10000;
    }

    function _writeQuorumParamsCheckpoint(ShwounsDAOTypes.DynamicQuorumParams memory params) internal {
        uint256 len = ds.quorumParamsCheckpoints.length;
        if (len > 0 && ds.quorumParamsCheckpoints[len - 1].fromBlock == block.number) {
            ds.quorumParamsCheckpoints[len - 1].params = params;
        } else {
            ds.quorumParamsCheckpoints.push(
                ShwounsDAOTypes.DynamicQuorumParamsCheckpoint({
                    fromBlock: uint32(block.number),
                    params: params
                })
            );
        }
    }

    /// @notice The quorum (in votes) required for a proposal, accounting for dynamic quorum and
    ///         the fixed-quorum fallback for proposals created before the first checkpoint.
    function quorumVotes(uint256 proposalId) external view returns (uint256) {
        return ds.quorumVotes(proposalId);
    }

    /// @notice Flat, mapping-free view of a proposal (id, votes, lifecycle, signers, state).
    function proposals(uint256 proposalId) external view returns (ShwounsDAOTypes.ProposalCondensed memory) {
        return ds.proposals(proposalId);
    }

    /// @notice The current proposal threshold in absolute votes (proposalThresholdBPS of supply).
    function proposalThreshold() external view returns (uint256) {
        return (ds.shwouns.totalSupply() * ds.proposalThresholdBPS) / 10000;
    }

    function getDynamicQuorumParamsCheckpointCount() external view returns (uint256) {
        return ds.quorumParamsCheckpoints.length;
    }

    function getDynamicQuorumParamsAt(uint256 blockNumber)
        external
        view
        returns (ShwounsDAOTypes.DynamicQuorumParams memory)
    {
        return ds.getDynamicQuorumParamsAt(blockNumber);
    }

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

    /// @notice If a proposal got stuck post-collect (finalize() never succeeded), the DAO
    ///         (via a new proposal) can call this to redistribute the held funds back to
    ///         the snapshotted vaults pro-rata. Refunds are sent to current Noun owners,
    ///         not to vaults — recovered ETH+ERC20s go to the owners directly.
    /// @dev Only callable by admin (typically DAOLogic itself via another proposal's
    ///      finalize). The stuck-proposal must be in Collected state.
    function refundStuckProposal(uint256 proposalId, address[] calldata assetsToRefund)
        external
        onlyAdmin
    {
        ds.refundStuckProposal(proposalId, assetsToRefund);
    }

    /// @notice Recover stray residual assets from a TERMINAL proposal's escrow to the immutable
    ///         GovernanceRewards sink (A8). Permissionless — settled — but strictly terminal-gated
    ///         in the library (only after Executed; never mid-execution). ETH ignores asset/tokenId/
    ///         amount; ERC-20 uses `asset`; ERC-721 uses `asset`+`tokenId`; ERC-1155 uses
    ///         `asset`+`tokenId`(id)+`amount`.
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
