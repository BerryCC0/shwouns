// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { ShwounsDescriptor } from "../src/token/ShwounsDescriptor.sol";

/// @title CopyArtFromNouns — populate ShwounsArt by reusing Nouns Art's SSTORE2 pointers
///
/// @notice Nouns DAO's art is CC0. Nouns Art stores each batch of compressed images at
///         an SSTORE2 contract whose address is recorded on-chain. Since SSTORE2 storage
///         is just bytecode, anyone can READ from it — we don't need to re-upload the
///         image data, just record the same pointer in our ShwounsArt contract.
///
/// What this script does:
///   1. Read Nouns Art's palette 0 pointer → store the same pointer in ShwounsArt.
///   2. Read Nouns Art's backgrounds → copy them via descriptor.addManyBackgrounds.
///   3. For bodies / accessories / heads: iterate Nouns Art's storagePages and call
///      descriptor.add*FromPointer(...) for each one.
///   4. SKIP glasses entirely — that trait doesn't exist in Shwouns.
///
/// Gas/cost: This is dramatically cheaper than re-uploading. Per-page copy is ~50-80k
///   gas (just storing a pointer + bumping a counter). Full copy is roughly 20-30 txs,
///   totaling ~3-5M gas — under $50 at typical mainnet gas prices.
///
/// CHAIN REQUIREMENT: Only works on Ethereum mainnet (where Nouns Art is deployed),
///   or against a mainnet fork. For testnet / L2 deployments, you need to either:
///     (a) Bridge the SSTORE2 pointers (not supported by any standard bridge)
///     (b) Re-encode and re-upload from Nouns' source PNGs using the nouns-assets
///         NPM package (sdk-lite encoder), OR
///     (c) Use Nouns' own deployed-on-L2 Art contract if/when one exists.
///
/// Usage:
///   FORK:    forge script script/CopyArtFromNouns.s.sol --rpc-url $MAINNET_RPC --broadcast
///            (set SHWOUNS_DESCRIPTOR env var to the address from Deploy.s.sol)

interface INounsArtView {
    struct NounArtStoragePage {
        uint16 imageCount;
        uint80 decompressedLength;
        address pointer;
    }
    struct Trait {
        NounArtStoragePage[] storagePages;
        uint256 storedImagesCount;
    }

    function palettesPointers(uint8) external view returns (address);
    function backgroundCount() external view returns (uint256);
    function backgrounds(uint256) external view returns (string memory);
    function getBodiesTrait() external view returns (Trait memory);
    function getAccessoriesTrait() external view returns (Trait memory);
    function getHeadsTrait() external view returns (Trait memory);
}

contract CopyArtFromNouns is Script {
    /// @notice Nouns Art on Ethereum mainnet. Verified via NounsDescriptorV3.art().
    address public constant NOUNS_ART_MAINNET = 0x6544bC8A0dE6ECe429F14840BA74611cA5098A92;

    function run() external {
        address descriptor = vm.envAddress("SHWOUNS_DESCRIPTOR");
        address nounsArt = vm.envOr("NOUNS_ART", NOUNS_ART_MAINNET);
        vm.startBroadcast();
        copy(ShwounsDescriptor(descriptor), INounsArtView(nounsArt));
        vm.stopBroadcast();
    }

    /// @notice Copy art from `source` (a Nouns Art contract) into `descriptor` (which writes
    ///         to its bound ShwounsArt). Caller must own the descriptor. Called by run() or
    ///         directly from tests / other scripts.
    function copy(ShwounsDescriptor descriptor, INounsArtView source) public {
        // ─── 1. Palette 0 ─────────────────────────────────────────────────
        // Nouns currently uses only palette index 0. If you ever need more, add a loop.
        address palette0 = source.palettesPointers(0);
        require(palette0 != address(0), "Nouns palette 0 not set");
        descriptor.setPalettePointer(0, palette0);
        console.log("Set palette pointer 0:", palette0);

        // ─── 2. Backgrounds ───────────────────────────────────────────────
        uint256 bgCount = source.backgroundCount();
        string[] memory bgs = new string[](bgCount);
        for (uint256 i = 0; i < bgCount; i++) {
            bgs[i] = source.backgrounds(i);
        }
        descriptor.addManyBackgrounds(bgs);
        console.log("Copied backgrounds:", bgCount);

        // ─── 3. Bodies pages ─────────────────────────────────────────────
        INounsArtView.Trait memory bodies = source.getBodiesTrait();
        for (uint256 i = 0; i < bodies.storagePages.length; i++) {
            INounsArtView.NounArtStoragePage memory p = bodies.storagePages[i];
            descriptor.addBodiesFromPointer(p.pointer, p.decompressedLength, p.imageCount);
        }
        console.log("Copied body pages:", bodies.storagePages.length, "total images:", bodies.storedImagesCount);

        // ─── 4. Accessories pages ────────────────────────────────────────
        INounsArtView.Trait memory accessories = source.getAccessoriesTrait();
        for (uint256 i = 0; i < accessories.storagePages.length; i++) {
            INounsArtView.NounArtStoragePage memory p = accessories.storagePages[i];
            descriptor.addAccessoriesFromPointer(p.pointer, p.decompressedLength, p.imageCount);
        }
        console.log("Copied accessory pages:", accessories.storagePages.length, "total images:", accessories.storedImagesCount);

        // ─── 5. Heads pages ──────────────────────────────────────────────
        INounsArtView.Trait memory heads = source.getHeadsTrait();
        for (uint256 i = 0; i < heads.storagePages.length; i++) {
            INounsArtView.NounArtStoragePage memory p = heads.storagePages[i];
            descriptor.addHeadsFromPointer(p.pointer, p.decompressedLength, p.imageCount);
        }
        console.log("Copied head pages:", heads.storagePages.length, "total images:", heads.storedImagesCount);

        // ─── 6. Glasses: INTENTIONALLY SKIPPED ───────────────────────────
        // Shwouns has no glasses trait. Nouns' glasses pages stay where they are; we don't
        // reference them.
    }
}
