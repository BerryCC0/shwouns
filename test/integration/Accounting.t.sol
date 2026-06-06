// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest} from "./LifecycleInvariants.t.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockFeeERC20} from "../mocks/MockFeeERC20.sol";

/// @title Accounting hygiene (§A accounting) — fundable allowlist (M-04), balance-delta (M-04),
///        top-up cap (L-02).
contract AccountingTest is LifecycleInvariantsTest {
    function _proposeERC20(address proposer, address token, address to, uint256 amount)
        internal
        returns (uint256 pid)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cds = new bytes[](1);
        targets[0] = token;
        cds[0] = abi.encodeWithSignature("transfer(address,uint256)", to, amount);
        vm.prank(proposer);
        pid = dao.propose(targets, values, sigs, cds, "erc20");
    }

    // ---- M-04 fundable-asset allowlist ----

    function test_nonAllowlistedERC20_rejectedAtQueue() public {
        MockERC20 t = new MockERC20();
        t.mint(address(aliceVault), 100 ether);
        // NOT allowlisted.
        uint256 pid = _proposeERC20(alice, address(t), recipientA, 50 ether);
        _passToSucceeded(pid);
        vm.expectRevert(ShwounsDAOProposals.AssetNotFundable.selector);
        dao.queue(pid);
    }

    function test_allowlistedERC20_queuesAndCollects() public {
        MockERC20 t = new MockERC20();
        t.mint(address(aliceVault), 100 ether);
        dao.setFundableAsset(address(t), true);
        assertTrue(dao.isFundableAsset(address(t)));
        assertTrue(dao.isFundableAsset(address(0)), "ETH always fundable");

        uint256 pid = _proposeERC20(alice, address(t), recipientA, 50 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 100);
        dao.collect(pid, 100);
        assertEq(t.balanceOf(dao.escrowAddressOf(pid)), 50 ether, "exact-transfer token fully collected");
        dao.finalize(pid);
        assertEq(t.balanceOf(recipientA), 50 ether, "executed");
    }

    // ---- M-04 balance-delta accounting (fee-on-transfer under-collects) ----

    function test_feeOnTransferToken_underCollects_blocksFinalize() public {
        MockFeeERC20 fee = new MockFeeERC20(1000); // 10% fee on transfer
        fee.mint(address(aliceVault), 100 ether);
        fee.mint(address(bobVault), 100 ether);
        fee.mint(address(carolVault), 100 ether);
        dao.setFundableAsset(address(fee), true);

        uint256 pid = _proposeERC20(alice, address(fee), recipientA, 60 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 100);
        dao.collect(pid, 100);

        // Each vault→escrow transfer loses 10% to the fee, so the escrow holds < 60 and the ledger
        // (credited by ACTUAL delta, not the requested amount) is short — finalize is blocked.
        uint256 escrowBal = fee.balanceOf(dao.escrowAddressOf(pid));
        assertLt(escrowBal, 60 ether, "fee token under-delivers");
        vm.expectRevert(ShwounsDAOProposals.InsufficientCollected.selector);
        dao.finalize(pid);
    }

    // ---- L-02 top-up cap ----

    function test_excessTopUp_rejected_exactTopUpWorks() public {
        // A shortfall ETH proposal: alice drains after snapshot so collection is short.
        uint256 pid = _proposeETH(alice, recipientA, 6 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 100);
        vm.prank(alice);
        aliceVault.withdraw(alice, 3 ether); // alice's 1.8 share now uncollectable
        dao.collect(pid, 100);

        uint256 collected = _escrowBal(pid);
        uint256 outstanding = 6 ether - collected;
        assertGt(outstanding, 0, "there is a shortfall");

        // Excess top-up (more than outstanding) is rejected — no stranded over-funding (L-02).
        vm.deal(address(this), 10 ether);
        vm.expectRevert(ShwounsDAOProposals.InvalidTopUp.selector);
        dao.topUp{value: outstanding + 1}(pid, address(0), outstanding + 1);

        // Exact top-up of the shortfall works and lets the proposal finalize.
        dao.topUp{value: outstanding}(pid, address(0), outstanding);
        dao.finalize(pid);
        assertEq(recipientA.balance, 6 ether, "executed after exact top-up");
    }
}
