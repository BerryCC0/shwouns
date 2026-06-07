// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BootstrapFixture} from "./BootstrapFixture.sol";
import {ShwounsArt} from "../../src/token/ShwounsArt.sol";
import {ShwounsDescriptor} from "../../src/token/ShwounsDescriptor.sol";
import {IShwounsArt} from "../../src/interfaces/IShwounsArt.sol";

/// @notice Exercises the full art stack deployed by Bootstrap, driving every descriptor op through
///         Bootstrap.execute (Bootstrap owns the descriptor pre-handoff — the production art-load
///         path, audit F3). No vm.prank ownership cheat. Pre-finalize (registry unbound).
contract ArtPipelineTest is BootstrapFixture {
    ShwounsArt art;
    ShwounsDescriptor descriptor;
    address operator = makeAddr("operator");

    function setUp() public {
        _deploySystem();
        art = ShwounsArt(m.art);
        descriptor = ShwounsDescriptor(m.descriptor);
    }

    function _exec(bytes memory data) internal {
        b.execute(m.descriptor, data);
    }

    function test_artStack_isDeployed() public {
        assertTrue(m.art.code.length > 0, "art deployed");
        assertTrue(address(art.inflator()).code.length > 0, "inflator deployed");
        assertTrue(address(descriptor.renderer()).code.length > 0, "renderer deployed");
        assertTrue(m.descriptor.code.length > 0, "descriptor deployed");
    }

    function test_artStack_isWiredToDescriptor() public {
        assertEq(address(descriptor.art()), m.art);
        assertEq(art.descriptor(), m.descriptor); // Art's descriptor handoff completed
    }

    function test_descriptor_canPopulateBackgrounds() public {
        _exec(abi.encodeWithSignature("addBackground(string)", "ffffff"));
        assertEq(art.backgroundCount(), 1);
        assertEq(art.backgrounds(0), "ffffff");

        string[] memory more = new string[](3);
        more[0] = "000000";
        more[1] = "112233";
        more[2] = "445566";
        _exec(abi.encodeWithSignature("addManyBackgrounds(string[])", more));
        assertEq(art.backgroundCount(), 4);
        assertEq(art.backgrounds(3), "445566");
    }

    function test_descriptor_canSetPalette() public {
        bytes memory palette = hex"ff0000" hex"00ff00" hex"0000ff";
        _exec(abi.encodeWithSignature("setPalette(uint8,bytes)", uint8(0), palette));

        bytes memory stored = art.palettes(0);
        assertEq(stored.length, 9);
        assertEq(uint8(stored[0]), 0xff);
        assertEq(uint8(stored[4]), 0xff);
        assertEq(uint8(stored[8]), 0xff);
    }

    function test_directArtCall_blockedForNonDescriptor() public {
        vm.prank(operator);
        vm.expectRevert(IShwounsArt.SenderIsNotDescriptor.selector);
        art.addBackground("ffffff");
    }

    function test_descriptor_lockingPartsDisablesUpdates() public {
        _exec(abi.encodeWithSignature("addBackground(string)", "ffffff"));
        _exec(abi.encodeWithSignature("lockParts()"));

        // The descriptor's "Parts are locked" revert bubbles up through Bootstrap.execute.
        vm.expectRevert("Parts are locked");
        _exec(abi.encodeWithSignature("addBackground(string)", "000000"));
    }

    /// M-06: after lockParts(), the Art descriptor/inflator handoff is ALSO blocked — otherwise the
    /// owner could route Art authority to a fresh unlocked descriptor and mutate palettes/traits.
    function test_m06_artAuthorityHandoff_blockedAfterLockParts() public {
        _exec(abi.encodeWithSignature("lockParts()"));

        vm.expectRevert("Parts are locked");
        _exec(abi.encodeWithSignature("setArtDescriptor(address)", makeAddr("newDescriptor")));

        vm.expectRevert("Parts are locked");
        _exec(abi.encodeWithSignature("setArtInflator(address)", makeAddr("newInflator")));
    }
}
