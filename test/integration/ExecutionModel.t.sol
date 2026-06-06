// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest} from "./LifecycleInvariants.t.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ProposalEscrow, IProposalEscrow} from "../../src/governance/ProposalEscrow.sol";

/// @dev Records the DAO's transient execution state at the instant it receives ETH — i.e. while the
///      proposal is mid-finalize, called from inside the escrow's execute().
contract ExecutingObserver {
    ShwounsDAOLogic public immutable dao;
    uint256 public observedState;
    bool public observedExecuting;
    uint256 public observedActiveId;
    bool public callerWasActiveExecutor;

    constructor(ShwounsDAOLogic _dao) {
        dao = _dao;
    }

    receive() external payable {
        observedExecuting = dao.executing();
        observedActiveId = dao.activeProposalId();
        observedState = uint256(dao.state(observedActiveId));
        // msg.sender here is the escrow making the value-bearing call.
        callerWasActiveExecutor = dao.isActiveExecutor(msg.sender);
    }
}

/// @dev On receiving ETH, attempts to finalize a DIFFERENT proposal — must hit the global lock.
contract NestedFinalizeOther {
    ShwounsDAOLogic public immutable dao;
    uint256 public otherPid;

    constructor(ShwounsDAOLogic _dao) {
        dao = _dao;
    }

    function setOther(uint256 pid) external {
        otherPid = pid;
    }

    receive() external payable {
        dao.finalize(otherPid);
    }
}

/// @title Execution-model regressions (A3/A4) — the finalize lock seam + executor authentication.
/// @notice Complements the flipped C-01/C-02 audit PoCs with the review §12 items testable from the
///         core alone (governance-action / upgrade / rescue / no-EOA tests arrive with §A's later
///         phases).
contract ExecutionModelTest is LifecycleInvariantsTest {
    function _passCollect(uint256 pid) internal {
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 100);
        dao.collect(pid, 100);
    }

    // ---- executor-authentication predicate (review §5, §12.5, §12.7) ----

    function test_isActiveExecutor_falseOutsideExecution() public {
        uint256 pid = _proposeETH(alice, recipientA, 2 ether);
        _passCollect(pid);
        address escrow = dao.escrowAddressOf(pid);
        // Before/after execution the escrow is NOT an authorized executor.
        assertFalse(dao.isActiveExecutor(escrow), "not executing -> escrow unauthorized");
        assertFalse(dao.isActiveExecutor(address(this)), "arbitrary address never authorized");
        assertFalse(dao.executing(), "no execution in progress");
        assertEq(dao.activeProposalId(), 0, "no active proposal");
    }

    function test_executingStatus_observableOnlyDuringExecution_thenStale() public {
        ExecutingObserver obs = new ExecutingObserver(dao);
        uint256 pid = _proposeETH(alice, address(obs), 2 ether);
        _passCollect(pid);
        address escrow = dao.escrowAddressOf(pid);

        dao.finalize(pid);

        // Captured from inside execution: Executing status, lock set, activeId = pid, escrow auth'd.
        assertEq(obs.observedState(), uint256(ShwounsDAOTypes.ProposalState.Executing), "Executing mid-call");
        assertTrue(obs.observedExecuting(), "lock set mid-call");
        assertEq(obs.observedActiveId(), pid, "activeId = pid mid-call");
        assertTrue(obs.callerWasActiveExecutor(), "escrow authenticated mid-call");

        // After execution returns: terminal Executed, lock cleared, escrow now STALE (unauthorized).
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Executed), "Executed after");
        assertFalse(dao.executing(), "lock cleared after");
        assertEq(dao.activeProposalId(), 0, "activeId cleared after");
        assertFalse(dao.isActiveExecutor(escrow), "stale escrow unauthorized after finalize");
    }

    function test_crossProposalEscrow_neverAuthorized() public {
        // Two proposals; while one executes, the OTHER proposal's escrow must not authenticate.
        ExecutingObserver obs = new ExecutingObserver(dao);
        uint256 pidA = _proposeETH(alice, address(obs), 2 ether);
        uint256 pidB = _proposeETH(bob, recipientB, 2 ether);
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pidA, 1);
        vm.prank(bob); dao.castVote(pidA, 1);
        vm.prank(carol); dao.castVote(pidA, 1);
        vm.prank(alice); dao.castVote(pidB, 1);
        vm.prank(bob); dao.castVote(pidB, 1);
        vm.prank(carol); dao.castVote(pidB, 1);
        vm.roll(block.number + 7201);
        dao.queue(pidA); dao.recordSnapshot(pidA, 100); dao.collect(pidA, 100);
        dao.queue(pidB); dao.recordSnapshot(pidB, 100); dao.collect(pidB, 100);

        address escrowB = dao.escrowAddressOf(pidB);
        // Finalizing A: the observer (paid by A's escrow) checks whether B's escrow is authorized.
        // It must NOT be — only the active proposal's escrow authenticates.
        dao.finalize(pidA);
        assertEq(obs.observedActiveId(), pidA, "A is the active proposal");
        assertFalse(dao.isActiveExecutor(escrowB), "B's escrow never authorized during A's execution");
    }

    // ---- escrow access control (A2) ----

    function test_escrow_execute_onlyDAOLogic() public {
        uint256 pid = _proposeETH(alice, recipientA, 2 ether);
        _passCollect(pid);
        IProposalEscrow escrow = IProposalEscrow(dao.escrowAddressOf(pid));

        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        bytes[] memory c = new bytes[](1);
        t[0] = recipientA; v[0] = 1 ether; c[0] = "";

        // A forged/direct caller (not the DAOLogic proxy) cannot drive the escrow.
        vm.expectRevert(ProposalEscrow.NotDAOLogic.selector);
        escrow.execute(t, v, c);

        vm.expectRevert(ProposalEscrow.NotDAOLogic.selector);
        escrow.payOut(address(0), recipientA, 1 ether);
    }

    // ---- global execution lock: nested finalize of a different proposal (review §7, §12.3) ----

    function test_nestedFinalize_differentProposal_revertsOnGlobalLock() public {
        NestedFinalizeOther attacker = new NestedFinalizeOther(dao);
        uint256 pidB = _proposeETH(alice, recipientB, 2 ether); // nested target
        uint256 pidA = _proposeETH(bob, address(attacker), 1 ether); // re-enters finalize(B)

        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pidB, 1);
        vm.prank(bob); dao.castVote(pidB, 1);
        vm.prank(carol); dao.castVote(pidB, 1);
        vm.prank(alice); dao.castVote(pidA, 1);
        vm.prank(bob); dao.castVote(pidA, 1);
        vm.prank(carol); dao.castVote(pidA, 1);
        vm.roll(block.number + 7201);
        dao.queue(pidB); dao.recordSnapshot(pidB, 100); dao.collect(pidB, 100);
        dao.queue(pidA); dao.recordSnapshot(pidA, 100); dao.collect(pidA, 100);
        attacker.setOther(pidB);

        // A's action re-enters finalize(B); the global lock reverts it, rolling A back atomically.
        vm.expectRevert();
        dao.finalize(pidA);

        assertEq(_escrowBal(pidA), 1 ether, "A's escrow intact");
        assertEq(_escrowBal(pidB), 2 ether, "B's escrow intact");
        assertFalse(dao.executing(), "lock cleared after rollback");
        assertEq(dao.activeProposalId(), 0, "no active proposal after rollback");
    }

    // ---- clone codehash uniformity (A3.4, §12 escrow-codehash) ----

    function test_escrowClones_shareUniformCodehash() public {
        uint256 pidA = _proposeETH(alice, recipientA, 2 ether);
        _passToSucceeded(pidA);
        dao.queue(pidA);
        uint256 pidB = _proposeETH(bob, recipientB, 2 ether);
        _passToSucceeded(pidB);
        dao.queue(pidB);

        address escrowA = dao.escrowAddressOf(pidA);
        address escrowB = dao.escrowAddressOf(pidB);
        assertTrue(escrowA != escrowB, "distinct per-proposal escrow identities");
        assertTrue(escrowA.codehash != bytes32(0), "escrow A deployed at queue");
        assertTrue(escrowB.codehash != bytes32(0), "escrow B deployed at queue");
        assertEq(escrowA.codehash, escrowB.codehash, "all clones share one runtime codehash");
    }

    // ---- escrow-impl setter is one-shot ----

    function test_setProposalEscrowImplementation_locksAfterFirstSet() public {
        // setUp already set + locked it; a second set must revert.
        vm.expectRevert(ShwounsDAOLogic.EscrowImplLocked.selector);
        dao.setProposalEscrowImplementation(address(0xCAFE));
    }
}
