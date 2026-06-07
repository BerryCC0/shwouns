// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BootstrapFixture} from "./BootstrapFixture.sol";
import {Bootstrap} from "../../src/governance/Bootstrap.sol";
import {CopyArtFromNouns, INounsArtView} from "../../script/CopyArtFromNouns.s.sol";
import {MockNounsArt} from "../mocks/MockNounsArt.sol";
import {ShwounsArt} from "../../src/token/ShwounsArt.sol";

/// @notice Proves the production art-copy flow (audit F3): the descriptor is owned by Bootstrap, and
///         art is loaded by routing the descriptor's onlyOwner ops through Bootstrap.executeBatch.
///         The op list is built by the script's pure buildOps(); the operator (this test) executes it.
contract CopyArtFromNounsTest is BootstrapFixture {
    ShwounsArt art;
    CopyArtFromNouns copyScript;
    MockNounsArt mockNounsArt;

    function setUp() public {
        _deploySystem();
        art = ShwounsArt(m.art);
        copyScript = new CopyArtFromNouns();

        mockNounsArt = new MockNounsArt();
        mockNounsArt.setPalette0(address(0xCAFE));
        mockNounsArt.addBackground("e1d7d5");
        mockNounsArt.addBackground("d5d7e1");

        INounsArtView.NounArtStoragePage[] memory bodyPages = new INounsArtView.NounArtStoragePage[](2);
        bodyPages[0] = INounsArtView.NounArtStoragePage({ imageCount: 15, decompressedLength: 1000, pointer: address(0x1001) });
        bodyPages[1] = INounsArtView.NounArtStoragePage({ imageCount: 15, decompressedLength: 1000, pointer: address(0x1002) });
        mockNounsArt.setBodies(bodyPages, 30);

        INounsArtView.NounArtStoragePage[] memory accPages = new INounsArtView.NounArtStoragePage[](5);
        for (uint256 i = 0; i < 5; i++) {
            accPages[i] = INounsArtView.NounArtStoragePage({ imageCount: 28, decompressedLength: 5000, pointer: address(uint160(0x2000 + i)) });
        }
        mockNounsArt.setAccessories(accPages, 140);

        INounsArtView.NounArtStoragePage[] memory headPages = new INounsArtView.NounArtStoragePage[](10);
        for (uint256 i = 0; i < 10; i++) {
            headPages[i] = INounsArtView.NounArtStoragePage({ imageCount: 24, decompressedLength: 10000, pointer: address(uint160(0x3000 + i)) });
        }
        mockNounsArt.setHeads(headPages, 240);
    }

    /// @dev Build the op list (script logic) and execute it through Bootstrap as the operator (this).
    function _runCopy() internal {
        (address[] memory targets, bytes[] memory datas) = copyScript.buildOps(m.descriptor, mockNounsArt);
        b.executeBatch(targets, datas);
    }

    function test_copy_setsAllArtCorrectly() public {
        // Before copy, ShwounsArt is empty.
        assertEq(art.backgroundCount(), 0);
        assertEq(art.bodyCount(), 0);
        assertEq(art.accessoryCount(), 0);
        assertEq(art.headCount(), 0);

        _runCopy();

        assertEq(art.backgroundCount(), 2);
        assertEq(art.backgrounds(0), "e1d7d5");
        assertEq(art.backgrounds(1), "d5d7e1");
        assertEq(art.palettesPointers(0), address(0xCAFE));
        assertEq(art.bodyCount(), 30);
        assertEq(art.accessoryCount(), 140);
        assertEq(art.headCount(), 240);
    }

    function test_copy_skipsGlassesEntirely() public {
        // The mock + ShwounsArt have no glasses surface; running copy with no glasses data succeeds.
        _runCopy();
        assertEq(art.headCount(), 240);
    }

    /// @dev F3/F2: art is loaded ONLY through the Bootstrap operator. A non-operator routing the same
    ///      ops reverts (the descriptor's onlyOwner is Bootstrap, and Bootstrap's executeBatch is
    ///      operator-gated) — so the EOA can't drive the descriptor directly.
    function test_copy_onlyOperatorCanDrive() public {
        (address[] memory targets, bytes[] memory datas) = copyScript.buildOps(m.descriptor, mockNounsArt);
        vm.prank(makeAddr("random"));
        vm.expectRevert(Bootstrap.NotOperator.selector);
        b.executeBatch(targets, datas);
    }
}
