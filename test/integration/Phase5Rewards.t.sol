// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ProposalEscrow} from "../../src/governance/ProposalEscrow.sol";

import {GovernanceRewards} from "../../src/rewards/GovernanceRewards.sol";
import {GovernanceIncentivesNFT} from "../../src/rewards/GovernanceIncentivesNFT.sol";
import {ApprovalRegistry} from "../../src/rewards/ApprovalRegistry.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Phase5RewardsTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    ShwounsDAOLogic dao;
    GovernanceRewards rewards;
    GovernanceIncentivesNFT giNFT;
    ApprovalRegistry approvalRegistry;

    address foundersDAO = makeAddr("foundersDAO");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");

    uint256 aliceNoun;
    uint256 bobNoun;
    uint256 carolNoun;
    uint256 daveNoun;

    ShwounsVault aliceVault;
    ShwounsVault bobVault;
    ShwounsVault carolVault;
    ShwounsVault daveVault;

    uint256 aliceGI;
    uint256 bobGI;
    uint256 carolGI;
    uint256 daveGI;

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        // Phase 1+2 stack
        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder);
        registry = new ShwounsVaultRegistry(address(token));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        // Phase 3 — GovernanceRewards (Phase 5 extended version)
        rewards = new GovernanceRewards();

        // Phase 5 — GI NFT + ApprovalRegistry
        giNFT = new GovernanceIncentivesNFT(0.01 ether);
        approvalRegistry = new ApprovalRegistry(IERC721(address(giNFT)));

        // GI NFT mint proceeds go to GovernanceRewards
        giNFT.transferOwnership(address(rewards));

        // Phase 4 DAO
        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: 7200,
            votingDelay: 1,
            proposalThresholdBPS: 1,
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400
        });
        ShwounsDAOTypes.DynamicQuorumParams memory dq = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: 200, maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this),
            address(0),
            IShwounsTokenLike(address(token)),
            registry,
            params,
            dq
        );
        ERC1967Proxy daoProxy = new ERC1967Proxy(address(daoImpl), initData);
        dao = ShwounsDAOLogic(payable(address(daoProxy)));
        registry.setDAOLogic(address(dao));

        // Wire Phase 5: GR ↔ DAO, GR.approvalRegistry, DAO.governanceRewards
        rewards.setDAOLogic(address(dao));
        rewards.setApprovalRegistry(approvalRegistry);
        dao.setGovernanceRewards(address(rewards));

        // Per-proposal escrow implementation (clone source); residual sink = GovernanceRewards.
        ProposalEscrow escrowImpl = new ProposalEscrow(address(dao), address(rewards));
        dao.setProposalEscrowImplementation(address(escrowImpl));

        // ApprovalRegistry: ownership transfers to the DAO so governance controls approvals.
        // For the test we keep ownership in this contract so we can call .approve() directly.
        // In production: approvalRegistry.transferOwnership(address(dao));

        // Mint Shwouns + distribute. token.mint() pattern: first call mints founder 0 + auction 1.
        aliceNoun = _mintTo(alice);
        bobNoun = _mintTo(bob);
        carolNoun = _mintTo(carol);
        daveNoun = _mintTo(dave);

        registry.createVaultFor(aliceNoun);
        registry.createVaultFor(bobNoun);
        registry.createVaultFor(carolNoun);
        registry.createVaultFor(daveNoun);
        aliceVault = ShwounsVault(payable(registry.vaultOf(aliceNoun)));
        bobVault = ShwounsVault(payable(registry.vaultOf(bobNoun)));
        carolVault = ShwounsVault(payable(registry.vaultOf(carolNoun)));
        daveVault = ShwounsVault(payable(registry.vaultOf(daveNoun)));

        vm.prank(alice); token.delegate(alice);
        vm.prank(bob); token.delegate(bob);
        vm.prank(carol); token.delegate(carol);
        vm.prank(dave); token.delegate(dave);

        // Fund vaults so proposals can collect from them
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        vm.deal(dave, 10 ether);
        vm.prank(alice); aliceVault.deposit{value: 2 ether}();
        vm.prank(bob); bobVault.deposit{value: 2 ether}();
        vm.prank(carol); carolVault.deposit{value: 2 ether}();
        vm.prank(dave); daveVault.deposit{value: 2 ether}();

        // Fund GR directly so it has reserves for proposal rewards + gas refunds
        vm.deal(address(this), 10 ether);
        (bool ok, ) = address(rewards).call{value: 5 ether}("");
        require(ok);

        // Voters mint GI NFTs
        aliceGI = _mintGI(alice);
        bobGI = _mintGI(bob);
        carolGI = _mintGI(carol);
        // dave does NOT mint a GI NFT — used to verify ineligibility

        // DAO approves alice's and bob's GI tokenIds (carol's NOT approved to verify allowlist)
        approvalRegistry.approve(aliceGI);
        approvalRegistry.approve(bobGI);

        vm.roll(block.number + 1);
    }

    function _mintTo(address recipient) internal returns (uint256) {
        uint256 nounId = token.mint();
        token.transferFrom(address(this), recipient, nounId);
        return nounId;
    }

    function _mintGI(address recipient) internal returns (uint256) {
        vm.deal(recipient, recipient.balance + 0.01 ether);
        vm.prank(recipient);
        return giNFT.mint{value: 0.01 ether}();
    }

    function _runProposalToCollected(uint256 ethAmount, address recipient)
        internal
        returns (uint256 proposalId)
    {
        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        string[] memory s = new string[](1);
        bytes[] memory c = new bytes[](1);
        t[0] = recipient;
        v[0] = ethAmount;

        vm.prank(alice);
        proposalId = dao.propose(t, v, s, c, "phase5 test");

        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(proposalId, 1);
        vm.prank(bob); dao.castVote(proposalId, 1);
        vm.prank(carol); dao.castVote(proposalId, 1);
        vm.prank(dave); dao.castVote(proposalId, 0);
        vm.roll(block.number + 7201);

        dao.queue(proposalId);
        dao.recordSnapshot(proposalId, 10);

        uint256[] memory vaultIds = new uint256[](4);
        vaultIds[0] = aliceNoun;
        vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun;
        vaultIds[3] = daveNoun;
        dao.collect(proposalId, vaultIds.length);
    }

    // =========================================================================
    // GI NFT mint flow
    // =========================================================================

    function test_giMint_forwardsProceedsToRewards() public {
        uint256 grBalanceBefore = address(rewards).balance;
        address newMinter = makeAddr("newMinter");
        vm.deal(newMinter, 1 ether);
        vm.prank(newMinter);
        uint256 tokenId = giNFT.mint{value: 0.01 ether}();

        assertEq(giNFT.ownerOf(tokenId), newMinter);
        assertEq(address(rewards).balance - grBalanceBefore, 0.01 ether);
    }

    function test_giMint_belowPrice_reverts() public {
        address newMinter = makeAddr("newMinter");
        vm.deal(newMinter, 1 ether);
        vm.prank(newMinter);
        vm.expectRevert(GovernanceIncentivesNFT.InsufficientPayment.selector);
        giNFT.mint{value: 0.005 ether}();
    }

    // =========================================================================
    // Proposal reward pool allocation
    // =========================================================================

    function test_finalize_allocatesProposalRewardPool() public {
        uint256 pid = _runProposalToCollected(4 ether, makeAddr("recip"));
        uint256 poolBefore = rewards.proposalRewardPool(pid);
        assertEq(poolBefore, 0);

        dao.finalize(pid);

        // GR's default proposalRewardAmount is 0.1 ether; pool should be set to that
        assertEq(rewards.proposalRewardPool(pid), 0.1 ether);
    }

    // =========================================================================
    // Voter claim — happy path + edge cases
    // =========================================================================

    function test_eligibleVoter_canClaim_proRataShare() public {
        uint256 pid = _runProposalToCollected(4 ether, makeAddr("recip"));
        dao.finalize(pid);

        // forVotes: alice + bob + carol = 3. againstVotes: dave = 1. totalEligible = 4.
        // alice has 1 vote → 0.1 ether * 1 / 4 = 0.025 ether
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        rewards.claimVotingReward(pid, aliceGI);
        assertEq(alice.balance - aliceBalanceBefore, 0.025 ether);
    }

    function test_voter_withoutGINFT_cannotClaim() public {
        uint256 pid = _runProposalToCollected(4 ether, makeAddr("recip"));
        dao.finalize(pid);

        // dave voted Against but has no GI NFT
        vm.prank(dave);
        vm.expectRevert(GovernanceRewards.NotEligible.selector);
        rewards.claimVotingReward(pid, 0);
    }

    function test_voter_withUnapprovedGINFT_cannotClaim() public {
        uint256 pid = _runProposalToCollected(4 ether, makeAddr("recip"));
        dao.finalize(pid);

        // Carol has a GI NFT (carolGI) but it's NOT in ApprovalRegistry
        vm.prank(carol);
        vm.expectRevert(GovernanceRewards.NotEligible.selector);
        rewards.claimVotingReward(pid, carolGI);
    }

    function test_voter_doubleClaim_reverts() public {
        uint256 pid = _runProposalToCollected(4 ether, makeAddr("recip"));
        dao.finalize(pid);

        vm.prank(alice);
        rewards.claimVotingReward(pid, aliceGI);

        vm.prank(alice);
        vm.expectRevert(GovernanceRewards.AlreadyClaimed.selector);
        rewards.claimVotingReward(pid, aliceGI);
    }

    function test_voter_didNotVote_cannotClaim() public {
        // Create a NEW voter who doesn't participate in the vote
        address ed = makeAddr("ed");
        uint256 edGI;
        {
            vm.deal(ed, 1 ether);
            vm.prank(ed);
            edGI = giNFT.mint{value: 0.01 ether}();
            approvalRegistry.approve(edGI);
        }

        uint256 pid = _runProposalToCollected(4 ether, makeAddr("recip"));
        dao.finalize(pid);

        vm.prank(ed);
        vm.expectRevert(GovernanceRewards.DidNotVote.selector);
        rewards.claimVotingReward(pid, edGI);
    }

    function test_voter_abstain_cannotClaim() public {
        // Have alice abstain instead of vote For
        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        string[] memory s = new string[](1);
        bytes[] memory c = new bytes[](1);
        t[0] = makeAddr("recip");
        v[0] = 2 ether;

        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "abstain test");
        vm.roll(block.number + 2);

        vm.prank(alice); dao.castVote(pid, 2); // abstain
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);

        dao.queue(pid);
        dao.recordSnapshot(pid, 10);
        uint256[] memory vaultIds = new uint256[](4);
        vaultIds[0] = aliceNoun; vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun; vaultIds[3] = daveNoun;
        dao.collect(pid, vaultIds.length);
        dao.finalize(pid);

        vm.prank(alice);
        vm.expectRevert(GovernanceRewards.AbstainNotEligible.selector);
        rewards.claimVotingReward(pid, aliceGI);

        // Bob (For) still can claim
        vm.prank(bob);
        rewards.claimVotingReward(pid, bobGI);
    }

    // =========================================================================
    // Refundable votes
    // =========================================================================

    function test_castRefundableVote_refundsGas() public {
        // Configure a non-zero refund cap
        rewards.setMaxRefundPerVote(0.001 ether);

        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        string[] memory s = new string[](1);
        bytes[] memory c = new bytes[](1);
        t[0] = makeAddr("recip");
        v[0] = 1 ether;
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "refund test");
        vm.roll(block.number + 2);

        // Need a non-zero tx.gasprice for the refund to compute > 0
        vm.txGasPrice(1 gwei);

        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        dao.castRefundableVote(pid, 1);

        // Alice should have received SOME refund (up to the cap)
        uint256 refunded = alice.balance - aliceBalanceBefore;
        assertGt(refunded, 0, "received some refund");
        assertLe(refunded, 0.001 ether, "refund respects cap");
    }

    function test_castRefundableVote_capRespected() public {
        rewards.setMaxRefundPerVote(0.0001 ether); // very small cap

        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        string[] memory s = new string[](1);
        bytes[] memory c = new bytes[](1);
        t[0] = makeAddr("recip");
        v[0] = 1 ether;
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "cap test");
        vm.roll(block.number + 2);
        vm.txGasPrice(1000 gwei); // very expensive gas

        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        dao.castRefundableVote(pid, 1);

        uint256 refunded = alice.balance - aliceBalanceBefore;
        assertLe(refunded, 0.0001 ether, "refund capped");
    }

    // =========================================================================
    // ApprovalRegistry
    // =========================================================================

    function test_approve_thenRevoke() public {
        uint256 newGI = _mintGI(makeAddr("randomMinter"));
        assertFalse(approvalRegistry.approvedTokenIds(newGI));
        approvalRegistry.approve(newGI);
        assertTrue(approvalRegistry.approvedTokenIds(newGI));
        approvalRegistry.revoke(newGI);
        assertFalse(approvalRegistry.approvedTokenIds(newGI));
    }

    function test_approve_byNonOwner_reverts() public {
        uint256 newGI = _mintGI(makeAddr("randomMinter"));
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        approvalRegistry.approve(newGI);
    }

    function test_isEligible_checksOwnership() public {
        // alice's tokenId is approved. If alice transfers to bob, bob becomes eligible.
        assertTrue(approvalRegistry.isEligible(alice, aliceGI));
        assertFalse(approvalRegistry.isEligible(bob, aliceGI));

        vm.prank(alice);
        giNFT.transferFrom(alice, makeAddr("newOwner"), aliceGI);

        assertFalse(approvalRegistry.isEligible(alice, aliceGI));
        assertTrue(approvalRegistry.isEligible(makeAddr("newOwner"), aliceGI));
    }
}
