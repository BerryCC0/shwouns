// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest} from "../integration/LifecycleInvariants.t.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {GovernanceRewards} from "../../src/rewards/GovernanceRewards.sol";
import {GovernanceIncentivesNFT} from "../../src/rewards/GovernanceIncentivesNFT.sol";
import {ApprovalRegistry} from "../../src/rewards/ApprovalRegistry.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {IERC6551Registry} from "../../src/vault/erc6551/interfaces/IERC6551Registry.sol";
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

    /// C-01 (FIXED — regression). A recipient re-entering finalize hits the global execution lock;
    /// the nested call reverts, fails the action, and rolls the whole attempt back atomically. No
    /// double-spend, and the victim's funds — in a SEPARATE escrow — are untouched, so the victim
    /// still finalizes with its full 2 ETH.
    function test_audit_finalizeReentrancySpendsAnotherProposalsETH() public {
        uint256 victimProposal = _proposeETH(alice, recipientA, 2 ether);
        _passToSucceeded(victimProposal);
        _queueSnapshotCollect(victimProposal, 100);

        ReentrantProposalTarget attacker = new ReentrantProposalTarget(dao);
        uint256 attackProposal = _proposeETH(bob, address(attacker), 1 ether);
        _passToSucceeded(attackProposal);
        _queueSnapshotCollect(attackProposal, 100);
        attacker.setProposalId(attackProposal);

        // Per-proposal custody: victim escrow holds 2, attack escrow holds 1, facade holds nothing.
        assertEq(_escrowBal(victimProposal), 2 ether, "victim escrow funded");
        assertEq(_escrowBal(attackProposal), 1 ether, "attack escrow funded");
        assertEq(address(dao).balance, 0, "facade custodies nothing");

        // The attacker's receive() re-enters finalize(attackProposal); the nested call reverts on
        // the global execution lock, which fails the action and reverts the whole finalize.
        vm.expectRevert();
        dao.finalize(attackProposal);

        // Nothing stolen, nothing leaked: both escrows intact, the execution lock is cleared.
        assertEq(_escrowBal(attackProposal), 1 ether, "attack escrow intact after revert");
        assertEq(_escrowBal(victimProposal), 2 ether, "victim escrow untouched");
        assertFalse(dao.executing(), "execution lock cleared after atomic rollback");
        assertEq(dao.activeProposalId(), 0, "no active proposal lingering");

        // The victim finalizes normally with its full 2 ETH — never drained by the attacker.
        dao.finalize(victimProposal);
        assertEq(recipientA.balance, 2 ether, "victim paid in full");
        assertEq(_escrowBal(victimProposal), 0, "victim escrow drained by its own finalize");
    }

    function test_audit_cancelAfterPartialCollectPermanentlyStrandsFunds() public {
        uint256 proposalId = _proposeETH(alice, recipientA, 6 ether);
        _passToSucceeded(proposalId);
        dao.queue(proposalId);
        dao.recordSnapshot(proposalId, 100);
        // Collect only the first snapshotted vault (alice's) — a partial collection.
        dao.collect(proposalId, 1);
        uint256 collected = _escrowBal(proposalId);
        assertGt(collected, 0, "partial collection sits in the escrow");

        // H-01 (FIXED — regression). Cancel is allowed even after funds moved; the funded Canceled
        // proposal routes into the permissionless contribution refund — nothing is stranded.
        vm.prank(alice);
        dao.cancel(proposalId);
        assertEq(uint256(dao.state(proposalId)), uint256(ShwounsDAOTypes.ProposalState.Canceled));

        uint256 aliceBefore = alice.balance;
        vm.prank(makeAddr("anyone")); // permissionless: anyone can trigger recovery for contributors
        dao.refund(proposalId, 100);

        assertEq(_escrowBal(proposalId), 0, "fully recovered - nothing stranded");
        // Only the collected vault (alice's) contributed; alice (its owner) is made whole.
        assertEq(alice.balance - aliceBefore, collected, "contributor refunded actual contribution");
    }

    function test_audit_approvalActionDrainsAnotherProposalsERC20() public {
        MockERC20 asset = new MockERC20();
        asset.mint(address(aliceVault), 100 ether);
        dao.setFundableAsset(address(asset), true); // M-04 allowlist so the victim can queue

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

        // The victim's ERC-20 is isolated in its own escrow, never the shared facade.
        address victimEscrow = dao.escrowAddressOf(victimProposal);
        assertEq(asset.balanceOf(victimEscrow), 100 ether, "victim ERC-20 isolated in its escrow");
        assertEq(asset.balanceOf(address(dao)), 0, "facade custodies no ERC-20");

        address attacker = makeAddr("allowanceAttacker");
        uint256 attackProposal = _proposeCall(
            bob, address(asset), abi.encodeWithSignature("approve(address,uint256)", attacker, type(uint256).max)
        );
        _passToSucceeded(attackProposal);
        dao.queue(attackProposal);
        dao.finalize(attackProposal);
        address attackEscrow = dao.escrowAddressOf(attackProposal);

        // C-02 (FIXED — regression). The malicious approve was made BY the attack escrow over its
        // OWN (empty) balance. It confers no allowance over the victim escrow or the facade.
        assertEq(asset.allowance(attackEscrow, attacker), type(uint256).max, "approve isolated to attack escrow");
        assertEq(asset.allowance(victimEscrow, attacker), 0, "no allowance over victim escrow");
        assertEq(asset.allowance(address(dao), attacker), 0, "no allowance over facade");

        // transferFrom against the empty attack escrow reverts (insufficient balance). Nothing
        // drained from the victim escrow or the facade.
        vm.prank(attacker);
        vm.expectRevert();
        asset.transferFrom(attackEscrow, attacker, 100 ether);
        assertEq(asset.balanceOf(attacker), 0, "attacker drained nothing");
        assertEq(asset.balanceOf(victimEscrow), 100 ether, "victim escrow intact");

        // The victim finalizes normally and pays recipientA in full.
        dao.finalize(victimProposal);
        assertEq(asset.balanceOf(recipientA), 100 ether, "victim executed in full");
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

        // M-02 (FIXED — regression). The active set is append-only: markPossiblyInactive no longer
        // evicts on a zero ETH balance, so an ERC-20-funded vault stays active and snapshottable.
        assertEq(asset.balanceOf(address(aliceVault)), 100 ether);
        assertTrue(_containsActiveVault(aliceNoun), "ERC-20-funded vault stays active (append-only)");
    }

    /// C-03 (FIXED — regression). (a) The registry refuses to deploy a vault for an unminted token.
    /// (b) Even force-deploying the vault directly via the canonical ERC-6551 registry and funding
    /// it does NOT pollute the active set: markActive reverts (token doesn't exist) and the vault
    /// swallows that revert (_notifyActive is try/catch), so the deposit succeeds but the tokenId
    /// never enters the active set.
    function test_audit_nonexistentTokenVaultCanPolluteActiveSet() public {
        uint256 nonexistentTokenId = 1_000_000_000;
        assertEq(token.totalSupply(), 4, "token ID is not minted");

        // (a) existence gate
        vm.expectRevert(ShwounsVaultRegistry.TokenDoesNotExist.selector);
        registry.createVaultFor(nonexistentTokenId);

        // (b) force-deploy the vault directly, bypassing createVaultFor
        address forced = IERC6551Registry(CANONICAL_REGISTRY).createAccount(
            address(vaultImpl), bytes32(0), block.chainid, address(token), nonexistentTokenId
        );
        assertEq(forced, registry.vaultOf(nonexistentTokenId), "deterministic address");

        vm.deal(address(this), 1 wei);
        (bool ok,) = forced.call{value: 1 wei}("");
        assertTrue(ok, "deposit succeeds (notify revert swallowed)");
        assertEq(forced.balance, 1 wei, "vault funded");
        assertFalse(_containsActiveVault(nonexistentTokenId), "nonexistent-token vault excluded from active set");
    }

    function _containsActiveVault(uint256 tokenId) internal view returns (bool) {
        uint256 length = registry.activeVaultsLength();
        for (uint256 i = 0; i < length; i++) {
            if (registry.activeVaultAt(i) == tokenId) return true;
        }
        return false;
    }

    function test_audit_oneApprovedGINFTCanAuthorizeMultipleVoterClaims() public {
        GovernanceRewards rewards = new GovernanceRewards(address(0));
        GovernanceIncentivesNFT giNFT = new GovernanceIncentivesNFT(0, address(0));
        ApprovalRegistry approvals = new ApprovalRegistry(IERC721(address(giNFT)), address(0));
        // A6: proceeds route via proceedsRecipient (mintPrice=0 here, so no proceeds anyway);
        // eligibility uses ownerOf(tokenId), not the GI NFT contract owner.
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
        GovernanceRewards rewards = new GovernanceRewards(address(0));
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
