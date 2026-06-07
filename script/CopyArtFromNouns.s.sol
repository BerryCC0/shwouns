// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { Bootstrap } from "../src/governance/Bootstrap.sol";

/// @title CopyArtFromNouns — populate ShwounsArt by reusing Nouns Art's SSTORE2 pointers
///
/// @notice Nouns DAO's art is CC0. Nouns Art stores each batch of compressed images at an SSTORE2
///         contract whose address is recorded on-chain. Since SSTORE2 storage is just bytecode,
///         anyone can READ it — we don't re-upload the image data, just record the same pointer in
///         ShwounsArt. Glasses are SKIPPED (Shwouns has no glasses trait).
///
/// @dev AUDIT F3 fix: the descriptor's owner during deployment is the BOOTSTRAP (not the operator
///      EOA), so the operator cannot call the descriptor's `onlyOwner` art functions directly (the
///      old script did, and only the test's `vm.prank` masked it). Every descriptor op is now routed
///      through `bootstrap.execute`/`executeBatch` (operator → Bootstrap → descriptor), which is the
///      real production flow. Run BEFORE finalizeBootstrap (which locks ownership to the DAO).
///
/// Gas: per-page copy is ~50-80k gas (store a pointer + bump a counter); the full copy is ~20-30 ops,
///      batched into a single executeBatch (~2-3M gas, well under the block limit) — under $50.
///
/// CHAIN REQUIREMENT: only works on Ethereum mainnet (where Nouns Art is deployed) or a mainnet fork.
///
/// Usage:
///   SHWOUNS_BOOTSTRAP=<bootstrap> SHWOUNS_DESCRIPTOR=<descriptor>
///     forge script script/CopyArtFromNouns.s.sol --rpc-url $MAINNET_RPC --broadcast
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
        Bootstrap b = Bootstrap(vm.envAddress("SHWOUNS_BOOTSTRAP"));
        address descriptor = vm.envAddress("SHWOUNS_DESCRIPTOR");
        address nounsArt = vm.envOr("NOUNS_ART", NOUNS_ART_MAINNET);
        vm.startBroadcast();
        copy(b, descriptor, INounsArtView(nounsArt));
        vm.stopBroadcast();
    }

    /// @notice Copy art from `source` (a Nouns Art contract) into the Bootstrap-owned `descriptor`,
    ///         driving every (onlyOwner) descriptor op through `bootstrap.executeBatch`. Must be called
    ///         BY the Bootstrap operator (run()'s broadcaster). Tests call buildOps() + executeBatch
    ///         directly (so the call originates from the test = operator).
    function copy(Bootstrap b, address descriptor, INounsArtView source) public {
        (address[] memory targets, bytes[] memory datas) = buildOps(descriptor, source);
        b.executeBatch(targets, datas);
        console.log("Copied art via Bootstrap.executeBatch; ops:", targets.length);
    }

    /// @notice Pure builder: produce the (target, calldata) op list that reuses Nouns Art's SSTORE2
    ///         pointers into `descriptor`. Every target is the descriptor; the caller routes them
    ///         through Bootstrap.executeBatch. Glasses are intentionally skipped.
    function buildOps(address descriptor, INounsArtView source)
        public
        view
        returns (address[] memory targets, bytes[] memory datas)
    {
        address palette0 = source.palettesPointers(0);
        require(palette0 != address(0), "Nouns palette 0 not set");

        INounsArtView.Trait memory bodies = source.getBodiesTrait();
        INounsArtView.Trait memory accessories = source.getAccessoriesTrait();
        INounsArtView.Trait memory heads = source.getHeadsTrait();

        uint256 bgCount = source.backgroundCount();
        string[] memory bgs = new string[](bgCount);
        for (uint256 i = 0; i < bgCount; i++) bgs[i] = source.backgrounds(i);

        uint256 n = 2 + bodies.storagePages.length + accessories.storagePages.length + heads.storagePages.length;
        targets = new address[](n);
        datas = new bytes[](n);
        for (uint256 i = 0; i < n; i++) targets[i] = descriptor;

        uint256 k = 0;
        // 1. Palette 0 (Nouns uses only index 0). 2. Backgrounds.
        datas[k++] = abi.encodeWithSignature("setPalettePointer(uint8,address)", uint8(0), palette0);
        datas[k++] = abi.encodeWithSignature("addManyBackgrounds(string[])", bgs);
        // 3-5. Bodies / accessories / heads pages (by SSTORE2 pointer).
        k = _appendPages(datas, k, "addBodiesFromPointer(address,uint80,uint16)", bodies.storagePages);
        k = _appendPages(datas, k, "addAccessoriesFromPointer(address,uint80,uint16)", accessories.storagePages);
        k = _appendPages(datas, k, "addHeadsFromPointer(address,uint80,uint16)", heads.storagePages);
    }

    function _appendPages(
        bytes[] memory datas,
        uint256 k,
        string memory sig,
        INounsArtView.NounArtStoragePage[] memory pages
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < pages.length; i++) {
            datas[k++] = abi.encodeWithSignature(sig, pages[i].pointer, pages[i].decompressedLength, pages[i].imageCount);
        }
        return k;
    }
}
