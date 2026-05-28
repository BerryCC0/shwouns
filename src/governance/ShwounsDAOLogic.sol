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

    modifier onlyAdmin() {
        if (msg.sender != ds.admin) revert OnlyAdmin();
        _;
    }

    /// @notice Initialize the DAO. Deployed via UUPS proxy.
    function initialize(
        address admin_,
        address vetoer_,
        IShwounsTokenLike shwouns_,
        IShwounsVaultRegistry vaultRegistry_,
        ShwounsDAOTypes.ShwounsDAOParams calldata params,
        uint256 quorumVotesBPS_
    ) external initializer {
        if (admin_ == address(0) || address(shwouns_) == address(0) || address(vaultRegistry_) == address(0))
            revert InvalidAddress();
        __UUPSUpgradeable_init();

        ds.admin = admin_;
        ds.vetoer = vetoer_;
        ds.shwouns = shwouns_;
        ds.vaultRegistry = vaultRegistry_;
        ds.votingDelay = params.votingDelay;
        ds.votingPeriod = params.votingPeriod;
        ds.proposalThresholdBPS = params.proposalThresholdBPS;
        ds.quorumVotesBPS = quorumVotesBPS_;
    }

    /// @notice UUPS upgrade authorization — admin only.
    function _authorizeUpgrade(address) internal view override onlyAdmin {}

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

    function proposalDigest(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external view returns (bytes32) {
        return ds.proposalDigest(targets, values, signatures, calldatas, description);
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

    function collect(uint256 proposalId, uint256[] calldata shwounIds) external {
        ds.collect(proposalId, shwounIds);
    }

    function finalize(uint256 proposalId) external {
        ds.finalize(proposalId);
        // If GovernanceRewards is wired, allocate this proposal's voter reward pool.
        // Wrapped in try/catch so a misconfigured GR doesn't brick finalize.
        if (address(governanceRewards) != address(0)) {
            try governanceRewards.allocateProposalReward(proposalId) {} catch {}
        }
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
        uint256 oldVotingDelay = ds.votingDelay;
        ds.votingDelay = newVotingDelay;
        emit VotingDelaySet(oldVotingDelay, newVotingDelay);
    }

    function setVotingPeriod(uint256 newVotingPeriod) external onlyAdmin {
        uint256 oldVotingPeriod = ds.votingPeriod;
        ds.votingPeriod = newVotingPeriod;
        emit VotingPeriodSet(oldVotingPeriod, newVotingPeriod);
    }

    function setProposalThresholdBPS(uint256 newProposalThresholdBPS) external onlyAdmin {
        uint256 oldProposalThresholdBPS = ds.proposalThresholdBPS;
        ds.proposalThresholdBPS = newProposalThresholdBPS;
        emit ProposalThresholdBPSSet(oldProposalThresholdBPS, newProposalThresholdBPS);
    }

    /// @notice Set the simple quorum BPS. Used when no dynamic quorum checkpoints exist.
    function setQuorumVotesBPS(uint256 newQuorumVotesBPS) external onlyAdmin {
        ds.quorumVotesBPS = newQuorumVotesBPS;
    }

    function setLastMinuteWindowInBlocks(uint32 newLastMinuteWindowInBlocks) external onlyAdmin {
        ds.lastMinuteWindowInBlocks = newLastMinuteWindowInBlocks;
    }

    /// @notice Set the GovernanceRewards contract. Callable once.
    function setGovernanceRewards(address _gr) external onlyAdmin {
        if (governanceRewardsLocked) revert AlreadyLocked();
        if (_gr == address(0)) revert InvalidAddress();
        governanceRewards = IGovernanceRewardsForDAO(_gr);
        governanceRewardsLocked = true;
        emit GovernanceRewardsSet(_gr);
    }

    function setObjectionPeriodDurationInBlocks(uint32 newObjectionPeriodDurationInBlocks) external onlyAdmin {
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
    ) external onlyAdmin {
        _writeQuorumParamsCheckpoint(
            ShwounsDAOTypes.DynamicQuorumParams({
                minQuorumVotesBPS: newMinQuorumVotesBPS,
                maxQuorumVotesBPS: newMaxQuorumVotesBPS,
                quorumCoefficient: newQuorumCoefficient
            })
        );
        emit MinQuorumVotesBPSSet(0, newMinQuorumVotesBPS);
        emit MaxQuorumVotesBPSSet(0, newMaxQuorumVotesBPS);
        emit QuorumCoefficientSet(0, newQuorumCoefficient);
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

    function getDynamicQuorumParamsCheckpointCount() external view returns (uint256) {
        return ds.quorumParamsCheckpoints.length;
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

    // -------------------------------------------------------------------------
    // Receive ETH (proposals can have value > 0; DAOLogic accumulates funds via collect)
    // -------------------------------------------------------------------------

    receive() external payable {}
}
