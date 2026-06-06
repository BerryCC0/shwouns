// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Bootstrap} from "../../src/governance/Bootstrap.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {ShwounsArt} from "../../src/token/ShwounsArt.sol";
import {ShwounsDescriptor} from "../../src/token/ShwounsDescriptor.sol";
import {IShwounsArt} from "../../src/interfaces/IShwounsArt.sol";
import {ISVGRenderer} from "../../src/interfaces/ISVGRenderer.sol";
import {IInflator} from "../../src/interfaces/IInflator.sol";
import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";

/// @notice Exercises the full art stack deployed by Bootstrap (without finalize, so the registry is
///         unbound and Bootstrap remains the descriptor owner — the natural pre-handoff state).
contract ArtPipelineTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    Bootstrap b;
    ShwounsArt art;
    ShwounsDescriptor descriptor;
    address owner; // Bootstrap holds owner during the pre-handoff phase

    address operator = makeAddr("operator");
    address foundersDAO = makeAddr("foundersDAO");

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);
        MockWETH weth = new MockWETH();

        Bootstrap.Config memory cfg = Bootstrap.Config({
            foundersDAO: foundersDAO,
            weth: address(weth),
            auctionDuration: 86400,
            reservePrice: 0.01 ether,
            timeBuffer: 300,
            minBidIncrementPct: 2,
            votingDelay: 1,
            votingPeriod: 7200,
            proposalThresholdBPS: 1,
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400,
            quorumVotesBPS: 1000,
            giMintPrice: 0.01 ether,
            proposalReward: 0.1 ether,
            maxRefundPerVote: 0.003 ether,
            lastMinuteWindowBlocks: 1,
            objectionPeriodBlocks: 3,
            art: IShwounsArt(address(0)),
            renderer: ISVGRenderer(address(0)),
            preDeployedDescriptor: IShwounsDescriptorMinimal(address(0)) // build the full stack
        });
        b = new Bootstrap();
        b.deploy(cfg); // not finalized: registry unbound, Bootstrap owns the descriptor
        art = b.art();
        descriptor = b.descriptor();
        owner = address(b);
    }

    function test_artStack_isDeployed() public {
        assertTrue(address(art).code.length > 0, "art deployed");
        assertTrue(address(b.inflator()).code.length > 0, "inflator deployed");
        assertTrue(address(b.renderer()).code.length > 0, "renderer deployed");
        assertTrue(address(descriptor).code.length > 0, "descriptor deployed");
    }

    function test_artStack_isWiredToDescriptor() public {
        assertEq(address(descriptor.art()), address(art));
        assertEq(address(descriptor.renderer()), address(b.renderer()));
        assertEq(art.descriptor(), address(descriptor)); // Art's descriptor handoff completed
        assertEq(address(art.inflator()), address(b.inflator()));
    }

    function test_descriptor_canPopulateBackgrounds() public {
        vm.prank(owner);
        descriptor.addBackground("ffffff");
        assertEq(art.backgroundCount(), 1);
        assertEq(art.backgrounds(0), "ffffff");

        string[] memory more = new string[](3);
        more[0] = "000000";
        more[1] = "112233";
        more[2] = "445566";
        vm.prank(owner);
        descriptor.addManyBackgrounds(more);
        assertEq(art.backgroundCount(), 4);
        assertEq(art.backgrounds(3), "445566");
    }

    function test_descriptor_canSetPalette() public {
        bytes memory palette = hex"ff0000" hex"00ff00" hex"0000ff";
        vm.prank(owner);
        descriptor.setPalette(0, palette);

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
        vm.prank(owner);
        descriptor.addBackground("ffffff");
        vm.prank(owner);
        descriptor.lockParts();

        vm.prank(owner);
        vm.expectRevert("Parts are locked");
        descriptor.addBackground("000000");
    }

    /// M-06: after lockParts(), the Art descriptor/inflator handoff is ALSO blocked — otherwise the
    /// owner could route Art authority to a fresh unlocked descriptor and mutate palettes/traits,
    /// bypassing the lock.
    function test_m06_artAuthorityHandoff_blockedAfterLockParts() public {
        vm.prank(owner);
        descriptor.lockParts();

        vm.prank(owner);
        vm.expectRevert("Parts are locked");
        descriptor.setArtDescriptor(makeAddr("newDescriptor"));

        vm.prank(owner);
        vm.expectRevert("Parts are locked");
        descriptor.setArtInflator(IInflator(makeAddr("newInflator")));
    }
}
