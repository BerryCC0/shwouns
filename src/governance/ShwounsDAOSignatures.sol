// SPDX-License-Identifier: GPL-3.0

/// @title Shwouns DAO signed-proposals + proposal-editing library
///
/// @notice Split out of ShwounsDAOProposals to keep that library under EIP-170 (audit F1). Holds the
///         EIP-712 multi-Noun co-signing family (proposeBySigs / updateProposalBySigs / proposalDigest
///         / cancelSig) and the proposer-only proposal-editing family (updateProposal*). These are all
///         COLD paths, so routing their shared helpers through cross-library delegatecalls to
///         ShwounsDAOProposals is acceptable; the HOT propose/vote/state paths stay entirely in
///         ShwounsDAOProposals as same-library JUMPs.
///
/// @dev Delegatecalled by the facade on the same `ds` storage (via `using ... for Storage`). It in
///      turn delegatecalls a handful of now-`public` ShwounsDAOProposals helpers (state,
///      _writeProposal, _validateActionsAndThreshold_skip, bps2Uint, _domainSeparator) — all run in
///      the facade's context, so `address(this)` and storage are the proxy's throughout. The EIP-712
///      encoding mirrors NounsDAOProposals byte-for-byte; the digest is unchanged by the split.

pragma solidity ^0.8.19;

import { ShwounsDAOTypes } from "./ShwounsDAOInterfaces.sol";
import { ShwounsDAOProposals } from "./ShwounsDAOProposals.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

library ShwounsDAOSignatures {
    /// @dev EIP-712 typehashes for signed proposals + edits. DOMAIN_TYPEHASH/DOMAIN_NAME_HASH and
    ///      BALLOT_TYPEHASH stay in ShwounsDAOProposals (the domain separator is shared).
    bytes32 internal constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
    );
    bytes32 internal constant UPDATE_PROPOSAL_TYPEHASH = keccak256(
        "UpdateProposal(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
    );

    // Re-declared so the library can emit them; topics match ShwounsDAOEvents / ShwounsDAOProposals.
    /// @notice Emitted when a proposal is created (mirrors ShwounsDAOProposals for proposeBySigs).
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
    /// @notice Emitted when a signer cancels one of their proposal signatures.
    event SignatureCancelled(address indexed signer, bytes sig);
    /// @notice Emitted after proposeBySigs, listing the proposal's co-signers.
    event ProposalCreatedWithSigners(uint256 indexed id, address[] signers);
    /// @notice Emitted when a proposal's actions and description are edited (Updatable window).
    event ProposalUpdated(
        uint256 indexed id, address indexed proposer, address[] targets, uint256[] values,
        string[] signatures, bytes[] calldatas, string description, string updateMessage
    );
    /// @notice Emitted when only a proposal's transactions are edited.
    event ProposalTransactionsUpdated(
        uint256 indexed id, address indexed proposer, address[] targets, uint256[] values,
        string[] signatures, bytes[] calldatas, string updateMessage
    );
    /// @notice Emitted when only a proposal's description is edited.
    event ProposalDescriptionUpdated(
        uint256 indexed id, address indexed proposer, string description, string updateMessage
    );

    /// @notice Thrown when a proposal signature has expired.
    error SigExpired();
    /// @notice Thrown when a proposal signature was cancelled by its signer.
    error SigCancelled();
    /// @notice Thrown when a proposal signature fails ERC-1271/ECDSA verification.
    error SigInvalid();
    /// @notice Thrown when the combined signer + proposer voting power does not exceed the threshold.
    error SignersBelowThreshold();
    /// @notice Thrown when editing a proposal that is not in the Updatable window.
    error CanOnlyEditUpdatableProposals();
    /// @notice Thrown when an editor is not the proposal's proposer (or the signer set mismatches).
    error OnlyProposerCanEdit();
    /// @notice Thrown when the non-sig edit path is used on a proposal that has co-signers.
    error ProposerCannotUpdateProposalWithSigners();
    /// @notice Thrown when the re-signing set size differs from the original signer set.
    error SignerCountMismatch();
    /// @notice Thrown when a signer or proposer already has a live proposal in flight.
    error ProposerAlreadyHasLiveProposal();

    /// @dev Bundles a proposal's action arrays into one memory pointer. updateProposalBySigs takes
    ///      this instead of four separate array params to keep its stack shallow under via_ir; the
    ///      facade builds it from the individual arrays, so the external ABI is unchanged.
    struct ProposalTxs {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
    }

    // =========================================================================
    // Signed proposals (proposeBySigs) — EIP-712 multi-Noun co-signing
    // =========================================================================

    /// @notice Create a proposal co-signed by multiple Shwoun holders. `msg.sender` is the
    ///         proposer and contributes its own votes; the signers' combined voting power plus the
    ///         proposer's must STRICTLY exceed the proposal threshold. Each signature binds the
    ///         proposer, the proposal actions, and that signer's own expiry, and is verified via
    ///         ERC-1271 (so smart-contract wallets can co-sign). Mirrors NounsDAOProposals.
    /// @param proposerSignatures The co-signers' EIP-712 signatures, each with signer + expiry.
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action (GovernorBravo form).
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @return proposalId The id of the created proposal.
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

        // Create the proposal BEFORE verifying signatures. This makes signer de-duplication free:
        // a repeated signer's latestProposalIds already points at this just-created (Pending)
        // proposal, so _enforceOneLiveProposalFor reverts. proposer = msg.sender. createForSigners
        // runs as a cross-library DELEGATECALL (own frame) — the 9-arg ProposalCreated emit won't
        // inline into proposeBySigs under via_ir, but compiles cleanly there (mirrors propose()).
        proposalId = ShwounsDAOProposals.createForSigners(ds, targets, values, signatures, calldatas, description);

        // Verify sigs, enforce the combined-power threshold, and return the trimmed signer set.
        address[] memory signers = _verifySignersAndCountVotes(
            ds, proposerSignatures, targets, values, signatures, calldatas, description, proposalId
        );
        ds._proposals[proposalId].signers = signers;
        emit ProposalCreatedWithSigners(proposalId, signers);
    }

    /// @dev Verify each signer's signature, enforce one-live-proposal per signer (which also
    ///      de-duplicates signers against the just-created proposal), count the votes of signers
    ///      with voting power, then add the proposer (msg.sender) the same way. Enforces the
    ///      combined-power threshold (folded in here so proposeBySigs carries no `votes` local —
    ///      via_ir stack depth) and returns the trimmed signer set.
    function _verifySignersAndCountVotes(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        uint256 proposalId
    ) internal returns (address[] memory signers) {
        bytes memory encodeData =
            _calcProposalEncodeData(msg.sender, targets, values, signatures, calldatas, description);

        signers = new address[](proposerSignatures.length);
        uint256 numSigners = 0;
        uint256 votes = 0;
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

        // Strictly greater than the threshold (Nouns parity), same as the normal propose() path.
        if (numSigners == 0) revert SignersBelowThreshold();
        if (votes <= ShwounsDAOProposals.bps2Uint(ds.proposalThresholdBPS, ds.shwouns.totalSupply())) {
            revert SignersBelowThreshold();
        }
    }

    /// @dev Per-signer one-live-proposal guard (the proposeBySigs analog of _enforceOneLiveProposal):
    ///      reverts if `proposer` already has a proposal in flight. Because the proposal is created
    ///      BEFORE signatures are verified, this also de-duplicates a repeated signer for free.
    function _enforceOneLiveProposalFor(ShwounsDAOTypes.Storage storage ds, address proposer) internal view {
        if (ds.latestProposalIds[proposer] == 0) return;
        ShwounsDAOTypes.ProposalState s = ShwounsDAOProposals.state(ds, ds.latestProposalIds[proposer]);
        if (s == ShwounsDAOTypes.ProposalState.Active ||
            s == ShwounsDAOTypes.ProposalState.Pending ||
            s == ShwounsDAOTypes.ProposalState.ObjectionPeriod ||
            s == ShwounsDAOTypes.ProposalState.Updatable) {
            revert ProposerAlreadyHasLiveProposal();
        }
    }

    /// @notice Allow a signer to invalidate a specific signature. After cancellation,
    ///         proposeBySigs will reject that sig.
    /// @param sig The exact signature bytes to invalidate (keyed by its keccak hash).
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
        if (ShwounsDAOProposals.state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Updatable)
            revert CanOnlyEditUpdatableProposals();
        if (msg.sender != proposal.proposer) revert OnlyProposerCanEdit();
        if (proposal.signers.length > 0) revert ProposerCannotUpdateProposalWithSigners();
    }

    /// @notice Edit a proposal's actions AND description during its Updatable window. Proposer only,
    ///         and only for proposals with no co-signers (those use updateProposalBySigs).
    /// @param proposalId The proposal to edit.
    /// @param targets The new action target addresses.
    /// @param values The new ETH value for each action.
    /// @param signatures The new function signature strings for each action.
    /// @param calldatas The new calldata (or args) for each action.
    /// @param description The new proposal description.
    /// @param updateMessage A human-readable note describing the edit.
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

    /// @notice Edit only a proposal's transactions during its Updatable window. Proposer only.
    /// @param proposalId The proposal to edit.
    /// @param targets The new action target addresses.
    /// @param values The new ETH value for each action.
    /// @param signatures The new function signature strings for each action.
    /// @param calldatas The new calldata (or args) for each action.
    /// @param updateMessage A human-readable note describing the edit.
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
        ShwounsDAOProposals._validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);
        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        _checkProposalUpdatable(ds, proposalId, p);
        p.targets = targets;
        p.values = values;
        p.signatures = signatures;
        p.calldatas = calldatas;
    }

    /// @notice Edit only a proposal's description during its Updatable window. Proposer only.
    /// @param proposalId The proposal to edit.
    /// @param description The new proposal description.
    /// @param updateMessage A human-readable note describing the edit.
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
    /// @dev `txs` bundles the four action arrays into one memory pointer (the facade builds it) so
    ///      this function stays under via_ir's stack limit. Behaviour + EIP-712 digest are identical
    ///      to passing the arrays individually.
    /// @param proposalId The co-signed proposal to edit.
    /// @param proposerSignatures Re-signatures from every original signer (same set, same order).
    /// @param txs The new action arrays (targets/values/signatures/calldatas) bundled.
    /// @param description The new proposal description.
    /// @param updateMessage A human-readable note describing the edit.
    function updateProposalBySigs(
        ShwounsDAOTypes.Storage storage ds,
        uint256 proposalId,
        ShwounsDAOTypes.ProposerSignature[] memory proposerSignatures,
        ProposalTxs memory txs,
        string memory description,
        string memory updateMessage
    ) external {
        ShwounsDAOProposals._validateActionsAndThreshold_skip(ds, txs.targets, txs.values, txs.signatures, txs.calldatas);
        if (proposerSignatures.length == 0) revert SignersBelowThreshold();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        if (ShwounsDAOProposals.state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Updatable)
            revert CanOnlyEditUpdatableProposals();
        if (msg.sender != p.proposer) revert OnlyProposerCanEdit();

        address[] memory signers = p.signers;
        if (proposerSignatures.length != signers.length) revert SignerCountMismatch();

        bytes memory encodeData = abi.encodePacked(
            proposalId,
            _calcProposalEncodeData(msg.sender, txs.targets, txs.values, txs.signatures, txs.calldatas, description)
        );
        for (uint256 i = 0; i < proposerSignatures.length; i++) {
            _verifyProposalSignature(ds, UPDATE_PROPOSAL_TYPEHASH, encodeData, proposerSignatures[i]);
            // Assume the same signer set in the same order (avoids an O(n^2) membership search).
            if (signers[i] != proposerSignatures[i].signer) revert OnlyProposerCanEdit();
        }

        p.targets = txs.targets;
        p.values = txs.values;
        p.signatures = txs.signatures;
        p.calldatas = txs.calldatas;
        emit ProposalUpdated(
            proposalId, msg.sender, txs.targets, txs.values, txs.signatures, txs.calldatas, description, updateMessage
        );
    }

    // =========================================================================
    // EIP-712 encoding helpers
    // =========================================================================

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
        return ECDSA.toTypedDataHash(ShwounsDAOProposals._domainSeparator(ds), structHash);
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
    ///         to build the signing payload. Takes the `proposer` (the address that will submit
    ///         proposeBySigs) and the signer's `expirationTimestamp`, both bound into the digest.
    /// @param proposer The address that will submit proposeBySigs (bound into the digest).
    /// @param targets The action target addresses.
    /// @param values The ETH value for each action.
    /// @param signatures The function signature strings for each action.
    /// @param calldatas The calldata (or args) for each action.
    /// @param description The proposal description.
    /// @param expirationTimestamp The signer's signature expiry (bound into the digest).
    /// @return The EIP-712 typed-data digest to sign.
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
}
