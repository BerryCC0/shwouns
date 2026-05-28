// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {ShwounsArt} from "../../src/token/ShwounsArt.sol";
import {ShwounsDescriptor} from "../../src/token/ShwounsDescriptor.sol";
import {Inflator} from "../../src/token/Inflator.sol";
import {SVGRenderer} from "../../src/token/SVGRenderer.sol";
import {IShwounsArt} from "../../src/interfaces/IShwounsArt.sol";
import {ISVGRenderer} from "../../src/interfaces/ISVGRenderer.sol";
import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";

/// @notice Exercises the full art pipeline — deploys Inflator, SVGRenderer, ShwounsArt, and
///         ShwounsDescriptor (no MockDescriptor), then verifies the Descriptor can populate
///         the Art via its onlyOwner functions. Confirms the deploy-time setDescriptor handoff
///         transfers control of Art from the Deploy contract to the Descriptor.
contract ArtPipelineTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    Deploy deployer;
    Deploy.Deployment d;
    Deploy.Config cfg;

    address operator = makeAddr("operator");
    address foundersDAO = makeAddr("foundersDAO");

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        MockWETH weth = new MockWETH();

        cfg = Deploy.Config({
            foundersDAO: foundersDAO,
            weth: address(weth),
            auctionDuration: 86400,
            reservePrice: 0.01 ether,
            timeBuffer: 300,
            minBidIncrementPct: 2,
            votingDelay: 1,
            votingPeriod: 5,
            proposalThresholdBPS: 0,
            quorumVotesBPS: 1000,
            giMintPrice: 0.01 ether,
            proposalReward: 0.1 ether,
            maxRefundPerVote: 0.003 ether,
            lastMinuteWindowBlocks: 1,
            objectionPeriodBlocks: 3,
            // No pre-deployed art / renderer — Deploy script builds the full stack
            art: IShwounsArt(address(0)),
            renderer: ISVGRenderer(address(0)),
            preDeployedDescriptor: IShwounsDescriptorMinimal(address(0)),
            adminTarget: operator
        });

        deployer = new Deploy();
        d = deployer._deploy(cfg);
        vm.prank(operator);
        d.dao.acceptAdmin();
    }

    function test_artStack_isDeployed() public {
        // All three new contracts should be deployed
        assertTrue(address(d.art).code.length > 0, "art deployed");
        assertTrue(address(d.inflator).code.length > 0, "inflator deployed");
        assertTrue(address(d.renderer).code.length > 0, "renderer deployed");
        assertTrue(address(d.descriptor).code.length > 0, "descriptor deployed");
    }

    function test_artStack_isWiredToDescriptor() public {
        // Descriptor was constructed with art + renderer
        assertEq(address(d.descriptor.art()), address(d.art));
        assertEq(address(d.descriptor.renderer()), address(d.renderer));

        // Art's descriptor handoff completed — Art's descriptor is now d.descriptor (not Deploy)
        assertEq(d.art.descriptor(), address(d.descriptor));

        // Art's inflator is wired
        assertEq(address(d.art.inflator()), address(d.inflator));
    }

    function test_descriptor_canPopulateBackgrounds() public {
        // Descriptor is owned by Deploy contract initially (matches other tests).
        // After we add a background via the Descriptor's owner-only function, the count goes up.
        vm.prank(address(deployer));
        d.descriptor.addBackground("ffffff");

        assertEq(d.art.backgroundCount(), 1);
        assertEq(d.art.backgrounds(0), "ffffff");

        // Add a batch
        string[] memory more = new string[](3);
        more[0] = "000000";
        more[1] = "112233";
        more[2] = "445566";
        vm.prank(address(deployer));
        d.descriptor.addManyBackgrounds(more);

        assertEq(d.art.backgroundCount(), 4);
        assertEq(d.art.backgrounds(3), "445566");
    }

    function test_descriptor_canSetPalette() public {
        // 3-color palette (9 bytes — 3 RGB triples)
        bytes memory palette = hex"ff0000" hex"00ff00" hex"0000ff";
        vm.prank(address(deployer));
        d.descriptor.setPalette(0, palette);

        bytes memory stored = d.art.palettes(0);
        assertEq(stored.length, 9);
        assertEq(uint8(stored[0]), 0xff);
        assertEq(uint8(stored[4]), 0xff);
        assertEq(uint8(stored[8]), 0xff);
    }

    function test_directArtCall_blockedForNonDescriptor() public {
        // Only the descriptor can call onlyDescriptor functions on Art directly
        vm.prank(operator);
        vm.expectRevert(IShwounsArt.SenderIsNotDescriptor.selector);
        d.art.addBackground("ffffff");
    }

    function test_descriptor_lockingPartsDisablesUpdates() public {
        vm.prank(address(deployer));
        d.descriptor.addBackground("ffffff");
        vm.prank(address(deployer));
        d.descriptor.lockParts();

        // Now further additions should revert (descriptor's whenPartsNotLocked check)
        vm.prank(address(deployer));
        vm.expectRevert("Parts are locked");
        d.descriptor.addBackground("000000");
    }
}
