// SPDX-License-Identifier: BSD-3-Clause

/// @title Shwouns DAO Governance interfaces, types, and events
///
/// @notice Forked from NounsDAOInterfaces.sol. Changes:
///   - Strip fork-related types (INounsDAOForkEscrow, IForkDAODeployer, fork events)
///   - Strip INounsDAOExecutor / timelock types (snapshot+collect+finalize replaces timelock)
///   - Strip NounsTokenLike (use IShwounsToken directly)
///   - Add SnapshotState struct for snapshot/collect bookkeeping per proposal
///   - Add Snapshotted + Collected to ProposalState enum
///   - Add ShwounsDAOParams and Storage adjustments matching our model
///
/// Original Copyright Compound Labs (BSD-3-Clause), modified by Nounders DAO, modified for Shwouns.

pragma solidity ^0.8.19;

import { IShwounsToken } from "../interfaces/IShwounsToken.sol";
import { IShwounsVaultRegistry } from "../vault/IShwounsVaultRegistry.sol";

/// @notice Subset of ShwounsToken used by the governance contracts. Avoids forcing
///         the concrete ShwounsToken to override base-class implementations of
///         totalSupply / getPriorVotes / getCurrentVotes (which are inherited from
///         ERC721Enumerable and ERC721Checkpointable).
interface IShwounsTokenLike {
    function totalSupply() external view returns (uint256);
    function getCurrentVotes(address account) external view returns (uint96);
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ShwounsDAOEvents {
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

    /// @notice Emitted per (proposal, vault, asset) during recordSnapshot.
    event VaultSnapshotted(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 balance);

    /// @notice Emitted per (proposal, vault, asset) during collect when amount actually pulled.
    event AssetCollectedFromVault(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 amount);

    /// @notice Emitted when a vault's actual balance at collect time is less than its snapshot share.
    event ShortfallRecorded(uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 missingAmount);

    /// @notice Emitted when finalize() attempts and fails (proposal stays in Collected; can retry).
    event FinalizeAttemptFailed(uint256 indexed proposalId, uint256 actionIndex, bytes returnData);

    // -- Parameter change events --
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdBPSSet(uint256 oldProposalThresholdBPS, uint256 newProposalThresholdBPS);
    event NewAdmin(address oldAdmin, address newAdmin);
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
    event NewVetoer(address oldVetoer, address newVetoer);
    event MinQuorumVotesBPSSet(uint16 oldMinQuorumVotesBPS, uint16 newMinQuorumVotesBPS);
    event MaxQuorumVotesBPSSet(uint16 oldMaxQuorumVotesBPS, uint16 newMaxQuorumVotesBPS);
    event QuorumCoefficientSet(uint32 oldQuorumCoefficient, uint32 newQuorumCoefficient);
}

interface ShwounsDAOTypes {
    // --------------------------------------------------------------------------
    // Storage layout (single struct accessed via library functions)
    // --------------------------------------------------------------------------
    struct Storage {
        /// @notice Administrator address (typically self post-deployment).
        address admin;
        /// @notice Pending administrator pending acceptance.
        address pendingAdmin;
        /// @notice Address with veto authority. Renounceable.
        address vetoer;
        /// @notice Pending vetoer pending acceptance.
        address pendingVetoer;

        /// @notice The delay before voting on a proposal may take place, in blocks.
        uint256 votingDelay;
        /// @notice The duration of voting on a proposal, in blocks.
        uint256 votingPeriod;
        /// @notice The basis points required to propose, as a fraction of token totalSupply.
        uint256 proposalThresholdBPS;
        /// @notice Quorum required in BPS of totalSupply (simple fixed quorum for MVP).
        uint256 quorumVotesBPS;
        /// @notice Last-minute window — in the final N blocks of voting, a For-flip triggers
        ///         an objection period extension.
        uint32 lastMinuteWindowInBlocks;
        /// @notice How long the objection period extends voting by (blocks).
        uint32 objectionPeriodDurationInBlocks;

        /// @notice Counter for proposal IDs.
        uint256 proposalCount;

        /// @notice The Shwouns ERC-721 token (voting power source). Stored as Like
        ///         so totalSupply / getPriorVotes / getCurrentVotes are reachable
        ///         without forcing the concrete token to override base implementations.
        IShwounsTokenLike shwouns;
        /// @notice The Shwouns Vault Registry (active-set + per-vault deployment).
        IShwounsVaultRegistry vaultRegistry;

        /// @notice Proposals by ID.
        mapping(uint256 => Proposal) _proposals;
        /// @notice Latest proposal ID per proposer (used for one-proposal-at-a-time check).
        mapping(address => uint256) latestProposalIds;

        /// @notice Snapshot/collect bookkeeping by proposal ID.
        mapping(uint256 => SnapshotState) _snapshotState;

        /// @notice Dynamic quorum parameter checkpoints.
        DynamicQuorumParamsCheckpoint[] quorumParamsCheckpoints;

        /// @notice Cancelled signatures: signer => keccak(sig) => true. Used by proposeBySigs
        ///         to reject sigs that the signer has explicitly invalidated.
        mapping(address => mapping(bytes32 => bool)) cancelledSigs;
        // -- Appended for proposal editing + queue-deadline (append-only; do not reorder) --
        /// @notice The pre-voting window (in blocks) during which a proposal is editable
        ///         (Updatable state). 0 = no edit window (proposals open directly to Pending).
        uint256 proposalUpdatablePeriodInBlocks;
        /// @notice How long after voting ends (in blocks) a Succeeded proposal may still be
        ///         queued before it becomes Expired. Shwouns policy (Nouns leaves it indefinite).
        uint256 proposalQueuePeriodInBlocks;
        // -- Appended for the security-remediation execution model (append-only; do not reorder) --
        /// @notice Global execution lock. True only while a finalize() is mid-flight (between the
        ///         lock being set and escrow.execute returning). The single "effect" set before the
        ///         external calls (CEI); terminal `executed` is set only AFTER execute returns.
        bool executing;
        /// @notice The proposal currently Executing under the lock (0 = none). Together with
        ///         `executing` this is the entire transient state behind the `Executing` lifecycle
        ///         status and the `isActiveExecutor` authentication predicate.
        uint256 activeProposalId;
        /// @notice The locked ProposalEscrow implementation (EIP-1167 clone source). Set once at
        ///         bootstrap. The deterministic escrow address and EXPECTED_ESCROW_CODEHASH both
        ///         derive from this single locked address.
        address proposalEscrowImplementation;
        /// @notice One-shot lock for `proposalEscrowImplementation`.
        bool proposalEscrowImplementationLocked;
        /// @notice DAO-curated allowlist of fundable ERC-20 assets (M-04). ETH (address(0)) is
        ///         always fundable and is NOT keyed here. Rebasing/fee-on-transfer tokens can't be
        ///         detected by interface, so a proposal that requests a non-allowlisted ERC-20 is
        ///         rejected at queue (paired with exact balance-delta collection + the pre-execution
        ///         solvency recheck as defense-in-depth).
        mapping(address => bool) fundableAsset;
        /// @notice Reserved slots for future upgrades. This Storage struct sits at slot 0 of the
        ///         UUPS proxy, FOLLOWED by inherited OpenZeppelin storage — so new fields must be
        ///         appended HERE (consuming the gap), never after `ds`, or they would shift the
        ///         inherited slots. Decrement the gap size by the number of slots you add.
        ///         Was [50]; -4 for executing(1)+activeProposalId(1)+escrowImpl+lock(1)+fundable(1).
        uint256[46] __gap;
    }

    // --------------------------------------------------------------------------
    // Proposal — slimmed from V4 (no clientId tracking, no fork fields, no timelockV1)
    // --------------------------------------------------------------------------
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 proposalThreshold;
        uint256 quorumVotes;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool vetoed;
        bool executed;
        mapping(address => Receipt) receipts;
        uint256 totalSupply;
        uint256 creationBlock;
        /// @notice Set to a non-zero block number if a last-minute For-flip triggers the
        ///         objection period extension. Voting continues but only Against votes are accepted.
        uint64 objectionPeriodEndBlock;
        /// @notice Co-signers when created via proposeBySigs. Empty for normal propose().
        address[] signers;
        // -- Appended for proposal editing (append-only; do not reorder) --
        /// @notice Last block on which this proposal can be edited. While block.number <= this,
        ///         the proposal is Updatable; voting (startBlock) begins after it.
        uint256 updatePeriodEndBlock;
    }

    /// @notice EIP-712 signature payload for proposeBySigs.
    struct ProposerSignature {
        bytes sig;
        address signer;
        uint256 expirationTimestamp;
    }

    // --------------------------------------------------------------------------
    // Snapshot/Collect state for a proposal (the novel part of our fork)
    // --------------------------------------------------------------------------
    struct SnapshotState {
        /// @notice Number of active vaults at queue() time. Locks the iteration target.
        uint256 snapshotTargetCount;
        /// @notice Number of vaults processed by recordSnapshot() so far. When this hits
        ///         snapshotTargetCount, snapshot phase is complete.
        uint256 snapshotProgress;
        /// @notice Number of vaults processed by collect() so far. When this hits the
        ///         number of vaults with non-zero snapshots, collect phase is complete.
        uint256 collectProgress;
        /// @notice Vaults that had non-zero ETH at snapshot (set during recordSnapshot).
        uint256[] snapshottedVaults;
        /// @notice Assets touched by this proposal (ETH always at index 0; ERC-20s added).
        address[] assets;
        /// @notice Total amount requested per asset (ETH from values[], ERC-20s from calldata).
        mapping(address => uint256) requestedAmount;
        /// @notice Sum of all snapshotted vault balances per asset.
        mapping(address => uint256) totalSnapshotBalance;
        /// @notice Per-vault snapshot per asset: vaultId → asset → balance at snapshot time.
        mapping(uint256 => mapping(address => uint256)) vaultSnapshot;
        /// @notice Marks whether a vault has been processed by collect().
        mapping(uint256 => bool) vaultCollected;
        /// @notice Whether finalize() has succeeded for this proposal.
        bool finalized;
        // -- Appended for the Phase 0.0 lifecycle redesign (append-only; do not reorder) --
        /// @notice Vault-ID set frozen at queue() (C1). recordSnapshot pages over THIS stable
        ///         list, not the live registry active-set, so mid-snapshot deposits/withdrawals
        ///         cannot skip, duplicate, or brick iteration. Guarantee: "vault-set frozen at
        ///         queue; balances sampled during snapshot paging" — NOT a historical balance
        ///         checkpoint (a withdrawal before a vault's page is processed reduces funding).
        uint256[] frozenVaultIds;
        /// @notice Actually-collected amount per asset for THIS proposal (C4). finalize requires
        ///         collected[asset] >= requestedAmount[asset] for every asset; refunds use this
        ///         so a proposal can never spend or refund another proposal's funds.
        mapping(address => uint256) collected;
        /// @notice True once queue() has run. Distinguishes a queued zero-funding proposal
        ///         (snapshotTargetCount == 0) from a never-queued one (C3).
        bool queued;
        // -- Appended for the M-05 paged freeze (append-only; do not reorder) --
        /// @notice Number of active vaults already copied into frozenVaultIds. queue() snapshots
        ///         snapshotTargetCount = activeVaultsLength() and freezes a bounded first batch;
        ///         freezeVaults() pages the remainder. recordSnapshot reverts until
        ///         freezeProgress == snapshotTargetCount. Sound because the active set is
        ///         append-only (M-02): indices [0, snapshotTargetCount) never shift.
        uint256 freezeProgress;
    }

    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint96 votes;
    }

    /// @notice Flat, mapping-free view of a proposal for indexers/UIs. Shwouns-native: no clientId
    ///         or fork fields; adds the editing/objection/snapshot-collect lifecycle data.
    struct ProposalCondensed {
        uint256 id;
        address proposer;
        uint256 proposalThreshold;
        uint256 quorumVotes;
        uint256 startBlock;
        uint256 endBlock;
        uint256 updatePeriodEndBlock;
        uint256 objectionPeriodEndBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool vetoed;
        bool executed;
        uint256 totalSupply;
        uint256 creationBlock;
        address[] signers;
        uint256 snapshotTargetCount;
        uint256 snapshotProgress;
        uint256 collectProgress;
        ProposalState state;
    }

    struct DynamicQuorumParams {
        uint16 minQuorumVotesBPS;
        uint16 maxQuorumVotesBPS;
        uint32 quorumCoefficient;
    }

    struct DynamicQuorumParamsCheckpoint {
        uint32 fromBlock;
        DynamicQuorumParams params;
    }

    struct ShwounsDAOParams {
        uint256 votingPeriod;
        uint256 votingDelay;
        uint256 proposalThresholdBPS;
        uint256 proposalUpdatablePeriodInBlocks;
        uint256 proposalQueuePeriodInBlocks;
    }

    /// @notice All possible proposal lifecycle states.
    enum ProposalState {
        Pending,         // 0  voting hasn't started
        Active,          // 1  voting open
        Canceled,        // 2  canceled by proposer
        Defeated,        // 3  vote failed
        Succeeded,       // 4  vote passed, awaiting queue
        Queued,          // 5  queue() called, snapshot phase in progress (or pending)
        Snapshotted,     // 6  snapshot phase complete; collect phase open
        Collected,       // 7  collect phase complete; finalize pending
        Executed,        // 8  finalize() succeeded; proposal done
        Vetoed,          // 9  vetoed
        Expired,         // 10 succeeded but never queued before queueDeadlineBlock (wired in E)
        ObjectionPeriod, // 11 last-minute For-flip extended voting; only Against votes accepted
        Updatable,       // 12 pre-voting edit window (wired in E); appended — never renumber
        Executing        // 13 finalize() in progress — transient; set before escrow.execute, cleared
                         //    after it returns (terminal Executed is set only then). Appended —
                         //    never renumber. A proposal is Executing iff it is the active proposal
                         //    under the global execution lock (ds.executing && ds.activeProposalId).
    }
}

contract ShwounsDAOStorage is ShwounsDAOTypes {
    Storage ds;
}
