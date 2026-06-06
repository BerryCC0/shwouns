// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest, Flag} from "./LifecycleInvariants.t.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";

/// @dev On receiving ETH mid-finalize, re-enters rescueFromEscrow for the same (active) proposal —
///      must revert because the proposal is Executing, not terminal (round-6 finding 1).
contract ReentrantRescue {
    ShwounsDAOLogic public immutable dao;
    uint256 public pid;

    constructor(ShwounsDAOLogic _dao) {
        dao = _dao;
    }

    function setPid(uint256 _pid) external {
        pid = _pid;
    }

    receive() external payable {
        dao.rescueFromEscrow(pid, ShwounsDAOProposals.AssetKind.ETH, address(0), 0, 0);
    }
}

/// @title Residual recovery (A8) — terminal-gated rescue routes residuals to the immutable GR sink.
contract RescueTest is LifecycleInvariantsTest {
    /// @dev Drive a pure-governance proposal to terminal Executed; returns its escrow address.
    function _executedProposal() internal returns (uint256 pid, address escrow) {
        Flag flag = new Flag();
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cds = new bytes[](1);
        targets[0] = address(flag);
        values[0] = 0;
        cds[0] = abi.encodeWithSelector(Flag.setValue.selector, uint256(1));
        vm.prank(alice);
        pid = dao.propose(targets, values, sigs, cds, "gov");
        _passToSucceeded(pid);
        dao.queue(pid);
        escrow = dao.escrowAddressOf(pid);
        dao.finalize(pid); // terminal Executed
    }

    function test_rescueETH_afterExecuted_routesToSink() public {
        (uint256 pid, address escrow) = _executedProposal();
        vm.deal(address(this), 1 ether);
        (bool ok, ) = escrow.call{ value: 1 ether }("");
        assertTrue(ok);

        uint256 sinkBefore = address(escrowSink).balance;
        dao.rescueFromEscrow(pid, ShwounsDAOProposals.AssetKind.ETH, address(0), 0, 0);
        assertEq(escrow.balance, 0, "escrow ETH swept");
        assertEq(address(escrowSink).balance - sinkBefore, 1 ether, "residual ETH to GR sink");
    }

    function test_rescueERC20_afterExecuted_routesToSink() public {
        (uint256 pid, address escrow) = _executedProposal();
        MockERC20 t = new MockERC20();
        t.mint(escrow, 100 ether);
        dao.rescueFromEscrow(pid, ShwounsDAOProposals.AssetKind.ERC20, address(t), 0, 0);
        assertEq(t.balanceOf(escrow), 0, "escrow ERC20 swept");
        assertEq(t.balanceOf(address(escrowSink)), 100 ether, "residual ERC20 to GR sink");
    }

    function test_rescueERC721_afterExecuted_routesToSink() public {
        (uint256 pid, address escrow) = _executedProposal();
        MockERC721 n = new MockERC721();
        n.mint(escrow, 7);
        dao.rescueFromEscrow(pid, ShwounsDAOProposals.AssetKind.ERC721, address(n), 7, 0);
        assertEq(n.ownerOf(7), address(escrowSink), "residual ERC721 to GR sink");
    }

    function test_rescueERC1155_afterExecuted_routesToSink() public {
        (uint256 pid, address escrow) = _executedProposal();
        MockERC1155 m = new MockERC1155();
        m.mint(escrow, 3, 50);
        dao.rescueFromEscrow(pid, ShwounsDAOProposals.AssetKind.ERC1155, address(m), 3, 50);
        assertEq(m.balanceOf(escrow, 3), 0, "escrow ERC1155 swept");
        assertEq(m.balanceOf(address(escrowSink), 3), 50, "residual ERC1155 to GR sink");
    }

    /// Before terminal the escrow holds live proposal funding — rescue must revert (no theft).
    function test_rescue_revertsBeforeTerminal() public {
        uint256 pid = _proposeETH(alice, recipientA, 2 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 100);
        dao.collect(pid, 100); // state Collected; escrow holds 2 ETH of live funding

        vm.expectRevert(ShwounsDAOProposals.NotTerminal.selector);
        dao.rescueFromEscrow(pid, ShwounsDAOProposals.AssetKind.ETH, address(0), 0, 0);
        assertEq(_escrowBal(pid), 2 ether, "live funding untouched by a pre-terminal rescue attempt");
    }

    /// A reentrant rescue of the active proposal mid-finalize reverts (status Executing, not
    /// Executed) and rolls the whole finalize back; the live escrow is untouched.
    function test_reentrantRescue_duringFinalize_reverts() public {
        ReentrantRescue attacker = new ReentrantRescue(dao);
        uint256 pid = _proposeETH(bob, address(attacker), 1 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 100);
        dao.collect(pid, 100);
        attacker.setPid(pid);

        vm.expectRevert();
        dao.finalize(pid);

        assertEq(_escrowBal(pid), 1 ether, "live escrow untouched after reverted reentrant rescue");
        assertFalse(dao.executing(), "lock cleared");
    }
}
