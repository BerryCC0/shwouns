// SPDX-License-Identifier: GPL-3.0

/// @title Shwouns DAO Proposals library
///
/// @notice Forked from NounsDAOProposals.sol. The propose/vote/state/cancel lifecycle
///         mostly mirrors V4. The novel parts are queue → recordSnapshot → collect →
///         finalize, which replace V4's timelock-based execute.
///
/// @dev MVP scope. Deferred from upstream: proposeBySigs, updateProposal, refundable
///      votes, candidates, objection period. Will be added in follow-up turns.

pragma solidity ^0.8.19;

import { ShwounsDAOTypes, ShwounsDAOEvents, IShwounsTokenLike } from "./ShwounsDAOInterfaces.sol";
import { IShwounsVaultRegistry } from "../vault/IShwounsVaultRegistry.sol";
import { ShwounsVault } from "../vault/ShwounsVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library ShwounsDAOProposals {
    /// @dev The 4-byte selector for ERC-20 transfer(address,uint256). Used to detect
    ///      ERC-20 funding requirements in a proposal's calldata.
    bytes4 internal constant ERC20_TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

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
    error NotShwounsHolder();
    error OnlyProposerOrVetoer();
    error OnlyVetoer();
    error NotAuthorized();
    error OnlyAgainstVotesDuringObjection();

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
        if (ds.shwouns.getPriorVotes(msg.sender, block.number - 1) < threshold) {
            revert ProposerVotesBelowThreshold();
        }
    }

    function _enforceOneLiveProposal(ShwounsDAOTypes.Storage storage ds) internal view {
        uint256 latestProposalId = ds.latestProposalIds[msg.sender];
        if (latestProposalId == 0) return;
        ShwounsDAOTypes.ProposalState state_ = state(ds, latestProposalId);
        if (state_ == ShwounsDAOTypes.ProposalState.Active ||
            state_ == ShwounsDAOTypes.ProposalState.Pending) {
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
        p.startBlock = block.number + ds.votingDelay;
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
        if (p.vetoed) return ShwounsDAOTypes.ProposalState.Vetoed;
        if (p.canceled) return ShwounsDAOTypes.ProposalState.Canceled;
        if (p.executed) return ShwounsDAOTypes.ProposalState.Executed;

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        // Advanced lifecycle states: only reachable post-vote-success
        if (ss.finalized) return ShwounsDAOTypes.ProposalState.Executed;

        if (ss.collectProgress > 0 && _isCollectComplete(ds, proposalId)) {
            return ShwounsDAOTypes.ProposalState.Collected;
        }
        if (ss.snapshotProgress > 0 && ss.snapshotProgress >= ss.snapshotTargetCount && ss.snapshotTargetCount > 0) {
            // snapshot phase complete OR snapshotTargetCount was 0 (no active vaults)
            return ShwounsDAOTypes.ProposalState.Snapshotted;
        }
        if (ss.snapshotTargetCount > 0 || ss.assets.length > 0) {
            // queue() was called (set snapshotTargetCount and assets)
            return ss.snapshotTargetCount == 0
                ? ShwounsDAOTypes.ProposalState.Snapshotted
                : ShwounsDAOTypes.ProposalState.Queued;
        }

        // Pre-queue states
        if (block.number <= p.startBlock) return ShwounsDAOTypes.ProposalState.Pending;
        if (block.number <= p.endBlock) return ShwounsDAOTypes.ProposalState.Active;
        if (p.objectionPeriodEndBlock > 0 && block.number <= p.objectionPeriodEndBlock) {
            return ShwounsDAOTypes.ProposalState.ObjectionPeriod;
        }
        if (p.forVotes <= p.againstVotes || p.forVotes < quorumVotes(ds, proposalId)) {
            return ShwounsDAOTypes.ProposalState.Defeated;
        }
        return ShwounsDAOTypes.ProposalState.Succeeded;
    }

    function _isCollectComplete(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId
    ) internal view returns (bool) {
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        return ss.collectProgress >= ss.snapshottedVaults.length && ss.snapshottedVaults.length > 0;
    }

    // =========================================================================
    // Cancel / Veto
    // =========================================================================

    function cancel(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        if (s == ShwounsDAOTypes.ProposalState.Executed) revert InvalidProposalState();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        // Proposer can cancel anytime pre-execution
        if (msg.sender != p.proposer) {
            // Anyone can cancel if proposer fell below threshold
            uint96 proposerVotes = ds.shwouns.getPriorVotes(p.proposer, block.number - 1);
            if (proposerVotes >= p.proposalThreshold) revert ProposerAboveThresholdAndNotVetoer();
        }

        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function veto(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        if (msg.sender != ds.vetoer) revert OnlyVetoer();
        ShwounsDAOTypes.ProposalState s = state(ds, proposalId);
        if (s == ShwounsDAOTypes.ProposalState.Executed) revert InvalidProposalState();
        ds._proposals[proposalId].vetoed = true;
        emit ProposalVetoed(proposalId);
    }

    // =========================================================================
    // Queue — transitions Succeeded → Queued; locks snapshot target + asset list
    // =========================================================================

    function queue(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Succeeded) revert InvalidProposalState();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        // Lock the iteration target for recordSnapshot
        ss.snapshotTargetCount = ds.vaultRegistry.activeVaultsLength();

        // Extract assets + per-asset requested amounts from the proposal's actions
        _extractAssetsAndAmounts(ds, proposalId, p.targets, p.values, p.calldatas);

        emit ProposalQueued(proposalId);
    }

    function _extractAssetsAndAmounts(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
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

        // Detect ERC-20 transfer() calls in calldata
        for (uint256 i = 0; i < targets.length; i++) {
            bytes memory cd = calldatas[i];
            if (cd.length < 36) continue;
            bytes4 sel;
            assembly { sel := mload(add(cd, 32)) }
            if (sel != ERC20_TRANSFER_SELECTOR) continue;

            // Decode (recipient, amount) from calldata starting at byte 4
            uint256 amount;
            assembly { amount := mload(add(cd, 68)) }

            address asset = targets[i];
            if (ss.requestedAmount[asset] == 0) {
                ss.assets.push(asset);
            }
            ss.requestedAmount[asset] += amount;
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
            uint256 shwounId = ds.vaultRegistry.activeVaultAt(i);
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
        uint256[] calldata shwounIds
    ) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Snapshotted) revert InvalidProposalState();

        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        for (uint256 k = 0; k < shwounIds.length; k++) {
            if (ss.vaultCollected[shwounIds[k]]) revert VaultAlreadyCollected();
            _collectFromVault(ds, ss, proposalId, shwounIds[k]);
            ss.vaultCollected[shwounIds[k]] = true;
            ss.collectProgress++;
        }

        if (_isCollectComplete(ds, proposalId)) {
            emit ProposalCollected(proposalId);
        }
    }

    function _collectFromVault(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.SnapshotState storage ss,
        uint256 proposalId,
        uint256 shwounId
    ) internal {
        address vault = ds.vaultRegistry.vaultOf(shwounId);
        uint256 assetCount = ss.assets.length;
        for (uint256 j = 0; j < assetCount; j++) {
            _collectAsset(ss, proposalId, shwounId, vault, ss.assets[j]);
        }
    }

    function _collectAsset(
        ShwounsDAOTypes.SnapshotState storage ss,
        uint256 proposalId,
        uint256 shwounId,
        address vault,
        address asset
    ) internal {
        uint256 snapshotBalance = ss.vaultSnapshot[shwounId][asset];
        if (snapshotBalance == 0) return;

        uint256 share = (ss.requestedAmount[asset] * snapshotBalance) / ss.totalSnapshotBalance[asset];
        uint256 currentBalance = asset == address(0)
            ? vault.balance
            : IERC20(asset).balanceOf(vault);
        uint256 actual = share < currentBalance ? share : currentBalance;

        if (actual < share) {
            emit ShortfallRecorded(proposalId, shwounId, asset, share - actual);
        }
        if (actual > 0) {
            ShwounsVault(payable(vault)).pullProRata(proposalId, asset, address(this), actual);
            emit AssetCollectedFromVault(proposalId, shwounId, asset, actual);
        }
    }

    // =========================================================================
    // finalize — makes the actual target.call(s) with accumulated funds
    // =========================================================================

    function finalize(ShwounsDAOTypes.Storage storage ds, uint256 proposalId) external {
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];

        for (uint256 i = 0; i < p.targets.length; i++) {
            (bool success, bytes memory result) = p.targets[i].call{value: p.values[i]}(p.calldatas[i]);
            if (!success) {
                // Bubble up the revert. Funds stay in DAOLogic. Caller can retry.
                if (result.length > 0) {
                    assembly { revert(add(result, 32), mload(result)) }
                }
                revert("ShwounsDAO::finalize: target call failed");
            }
        }

        ss.finalized = true;
        p.executed = true;
        emit ProposalExecuted(proposalId);
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
    bytes32 internal constant DOMAIN_NAME_HASH = keccak256("ShwounsDAO");

    event SignatureCancelled(address indexed signer, bytes sig);
    event ProposalCreatedWithSigners(uint256 indexed id, address[] signers);

    error SigExpired();
    error SigCancelled();
    error SigInvalid();
    error SignersBelowThreshold();
    error DuplicateSigner();

    /// @notice Create a proposal co-signed by multiple Shwoun holders. Their combined voting
    ///         power must meet the proposal threshold. The first signer becomes the canonical
    ///         proposer; the rest are recorded in proposal.signers.
    function proposeBySigs(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId) {
        _validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);

        address[] memory signers = _checkSignersAndThreshold(
            ds, proposerSignatures, targets, values, signatures, calldatas, description
        );

        _enforceOneLiveProposalFor(ds, signers[0]);

        ds.proposalCount++;
        proposalId = ds.proposalCount;
        _writeProposalForSigners(ds, proposalId, signers[0], signers, targets, values, signatures, calldatas);
        ds.latestProposalIds[signers[0]] = proposalId;

        _emitSignedProposalEvents(ds, proposalId, signers, targets, values, signatures, calldatas, description);
    }

    function _checkSignersAndThreshold(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal view returns (address[] memory signers) {
        bytes32 digest = ECDSA.toTypedDataHash(
            _domainSeparator(ds),
            _hashProposal(targets, values, signatures, calldatas, description)
        );
        uint256 totalVotes;
        (signers, totalVotes) = _validateSignersAndSum(ds, proposerSignatures, digest);
        if (totalVotes < bps2Uint(ds.proposalThresholdBPS, ds.shwouns.totalSupply())) {
            revert SignersBelowThreshold();
        }
    }

    function _enforceOneLiveProposalFor(ShwounsDAOTypes.Storage storage ds, address proposer) internal view {
        if (ds.latestProposalIds[proposer] == 0) return;
        ShwounsDAOTypes.ProposalState s = state(ds, ds.latestProposalIds[proposer]);
        if (s == ShwounsDAOTypes.ProposalState.Active || s == ShwounsDAOTypes.ProposalState.Pending) {
            revert ProposerAlreadyHasLiveProposal();
        }
    }

    function _emitSignedProposalEvents(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] memory signers,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal {
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        emit ProposalCreated(
            proposalId, signers[0], targets, values, signatures, calldatas,
            p.startBlock, p.endBlock, description
        );
        emit ProposalCreatedWithSigners(proposalId, signers);
    }

    /// @notice Allow a signer to invalidate a specific signature. After cancellation,
    ///         proposeBySigs will reject that sig.
    function cancelSig(ShwounsDAOTypes.Storage storage ds, bytes calldata sig) external {
        ds.cancelledSigs[msg.sender][keccak256(sig)] = true;
        emit SignatureCancelled(msg.sender, sig);
    }

    function _validateSignersAndSum(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.ProposerSignature[] memory ps,
        bytes32 digest
    ) internal view returns (address[] memory signers, uint256 totalVotes) {
        uint256 n = ps.length;
        if (n == 0) revert SignersBelowThreshold();
        signers = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            if (block.timestamp > ps[i].expirationTimestamp) revert SigExpired();
            if (ds.cancelledSigs[ps[i].signer][keccak256(ps[i].sig)]) revert SigCancelled();
            address recovered = ECDSA.recover(digest, ps[i].sig);
            if (recovered != ps[i].signer) revert SigInvalid();

            // Detect duplicates (O(n²) but n is small)
            for (uint256 j = 0; j < i; j++) {
                if (signers[j] == ps[i].signer) revert DuplicateSigner();
            }
            signers[i] = ps[i].signer;
            totalVotes += ds.shwouns.getPriorVotes(ps[i].signer, block.number - 1);
        }
    }

    function _writeProposalForSigners(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address proposer,
        address[] memory signers,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas
    ) internal {
        uint256 totalSupply = ds.shwouns.totalSupply();
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        p.id = proposalId;
        p.proposer = proposer;
        p.proposalThreshold = bps2Uint(ds.proposalThresholdBPS, totalSupply);
        p.quorumVotes = bps2Uint(ds.quorumVotesBPS, totalSupply);
        p.targets = targets;
        p.values = values;
        p.signatures = signatures;
        p.calldatas = calldatas;
        p.startBlock = block.number + ds.votingDelay;
        p.endBlock = p.startBlock + ds.votingPeriod;
        p.totalSupply = totalSupply;
        p.creationBlock = block.number;
        p.signers = signers;
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

    function _hashProposal(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            PROPOSAL_TYPEHASH,
            address(0), // proposer field (unused — sig signed over actions, not proposer)
            keccak256(abi.encodePacked(targets)),
            keccak256(abi.encodePacked(values)),
            _hashStringArray(signatures),
            _hashBytesArray(calldatas),
            keccak256(bytes(description)),
            uint256(0) // expiry baked into ProposerSignature, not the hash itself
        ));
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

    /// @notice Compute the EIP-712 digest a signer would sign over a given proposal.
    ///         Helper exposed for off-chain UIs to construct the signing payload.
    function proposalDigest(
        ShwounsDAOTypes.Storage storage ds,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external view returns (bytes32) {
        bytes32 proposalHash = _hashProposal(targets, values, signatures, calldatas, description);
        return ECDSA.toTypedDataHash(_domainSeparator(ds), proposalHash);
    }

    // =========================================================================
    // Refund a stuck proposal — last-resort recovery if finalize() never succeeds
    // =========================================================================

    event StuckProposalRefunded(uint256 indexed proposalId, address indexed asset, uint256 totalRefunded);

    /// @notice Distribute the funds DAOLogic holds (from collect() on the stuck proposal)
    ///         back to the snapshotted vaults' current owners, pro-rata to their snapshot share.
    /// @dev Only callable from facade via admin path. Marks the proposal as finalized to
    ///      prevent double-spend. Iterates snapshottedVaults; for large sets this may need
    ///      a paged variant — v1 is single-call.
    function refundStuckProposal(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        address[] calldata assetsToRefund
    ) external {
        ShwounsDAOTypes.SnapshotState storage ss = ds._snapshotState[proposalId];
        if (state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Collected) revert InvalidProposalState();

        uint256 vaultCount = ss.snapshottedVaults.length;
        for (uint256 a = 0; a < assetsToRefund.length; a++) {
            address asset = assetsToRefund[a];
            uint256 total = ss.totalSnapshotBalance[asset];
            if (total == 0) continue;
            uint256 distributed = 0;
            for (uint256 i = 0; i < vaultCount; i++) {
                uint256 shwounId = ss.snapshottedVaults[i];
                uint256 snap = ss.vaultSnapshot[shwounId][asset];
                if (snap == 0) continue;
                uint256 share = (ss.requestedAmount[asset] * snap) / total;
                // Transfer to the current owner of the Noun (not the vault)
                address owner = ds.shwouns.ownerOf(shwounId);
                if (asset == address(0)) {
                    (bool ok, ) = owner.call{value: share}("");
                    require(ok, "refund ETH failed");
                } else {
                    IERC20(asset).transfer(owner, share);
                }
                distributed += share;
            }
            emit StuckProposalRefunded(proposalId, asset, distributed);
        }

        ss.finalized = true; // mark as terminal — cannot finalize() again
        ds._proposals[proposalId].executed = true; // surface as Executed in state()
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
        if (ds.quorumParamsCheckpoints.length == 0) {
            // Fallback to fixed quorum recorded at proposal creation.
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
