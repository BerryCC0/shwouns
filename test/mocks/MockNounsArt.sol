// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { INounsArtView } from "../../script/CopyArtFromNouns.s.sol";

/// @dev Minimal mock of Nouns Art that returns canned data for testing CopyArtFromNouns.
contract MockNounsArt is INounsArtView {
    address public palette0Pointer;
    string[] internal _backgrounds;
    Trait internal _bodies;
    Trait internal _accessories;
    Trait internal _heads;

    function setPalette0(address ptr) external { palette0Pointer = ptr; }
    function addBackground(string calldata bg) external { _backgrounds.push(bg); }

    function setBodies(NounArtStoragePage[] memory pages, uint256 total) external {
        delete _bodies.storagePages;
        for (uint256 i = 0; i < pages.length; i++) _bodies.storagePages.push(pages[i]);
        _bodies.storedImagesCount = total;
    }

    function setAccessories(NounArtStoragePage[] memory pages, uint256 total) external {
        delete _accessories.storagePages;
        for (uint256 i = 0; i < pages.length; i++) _accessories.storagePages.push(pages[i]);
        _accessories.storedImagesCount = total;
    }

    function setHeads(NounArtStoragePage[] memory pages, uint256 total) external {
        delete _heads.storagePages;
        for (uint256 i = 0; i < pages.length; i++) _heads.storagePages.push(pages[i]);
        _heads.storedImagesCount = total;
    }

    // ── INounsArtView ──
    function palettesPointers(uint8) external view override returns (address) { return palette0Pointer; }
    function backgroundCount() external view override returns (uint256) { return _backgrounds.length; }
    function backgrounds(uint256 i) external view override returns (string memory) { return _backgrounds[i]; }
    function getBodiesTrait() external view override returns (Trait memory) { return _bodies; }
    function getAccessoriesTrait() external view override returns (Trait memory) { return _accessories; }
    function getHeadsTrait() external view override returns (Trait memory) { return _heads; }
}
