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
    error ProposerAlreadyHasLiveProposal();

    // =========================================================================
    // Signed proposals (proposeBySigs) — EIP-712 multi-Noun co-signing
    // =========================================================================

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
        ShwounsDAOProposals._validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);

        // Create the proposal BEFORE verifying signatures. This makes signer de-duplication free:
        // a repeated signer's latestProposalIds already points at this just-created (Pending)
        // proposal, so _enforceOneLiveProposalFor reverts. proposer = msg.sender (set by _writeProposal).
        ds.proposalCount++;
        proposalId = ds.proposalCount;
        ShwounsDAOProposals._writeProposal(ds, proposalId, targets, values, signatures, calldatas);

        (uint256 votes, address[] memory signers) = _verifySignersAndCountVotes(
            ds, proposerSignatures, targets, values, signatures, calldatas, description, proposalId
        );
        if (signers.length == 0) revert SignersBelowThreshold();
        // Strictly greater than the threshold (Nouns parity), same as the normal propose() path.
        if (votes <= ShwounsDAOProposals.bps2Uint(ds.proposalThresholdBPS, ds.shwouns.totalSupply())) {
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
        ShwounsDAOProposals._validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);
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
        ShwounsDAOProposals._validateActionsAndThreshold_skip(ds, targets, values, signatures, calldatas);
        if (proposerSignatures.length == 0) revert SignersBelowThreshold();

        ShwounsDAOTypes.Proposal storage p = ds._proposals[proposalId];
        if (ShwounsDAOProposals.state(ds, proposalId) != ShwounsDAOTypes.ProposalState.Updatable)
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
