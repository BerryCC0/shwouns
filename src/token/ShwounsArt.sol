// SPDX-License-Identifier: GPL-3.0

/// @title The Shwouns art storage contract
///
/// @notice Forked from NounsArt (nouns-monorepo @ main). Changes:
///   - Removed all glasses trait support (glassesTrait storage, addGlasses /
///     addGlassesFromPointer / updateGlasses / updateGlassesFromPointer,
///     getGlassesTrait, glasses(index), glassesCount, GlassesAdded / GlassesUpdated events).
///   - Interface swapped: INounsArt → IShwounsArt.
///   - Identical SSTORE2 storage layout for the remaining four trait types
///     (backgrounds, bodies, accessories, heads).
///
/// Original Copyright Nouns DAO, GPL-3.0. Modified for Shwouns.

pragma solidity ^0.8.6;

import { IShwounsArt } from '../interfaces/IShwounsArt.sol';
import { SSTORE2 } from '../libs/SSTORE2.sol';
import { IInflator } from '../interfaces/IInflator.sol';

contract ShwounsArt is IShwounsArt {
    /// @notice Current Shwouns Descriptor address
    address public override descriptor;

    /// @notice Current inflator address
    IInflator public override inflator;

    /// @notice Shwouns Backgrounds (Hex Colors)
    string[] public override backgrounds;

    /// @notice Shwouns Color Palettes (Index => Hex Colors, stored as a contract using SSTORE2)
    mapping(uint8 => address) public palettesPointers;

    /// @notice Shwouns Bodies Trait
    Trait public bodiesTrait;

    /// @notice Shwouns Accessories Trait
    Trait public accessoriesTrait;

    /// @notice Shwouns Heads Trait
    Trait public headsTrait;

    /// @notice Require that the sender is the descriptor.
    modifier onlyDescriptor() {
        if (msg.sender != descriptor) {
            revert SenderIsNotDescriptor();
        }
        _;
    }

    constructor(address _descriptor, IInflator _inflator) {
        descriptor = _descriptor;
        inflator = _inflator;
    }

    // -------------------------------------------------------------------------
    // Descriptor + Inflator setters
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function setDescriptor(address _descriptor) external override onlyDescriptor {
        address oldDescriptor = descriptor;
        descriptor = _descriptor;
        emit DescriptorUpdated(oldDescriptor, descriptor);
    }

    /// @inheritdoc IShwounsArt
    function setInflator(IInflator _inflator) external override onlyDescriptor {
        address oldInflator = address(inflator);
        inflator = _inflator;
        emit InflatorUpdated(oldInflator, address(_inflator));
    }

    // -------------------------------------------------------------------------
    // Trait getters (explicit because Solidity auto-getters don't return structs cleanly)
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function getBodiesTrait() external view override returns (Trait memory) { return bodiesTrait; }
    /// @inheritdoc IShwounsArt
    function getAccessoriesTrait() external view override returns (Trait memory) { return accessoriesTrait; }
    /// @inheritdoc IShwounsArt
    function getHeadsTrait() external view override returns (Trait memory) { return headsTrait; }

    // -------------------------------------------------------------------------
    // Background management
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function addManyBackgrounds(string[] calldata _backgrounds) external override onlyDescriptor {
        for (uint256 i = 0; i < _backgrounds.length; i++) {
            _addBackground(_backgrounds[i]);
        }
        emit BackgroundsAdded(_backgrounds.length);
    }

    /// @inheritdoc IShwounsArt
    function addBackground(string calldata _background) external override onlyDescriptor {
        _addBackground(_background);
        emit BackgroundsAdded(1);
    }

    function _addBackground(string calldata _background) internal {
        backgrounds.push(_background);
    }

    // -------------------------------------------------------------------------
    // Palette management
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function setPalette(uint8 paletteIndex, bytes calldata palette) external override onlyDescriptor {
        if (palette.length == 0) revert EmptyPalette();
        if (palette.length % 3 != 0 || palette.length > 768) revert BadPaletteLength();
        palettesPointers[paletteIndex] = SSTORE2.write(palette);
        emit PaletteSet(paletteIndex);
    }

    /// @inheritdoc IShwounsArt
    function setPalettePointer(uint8 paletteIndex, address pointer) external override onlyDescriptor {
        palettesPointers[paletteIndex] = pointer;
        emit PaletteSet(paletteIndex);
    }

    /// @inheritdoc IShwounsArt
    function palettes(uint8 paletteIndex) public view override returns (bytes memory) {
        address pointer = palettesPointers[paletteIndex];
        if (pointer == address(0)) revert PaletteNotFound();
        return SSTORE2.read(palettesPointers[paletteIndex]);
    }

    // -------------------------------------------------------------------------
    // Add trait pages (bodies / accessories / heads)
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function addBodies(
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        addPage(bodiesTrait, encodedCompressed, decompressedLength, imageCount);
        emit BodiesAdded(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function addAccessories(
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        addPage(accessoriesTrait, encodedCompressed, decompressedLength, imageCount);
        emit AccessoriesAdded(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function addHeads(
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        addPage(headsTrait, encodedCompressed, decompressedLength, imageCount);
        emit HeadsAdded(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function addBodiesFromPointer(
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        addPage(bodiesTrait, pointer, decompressedLength, imageCount);
        emit BodiesAdded(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function addAccessoriesFromPointer(
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        addPage(accessoriesTrait, pointer, decompressedLength, imageCount);
        emit AccessoriesAdded(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function addHeadsFromPointer(
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        addPage(headsTrait, pointer, decompressedLength, imageCount);
        emit HeadsAdded(imageCount);
    }

    // -------------------------------------------------------------------------
    // Update (replace) trait pages
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function updateBodies(
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        replaceTraitData(bodiesTrait, encodedCompressed, decompressedLength, imageCount);
        emit BodiesUpdated(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function updateAccessories(
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        replaceTraitData(accessoriesTrait, encodedCompressed, decompressedLength, imageCount);
        emit AccessoriesUpdated(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function updateHeads(
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        replaceTraitData(headsTrait, encodedCompressed, decompressedLength, imageCount);
        emit HeadsUpdated(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function updateBodiesFromPointer(
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        replaceTraitData(bodiesTrait, pointer, decompressedLength, imageCount);
        emit BodiesUpdated(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function updateAccessoriesFromPointer(
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        replaceTraitData(accessoriesTrait, pointer, decompressedLength, imageCount);
        emit AccessoriesUpdated(imageCount);
    }

    /// @inheritdoc IShwounsArt
    function updateHeadsFromPointer(
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) external override onlyDescriptor {
        replaceTraitData(headsTrait, pointer, decompressedLength, imageCount);
        emit HeadsUpdated(imageCount);
    }

    // -------------------------------------------------------------------------
    // Counts + image reads
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsArt
    function backgroundCount() external view override returns (uint256) { return backgrounds.length; }
    /// @inheritdoc IShwounsArt
    function bodyCount() external view override returns (uint256) { return bodiesTrait.storedImagesCount; }
    /// @inheritdoc IShwounsArt
    function accessoryCount() external view override returns (uint256) { return accessoriesTrait.storedImagesCount; }
    /// @inheritdoc IShwounsArt
    function headCount() external view override returns (uint256) { return headsTrait.storedImagesCount; }

    /// @inheritdoc IShwounsArt
    function bodies(uint256 index) public view override returns (bytes memory) {
        return imageByIndex(bodiesTrait, index);
    }

    /// @inheritdoc IShwounsArt
    function accessories(uint256 index) public view override returns (bytes memory) {
        return imageByIndex(accessoriesTrait, index);
    }

    /// @inheritdoc IShwounsArt
    function heads(uint256 index) public view override returns (bytes memory) {
        return imageByIndex(headsTrait, index);
    }

    // -------------------------------------------------------------------------
    // Internal page management
    // -------------------------------------------------------------------------

    function replaceTraitData(
        Trait storage trait,
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) internal {
        if (encodedCompressed.length == 0) revert EmptyBytes();
        delete trait.storagePages;
        delete trait.storedImagesCount;
        addPage(trait, encodedCompressed, decompressedLength, imageCount);
    }

    function replaceTraitData(
        Trait storage trait,
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) internal {
        if (decompressedLength == 0) revert BadDecompressedLength();
        if (imageCount == 0) revert BadImageCount();
        delete trait.storagePages;
        delete trait.storedImagesCount;
        addPage(trait, pointer, decompressedLength, imageCount);
    }

    function addPage(
        Trait storage trait,
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) internal {
        if (encodedCompressed.length == 0) revert EmptyBytes();
        address pointer = SSTORE2.write(encodedCompressed);
        addPage(trait, pointer, decompressedLength, imageCount);
    }

    function addPage(
        Trait storage trait,
        address pointer,
        uint80 decompressedLength,
        uint16 imageCount
    ) internal {
        if (decompressedLength == 0) revert BadDecompressedLength();
        if (imageCount == 0) revert BadImageCount();
        trait.storagePages.push(
            ShwounsArtStoragePage({ pointer: pointer, decompressedLength: decompressedLength, imageCount: imageCount })
        );
        trait.storedImagesCount += imageCount;
    }

    function imageByIndex(IShwounsArt.Trait storage trait, uint256 index)
        internal
        view
        returns (bytes memory)
    {
        (IShwounsArt.ShwounsArtStoragePage storage page, uint256 indexInPage) =
            getPage(trait.storagePages, index);
        bytes[] memory decompressedImages = decompressAndDecode(page);
        return decompressedImages[indexInPage];
    }

    /// @dev Given an image index, find the page it lives in and its index within that page.
    function getPage(IShwounsArt.ShwounsArtStoragePage[] storage pages, uint256 index)
        internal
        view
        returns (IShwounsArt.ShwounsArtStoragePage storage, uint256)
    {
        uint256 len = pages.length;
        uint256 pageFirstImageIndex = 0;
        for (uint256 i = 0; i < len; i++) {
            IShwounsArt.ShwounsArtStoragePage storage page = pages[i];
            if (index < pageFirstImageIndex + page.imageCount) {
                return (page, index - pageFirstImageIndex);
            }
            pageFirstImageIndex += page.imageCount;
        }
        revert ImageNotFound();
    }

    function decompressAndDecode(IShwounsArt.ShwounsArtStoragePage storage page)
        internal
        view
        returns (bytes[] memory)
    {
        bytes memory compressedData = SSTORE2.read(page.pointer);
        (, bytes memory decompressedData) = inflator.puff(compressedData, page.decompressedLength);
        return abi.decode(decompressedData, (bytes[]));
    }
}
