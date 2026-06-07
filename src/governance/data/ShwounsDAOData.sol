// SPDX-License-Identifier: GPL-3.0

/// @title ShwounsDAOData — pre-proposal candidates + on-chain feedback
///
/// @notice Forked-down version of NounsDAOData. Stripped to event-only mode:
///   - Candidate bodies (targets/values/sigs/calldatas/description) live in event logs,
///     not contract storage. Off-chain indexers reconstruct candidates from event history.
///   - On-chain state is just a uniqueness map: (proposer, slug-hash) → exists, used to
///     reject duplicate slugs and to gate updateProposalCandidate / cancelProposalCandidate
///     to the original creator.
///
/// Why event-only:
///   - V4's NounsDAOData stores full proposal data in storage for canonical on-chain reads.
///     That adds ~600 LOC, dominates the audit surface, and adds significant deployment cost.
///   - We need pre-proposal coordination but don't need on-chain canonical data — indexers
///     (Ponder) can rebuild candidates from events with full fidelity.
///   - Signatures collected off-chain anyway (passed to proposeBySigs at promotion time).

pragma solidity ^0.8.19;

contract ShwounsDAOData {
    /// @notice (creator, slugHash) → true once they've created a candidate with that slug
    ///         and not cancelled it. Used for duplicate-slug protection and update auth.
    mapping(address => mapping(bytes32 => bool)) public candidateActive;

    struct Candidate {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        string description;
    }

    /// @notice Emitted when a pre-proposal candidate is created. The full body lives in the log.
    event ProposalCandidateCreated(
        address indexed proposer,
        bytes32 indexed slugHash,
        string slug,
        Candidate candidate,
        string reason
    );

    /// @dev Bundling event payload into a struct to reduce stack pressure on the emit site.
    struct CandidateUpdate {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        string description;
        string updateMessage;
    }

    /// @notice Emitted when a candidate is updated by its creator. The new body lives in the log.
    event ProposalCandidateUpdated(
        address indexed proposer,
        bytes32 indexed slugHash,
        CandidateUpdate update
    );

    /// @notice Emitted when a candidate is canceled by its creator, freeing the slug for re-use.
    event ProposalCandidateCanceled(address indexed proposer, bytes32 indexed slugHash);

    /// @notice Emitted when a Shwoun holder posts on-chain support/feedback for a candidate.
    ///         Off-chain UIs can also accept signed feedback messages, but on-chain feedback
    ///         is the auditable canonical form.
    event FeedbackSent(
        address indexed sender,
        address indexed candidateProposer,
        bytes32 indexed candidateSlugHash,
        uint8 support,
        string reason
    );

    /// @notice Same as FeedbackSent but for already-created formal proposals.
    event ProposalFeedbackSent(
        address indexed sender,
        uint256 indexed proposalId,
        uint8 support,
        string reason
    );

    /// @notice Thrown when a (creator, slug) pair already has an active candidate.
    error CandidateAlreadyExists();
    /// @notice Thrown when updating/canceling/feedback-ing a (creator, slug) with no active candidate.
    error CandidateNotFound();
    /// @notice Thrown when a feedback `support` value is greater than 2.
    error InvalidSupportValue();
    /// @notice Thrown when a candidate's targets/values/signatures/calldatas arrays differ in length.
    error ActionsArrayLengthMismatch();
    /// @notice Thrown when a candidate has zero actions or more than 10.
    error InvalidProposalActions();

    /// @notice Create a pre-proposal candidate. Anyone can create; the candidate body is
    ///         emitted in the event log for off-chain indexing.
    /// @param c The candidate body (targets/values/signatures/calldatas/description).
    /// @param slug A human-readable identifier scoped to msg.sender. The (sender, slug)
    ///        pair must be unique among active candidates from that sender.
    /// @param reason Optional message accompanying the creation.
    /// @dev Args bundled into a struct to avoid stack-too-deep.
    function createProposalCandidate(
        Candidate calldata c,
        string calldata slug,
        string calldata reason
    ) external {
        _validateActions(c.targets, c.values, c.signatures, c.calldatas);
        bytes32 slugHash = keccak256(bytes(slug));
        if (candidateActive[msg.sender][slugHash]) revert CandidateAlreadyExists();
        candidateActive[msg.sender][slugHash] = true;
        emit ProposalCandidateCreated(msg.sender, slugHash, slug, c, reason);
    }

    /// @notice Update an existing candidate. Only callable by the original creator.
    /// @param slug The slug identifying the candidate to update.
    /// @param u The new candidate body plus an update message.
    /// @dev Args bundled into a struct to avoid stack pressure.
    function updateProposalCandidate(string calldata slug, CandidateUpdate calldata u) external {
        _validateActions(u.targets, u.values, u.signatures, u.calldatas);
        if (!candidateActive[msg.sender][keccak256(bytes(slug))]) revert CandidateNotFound();
        emit ProposalCandidateUpdated(msg.sender, keccak256(bytes(slug)), u);
    }

    /// @notice Cancel a candidate. Only callable by the original creator. Frees the slug
    ///         for re-use.
    /// @param slug The slug identifying the candidate to cancel.
    function cancelProposalCandidate(string calldata slug) external {
        bytes32 slugHash = keccak256(bytes(slug));
        if (!candidateActive[msg.sender][slugHash]) revert CandidateNotFound();
        candidateActive[msg.sender][slugHash] = false;
        emit ProposalCandidateCanceled(msg.sender, slugHash);
    }

    /// @notice Send on-chain feedback for a candidate. Anyone can call.
    /// @param candidateProposer The creator of the candidate being commented on.
    /// @param slug The slug identifying the candidate.
    /// @param support 0=against, 1=for, 2=abstain (matches the DAO's voting enum)
    /// @param reason Free-text feedback emitted in the log.
    function sendCandidateFeedback(
        address candidateProposer,
        string calldata slug,
        uint8 support,
        string calldata reason
    ) external {
        if (support > 2) revert InvalidSupportValue();
        bytes32 slugHash = keccak256(bytes(slug));
        if (!candidateActive[candidateProposer][slugHash]) revert CandidateNotFound();
        emit FeedbackSent(msg.sender, candidateProposer, slugHash, support, reason);
    }

    /// @notice Send on-chain feedback for an already-created formal proposal. Anyone can call;
    ///         intended for non-voters to register opinion or for voters to attach reasoning
    ///         outside the votes themselves.
    /// @param proposalId The id of the formal proposal being commented on.
    /// @param support 0=against, 1=for, 2=abstain (matches the DAO's voting enum).
    /// @param reason Free-text feedback emitted in the log.
    function sendProposalFeedback(uint256 proposalId, uint8 support, string calldata reason) external {
        if (support > 2) revert InvalidSupportValue();
        emit ProposalFeedbackSent(msg.sender, proposalId, support, reason);
    }

    function _validateActions(
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas
    ) internal pure {
        if (targets.length != values.length ||
            targets.length != signatures.length ||
            targets.length != calldatas.length) revert ActionsArrayLengthMismatch();
        if (targets.length == 0 || targets.length > 10) revert InvalidProposalActions();
    }
}
