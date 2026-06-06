// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest, Flag} from "./LifecycleInvariants.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {GovernanceAuthRegistry} from "../../src/governance/GovernanceAuthRegistry.sol";
import {ShwounsAuctionHouse} from "../../src/auction/ShwounsAuctionHouse.sol";
import {IShwounsToken} from "../../src/interfaces/IShwounsToken.sol";
import {IChainalysisSanctionsList} from "../../src/interfaces/IChainalysisSanctionsList.sol";

/// @dev Storage-compatible DAOLogic upgrade target (adds only a pure function).
contract ShwounsDAOLogicV2Mock is ShwounsDAOLogic {
    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @dev Storage-compatible auction-house upgrade target reporting the same governanceAuth.
contract ShwounsAuctionHouseV2Mock is ShwounsAuctionHouse {
    constructor(IShwounsToken s, address w, uint256 d, address a) ShwounsAuctionHouse(s, w, d, a) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @title UUPS upgrade invariants (A9) — upgrades only via an authenticated active escrow.
contract UpgradesTest is LifecycleInvariantsTest {
    function _proposeCall(address proposer, address target, bytes memory data) internal returns (uint256 pid) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cds = new bytes[](1);
        targets[0] = target; cds[0] = data;
        vm.prank(proposer);
        pid = dao.propose(targets, values, sigs, cds, "upgrade");
    }

    // ---- DAOLogic self-upgrade ----

    function test_daoLogicUpgrade_viaProposal_finalAction_succeeds() public {
        ShwounsDAOLogicV2Mock v2 = new ShwounsDAOLogicV2Mock();
        uint256 pid = _proposeCall(alice, address(dao), abi.encodeWithSignature("upgradeTo(address)", address(v2)));
        _passToSucceeded(pid);
        dao.queue(pid); // upgrade is the only (hence final) action → passes queue validation
        dao.finalize(pid);

        assertEq(ShwounsDAOLogicV2Mock(payable(address(dao))).version(), 2, "proxy now runs v2 impl");
        assertFalse(dao.executing(), "old finalize frame cleared authentication");
        assertEq(dao.activeProposalId(), 0, "activeProposalId cleared");
    }

    function test_daoLogicUpgrade_nonFinalAction_rejectedAtQueue() public {
        Flag flag = new Flag();
        ShwounsDAOLogicV2Mock v2 = new ShwounsDAOLogicV2Mock();
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        string[] memory sigs = new string[](2);
        bytes[] memory cds = new bytes[](2);
        targets[0] = address(dao); cds[0] = abi.encodeWithSignature("upgradeTo(address)", address(v2));
        targets[1] = address(flag); cds[1] = abi.encodeWithSelector(Flag.setValue.selector, uint256(1));
        vm.prank(alice);
        uint256 pid = dao.propose(targets, values, sigs, cds, "upgrade not last");
        _passToSucceeded(pid);

        vm.expectRevert(ShwounsDAOProposals.UpgradeMustBeLastAction.selector);
        dao.queue(pid);
    }

    function test_daoLogicUpgrade_directNonExecutor_reverts() public {
        ShwounsDAOLogicV2Mock v2 = new ShwounsDAOLogicV2Mock();
        vm.expectRevert(ShwounsDAOLogic.NotActiveExecutor.selector);
        dao.upgradeTo(address(v2)); // not the active escrow → rejected
    }

    // ---- AuctionHouse upgrade ----

    function _deployAuctionHouse(address auth) internal returns (ShwounsAuctionHouse ah) {
        ShwounsAuctionHouse impl = new ShwounsAuctionHouse(IShwounsToken(address(token)), address(0), 86400, auth);
        bytes memory init = abi.encodeWithSelector(
            ShwounsAuctionHouse.initialize.selector,
            uint192(0.01 ether), uint56(300), uint8(2), IChainalysisSanctionsList(address(0))
        );
        ah = ShwounsAuctionHouse(payable(address(new ERC1967Proxy(address(impl), init))));
    }

    function test_auctionHouseUpgrade_viaProposal_succeeds() public {
        ShwounsAuctionHouse ah = _deployAuctionHouse(address(authRegistry));
        ShwounsAuctionHouseV2Mock newImpl =
            new ShwounsAuctionHouseV2Mock(IShwounsToken(address(token)), address(0), 86400, address(authRegistry));

        uint256 pid = _proposeCall(alice, address(ah), abi.encodeWithSignature("upgradeTo(address)", address(newImpl)));
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.finalize(pid); // escrow drives the upgrade; candidate reports the canonical registry

        assertEq(ShwounsAuctionHouseV2Mock(payable(address(ah))).version(), 2, "AH proxy now runs v2");
    }

    function test_auctionHouseUpgrade_candidateRegistryMismatch_reverts() public {
        ShwounsAuctionHouse ah = _deployAuctionHouse(address(authRegistry));
        GovernanceAuthRegistry wrong = new GovernanceAuthRegistry();
        ShwounsAuctionHouseV2Mock badImpl =
            new ShwounsAuctionHouseV2Mock(IShwounsToken(address(token)), address(0), 86400, address(wrong));

        uint256 pid = _proposeCall(alice, address(ah), abi.encodeWithSignature("upgradeTo(address)", address(badImpl)));
        _passToSucceeded(pid);
        dao.queue(pid);
        // candidate reports a different registry → _authorizeUpgrade rejects → finalize reverts
        vm.expectRevert();
        dao.finalize(pid);
    }
}
