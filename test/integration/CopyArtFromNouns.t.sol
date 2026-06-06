// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {CopyArtFromNouns, INounsArtView} from "../../script/CopyArtFromNouns.s.sol";
import {MockNounsArt} from "../mocks/MockNounsArt.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {IShwounsArt} from "../../src/interfaces/IShwounsArt.sol";
import {ISVGRenderer} from "../../src/interfaces/ISVGRenderer.sol";
import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";

contract CopyArtFromNounsTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    Deploy deployer;
    Deploy.Deployment d;
    CopyArtFromNouns copyScript;
    MockNounsArt mockNounsArt;

    address operator = makeAddr("operator");
    address foundersDAO = makeAddr("foundersDAO");

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        MockWETH weth = new MockWETH();

        // Deploy the full art stack
        Deploy.Config memory cfg = Deploy.Config({
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
            preDeployedDescriptor: IShwounsDescriptorMinimal(address(0)),
            adminTarget: operator
        });
        deployer = new Deploy();
        d = deployer._deploy(cfg);

        // Set up the mock Nouns Art with realistic data
        mockNounsArt = new MockNounsArt();
        copyScript = new CopyArtFromNouns();

        // Palette pointer — just any address; it's stored as-is
        mockNounsArt.setPalette0(address(0xCAFE));

        // 2 backgrounds
        mockNounsArt.addBackground("e1d7d5");
        mockNounsArt.addBackground("d5d7e1");

        // Bodies: 2 pages, 30 total images (matches Nouns' deployment shape)
        INounsArtView.NounArtStoragePage[] memory bodyPages = new INounsArtView.NounArtStoragePage[](2);
        bodyPages[0] = INounsArtView.NounArtStoragePage({ imageCount: 15, decompressedLength: 1000, pointer: address(0x1001) });
        bodyPages[1] = INounsArtView.NounArtStoragePage({ imageCount: 15, decompressedLength: 1000, pointer: address(0x1002) });
        mockNounsArt.setBodies(bodyPages, 30);

        // Accessories: 5 pages, 140 total
        INounsArtView.NounArtStoragePage[] memory accPages = new INounsArtView.NounArtStoragePage[](5);
        for (uint256 i = 0; i < 5; i++) {
            accPages[i] = INounsArtView.NounArtStoragePage({
                imageCount: 28, decompressedLength: 5000, pointer: address(uint160(0x2000 + i))
            });
        }
        mockNounsArt.setAccessories(accPages, 140);

        // Heads: 10 pages, 240 total
        INounsArtView.NounArtStoragePage[] memory headPages = new INounsArtView.NounArtStoragePage[](10);
        for (uint256 i = 0; i < 10; i++) {
            headPages[i] = INounsArtView.NounArtStoragePage({
                imageCount: 24, decompressedLength: 10000, pointer: address(uint160(0x3000 + i))
            });
        }
        mockNounsArt.setHeads(headPages, 240);
    }

    function test_copy_setsAllArtCorrectly() public {
        // Sanity: before copy, ShwounsArt is empty
        assertEq(d.art.backgroundCount(), 0);
        assertEq(d.art.bodyCount(), 0);
        assertEq(d.art.accessoryCount(), 0);
        assertEq(d.art.headCount(), 0);

        // Copy script makes internal calls to descriptor's onlyOwner functions. Transfer
        // descriptor ownership to the copy script for the duration of the operation.
        vm.prank(address(deployer));
        d.descriptor.transferOwnership(address(copyScript));
        copyScript.copy(d.descriptor, mockNounsArt);

        // Verify everything got copied
        assertEq(d.art.backgroundCount(), 2);
        assertEq(d.art.backgrounds(0), "e1d7d5");
        assertEq(d.art.backgrounds(1), "d5d7e1");

        // Palette pointer copied (read by Art via SSTORE2.read; here we just check the pointer
        // mapping was updated — the actual palette() read would attempt to SSTORE2.read from
        // address(0xCAFE) which has no code, so it'd revert. That's fine for this test —
        // mainnet has real pointers).
        assertEq(d.art.palettesPointers(0), address(0xCAFE));

        // Bodies: 30 total images via 2 pages
        assertEq(d.art.bodyCount(), 30);
        // Accessories: 140 via 5 pages
        assertEq(d.art.accessoryCount(), 140);
        // Heads: 240 via 10 pages
        assertEq(d.art.headCount(), 240);
    }

    function test_copy_skipsGlassesEntirely() public {
        // Mock has no glasses-related methods (and ShwounsArt has no glasses storage either).
        // The script doesn't reference glasses. This test just documents that fact —
        // simply running copy() with no glasses-related data succeeds.
        vm.prank(address(deployer));
        d.descriptor.transferOwnership(address(copyScript));
        copyScript.copy(d.descriptor, mockNounsArt);

        // Verify the Shwouns Art struct has no glasses-related fields by examining the
        // descriptor's getPartsForSeed return — should be 3 parts (body, accessory, head).
        // The Art itself doesn't even expose a glassesCount() function (we stripped it
        // in IShwounsArt). So no test surface to assert against — the absence is the test.
        assertEq(d.art.headCount(), 240); // last assertion as a smoke check
    }

    function test_copy_requiresOwnership() public {
        // Copy requires calling descriptor.addManyBackgrounds (etc.) which is onlyOwner.
        // The descriptor's owner is the Deploy contract; some other caller can't drive it.
        address randomCaller = makeAddr("random");
        vm.prank(randomCaller);
        vm.expectRevert("Ownable: caller is not the owner");
        copyScript.copy(d.descriptor, mockNounsArt);
    }
}
