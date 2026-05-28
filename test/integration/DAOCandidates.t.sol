// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ShwounsDAOData} from "../../src/governance/data/ShwounsDAOData.sol";

contract DAOCandidatesTest is Test {
    // Mirror the contract's events so we can use vm.expectEmit.
    struct Candidate {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        string description;
    }
    event ProposalCandidateCreated(
        address indexed proposer,
        bytes32 indexed slugHash,
        string slug,
        Candidate candidate,
        string reason
    );
    struct CandidateUpdate {
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        string description;
        string updateMessage;
    }
    event ProposalCandidateUpdated(
        address indexed proposer,
        bytes32 indexed slugHash,
        CandidateUpdate update
    );
    event ProposalCandidateCanceled(address indexed proposer, bytes32 indexed slugHash);
    event FeedbackSent(
        address indexed sender,
        address indexed candidateProposer,
        bytes32 indexed candidateSlugHash,
        uint8 support,
        string reason
    );
    event ProposalFeedbackSent(
        address indexed sender,
        uint256 indexed proposalId,
        uint8 support,
        string reason
    );

    ShwounsDAOData daoData;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        daoData = new ShwounsDAOData();
    }

    function _simpleAction()
        internal
        view
        returns (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c)
    {
        t = new address[](1);
        v = new uint256[](1);
        s = new string[](1);
        c = new bytes[](1);
        t[0] = address(this);
        v[0] = 1 ether;
    }

    function _candidate(string memory description)
        internal
        view
        returns (ShwounsDAOData.Candidate memory)
    {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _simpleAction();
        return ShwounsDAOData.Candidate({
            targets: t, values: v, signatures: s, calldatas: c, description: description
        });
    }

    function test_createCandidate_marksSlugActive_andEmits() public {
        ShwounsDAOData.Candidate memory cand = _candidate("fund the thing");

        vm.prank(alice);
        daoData.createProposalCandidate(cand, "my-proposal", "looking for feedback");

        assertTrue(daoData.candidateActive(alice, keccak256(bytes("my-proposal"))));
    }

    function test_createCandidate_duplicateSlug_reverts() public {
        ShwounsDAOData.Candidate memory cand = _candidate("d");
        vm.prank(alice);
        daoData.createProposalCandidate(cand, "same-slug", "");

        vm.prank(alice);
        vm.expectRevert(ShwounsDAOData.CandidateAlreadyExists.selector);
        daoData.createProposalCandidate(cand, "same-slug", "");
    }

    function test_differentProposers_canShareSlug() public {
        ShwounsDAOData.Candidate memory cand = _candidate("d");
        vm.prank(alice);
        daoData.createProposalCandidate(cand, "same-slug", "");
        vm.prank(bob);
        daoData.createProposalCandidate(cand, "same-slug", "");

        assertTrue(daoData.candidateActive(alice, keccak256(bytes("same-slug"))));
        assertTrue(daoData.candidateActive(bob, keccak256(bytes("same-slug"))));
    }

    function test_updateCandidate_byCreator() public {
        ShwounsDAOData.Candidate memory cand = _candidate("v1");
        vm.prank(alice);
        daoData.createProposalCandidate(cand, "p", "");

        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _simpleAction();
        ShwounsDAOData.CandidateUpdate memory u = ShwounsDAOData.CandidateUpdate({
            targets: t, values: v, signatures: s, calldatas: c,
            description: "v2", updateMessage: "improved"
        });

        vm.prank(alice);
        daoData.updateProposalCandidate("p", u);
    }

    function test_updateCandidate_notFound_reverts() public {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _simpleAction();
        ShwounsDAOData.CandidateUpdate memory u = ShwounsDAOData.CandidateUpdate({
            targets: t, values: v, signatures: s, calldatas: c,
            description: "v2", updateMessage: ""
        });
        vm.prank(alice);
        vm.expectRevert(ShwounsDAOData.CandidateNotFound.selector);
        daoData.updateProposalCandidate("doesnt-exist", u);
    }

    function test_cancelCandidate_freesSlug() public {
        ShwounsDAOData.Candidate memory cand = _candidate("v1");
        vm.prank(alice);
        daoData.createProposalCandidate(cand, "p", "");

        vm.expectEmit(true, true, false, false);
        emit ProposalCandidateCanceled(alice, keccak256(bytes("p")));

        vm.prank(alice);
        daoData.cancelProposalCandidate("p");

        assertFalse(daoData.candidateActive(alice, keccak256(bytes("p"))));

        // Slug can now be reused
        ShwounsDAOData.Candidate memory cand2 = _candidate("v2");
        vm.prank(alice);
        daoData.createProposalCandidate(cand2, "p", "");
        assertTrue(daoData.candidateActive(alice, keccak256(bytes("p"))));
    }

    function test_sendCandidateFeedback_emitsEvent() public {
        ShwounsDAOData.Candidate memory cand = _candidate("d");
        vm.prank(alice);
        daoData.createProposalCandidate(cand, "candidate", "");

        vm.expectEmit(true, true, true, true);
        emit FeedbackSent(bob, alice, keccak256(bytes("candidate")), 1, "ship it");

        vm.prank(bob);
        daoData.sendCandidateFeedback(alice, "candidate", 1, "ship it");
    }

    function test_sendCandidateFeedback_unknownCandidate_reverts() public {
        vm.prank(bob);
        vm.expectRevert(ShwounsDAOData.CandidateNotFound.selector);
        daoData.sendCandidateFeedback(alice, "ghost", 1, "?");
    }

    function test_sendCandidateFeedback_invalidSupport_reverts() public {
        ShwounsDAOData.Candidate memory cand = _candidate("d");
        vm.prank(alice);
        daoData.createProposalCandidate(cand, "candidate", "");

        vm.prank(bob);
        vm.expectRevert(ShwounsDAOData.InvalidSupportValue.selector);
        daoData.sendCandidateFeedback(alice, "candidate", 3, "");
    }

    function test_sendProposalFeedback_emits() public {
        vm.expectEmit(true, true, false, true);
        emit ProposalFeedbackSent(bob, 42, 0, "nope");
        vm.prank(bob);
        daoData.sendProposalFeedback(42, 0, "nope");
    }
}
