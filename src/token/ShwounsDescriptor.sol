// SPDX-License-Identifier: GPL-3.0

/// @title The Shwouns NFT descriptor
/// @notice Forked from NounsDescriptorV3 (nouns-monorepo @ main). Glasses trait removed:
///   - No `glasses(uint256)` / `glassesCount` views
///   - No `addGlasses` / `addGlassesFromPointer` / `updateGlasses` / `updateGlassesFromPointer`
///   - `getPartsForSeed` returns 4 parts (background, body, accessory, head) instead of 5

pragma solidity ^0.8.6;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import { IShwounsDescriptor } from '../interfaces/IShwounsDescriptor.sol';
import { IShwounsSeeder } from '../interfaces/IShwounsSeeder.sol';
import { NFTDescriptorV2 } from '../libs/NFTDescriptorV2.sol';
import { ISVGRenderer } from '../interfaces/ISVGRenderer.sol';
import { IShwounsArt } from '../interfaces/IShwounsArt.sol';
import { IInflator } from '../interfaces/IInflator.sol';

contract ShwounsDescriptor is IShwounsDescriptor, Ownable {
    using Strings for uint256;

    // https://creativecommons.org/publicdomain/zero/1.0/legalcode.txt
    bytes32 constant COPYRIGHT_CC0_1_0_UNIVERSAL_LICENSE = 0xa2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499;

    IShwounsArt public art;
    ISVGRenderer public renderer;

    bool public override arePartsLocked;
    bool public override isDataURIEnabled = true;
    string public override baseURI;

    modifier whenPartsNotLocked() {
        require(!arePartsLocked, 'Parts are locked');
        _;
    }

    constructor(IShwounsArt _art, ISVGRenderer _renderer) {
        art = _art;
        renderer = _renderer;
    }

    function setArt(IShwounsArt _art) external onlyOwner whenPartsNotLocked {
        art = _art;
        emit ArtUpdated(_art);
    }

    function setRenderer(ISVGRenderer _renderer) external onlyOwner {
        renderer = _renderer;
        emit RendererUpdated(_renderer);
    }

    function setArtDescriptor(address descriptor) external onlyOwner {
        art.setDescriptor(descriptor);
    }

    function setArtInflator(IInflator inflator) external onlyOwner {
        art.setInflator(inflator);
    }

    function backgroundCount() public view override returns (uint256) {
        return art.backgroundCount();
    }

    function bodyCount() public view override returns (uint256) {
        return art.bodyCount();
    }

    function accessoryCount() public view override returns (uint256) {
        return art.accessoryCount();
    }

    function headCount() public view override returns (uint256) {
        return art.headCount();
    }

    function addManyBackgrounds(string[] calldata _backgrounds) external override onlyOwner whenPartsNotLocked {
        art.addManyBackgrounds(_backgrounds);
    }

    function addBackground(string calldata _background) external override onlyOwner whenPartsNotLocked {
        art.addBackground(_background);
    }

    function setPalette(uint8 paletteIndex, bytes calldata palette) external override onlyOwner whenPartsNotLocked {
        art.setPalette(paletteIndex, palette);
    }

    function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        art.addBodies(encodedCompressed, decompressedLength, imageCount);
    }

    function addAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        art.addAccessories(encodedCompressed, decompressedLength, imageCount);
    }

    function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        art.addHeads(encodedCompressed, decompressedLength, imageCount);
    }

    function setPalettePointer(uint8 paletteIndex, address pointer) external override onlyOwner whenPartsNotLocked {
        art.setPalettePointer(paletteIndex, pointer);
    }

    function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        art.addBodiesFromPointer(pointer, decompressedLength, imageCount);
    }

    function addAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        art.addAccessoriesFromPointer(pointer, decompressedLength, imageCount);
    }

    function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        art.addHeadsFromPointer(pointer, decompressedLength, imageCount);
    }

    function backgrounds(uint256 index) public view override returns (string memory) {
        return art.backgrounds(index);
    }

    function heads(uint256 index) public view override returns (bytes memory) {
        return art.heads(index);
    }

    function bodies(uint256 index) public view override returns (bytes memory) {
        return art.bodies(index);
    }

    function accessories(uint256 index) public view override returns (bytes memory) {
        return art.accessories(index);
    }

    function palettes(uint8 index) public view override returns (bytes memory) {
        return art.palettes(index);
    }

    function lockParts() external override onlyOwner whenPartsNotLocked {
        arePartsLocked = true;
        emit PartsLocked();
    }

    function toggleDataURIEnabled() external override onlyOwner {
        bool enabled = !isDataURIEnabled;
        isDataURIEnabled = enabled;
        emit DataURIToggled(enabled);
    }

    function setBaseURI(string calldata _baseURI) external override onlyOwner {
        baseURI = _baseURI;
        emit BaseURIUpdated(_baseURI);
    }

    function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view override returns (string memory) {
        if (isDataURIEnabled) {
            return dataURI(tokenId, seed);
        }
        return string(abi.encodePacked(baseURI, tokenId.toString()));
    }

    function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) public view override returns (string memory) {
        string memory shwounId = tokenId.toString();
        string memory name = string(abi.encodePacked('Shwoun ', shwounId));
        string memory description = string(abi.encodePacked('Shwoun ', shwounId, ' is a member of the Shwouns DAO'));
        return genericDataURI(name, description, seed);
    }

    function genericDataURI(
        string memory name,
        string memory description,
        IShwounsSeeder.Seed memory seed
    ) public view override returns (string memory) {
        NFTDescriptorV2.TokenURIParams memory params = NFTDescriptorV2.TokenURIParams({
            name: name,
            description: description,
            parts: getPartsForSeed(seed),
            background: art.backgrounds(seed.background)
        });
        return NFTDescriptorV2.constructTokenURI(renderer, params);
    }

    function generateSVGImage(IShwounsSeeder.Seed memory seed) external view override returns (string memory) {
        ISVGRenderer.SVGParams memory params = ISVGRenderer.SVGParams({
            parts: getPartsForSeed(seed),
            background: art.backgrounds(seed.background)
        });
        return NFTDescriptorV2.generateSVGImage(renderer, params);
    }

    /// @notice Get all Shwoun parts for the passed `seed`. Returns 3 parts (body, accessory, head) — no glasses.
    function getPartsForSeed(IShwounsSeeder.Seed memory seed) public view returns (ISVGRenderer.Part[] memory) {
        bytes memory body = art.bodies(seed.body);
        bytes memory accessory = art.accessories(seed.accessory);
        bytes memory head = art.heads(seed.head);

        ISVGRenderer.Part[] memory parts = new ISVGRenderer.Part[](3);
        parts[0] = ISVGRenderer.Part({ image: body, palette: _getPalette(body) });
        parts[1] = ISVGRenderer.Part({ image: accessory, palette: _getPalette(accessory) });
        parts[2] = ISVGRenderer.Part({ image: head, palette: _getPalette(head) });
        return parts;
    }

    function _getPalette(bytes memory part) private view returns (bytes memory) {
        return art.palettes(uint8(part[0]));
    }

    function updateAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        uint256 originalCount = accessoryCount();
        art.updateAccessories(encodedCompressed, decompressedLength, imageCount);
        require(originalCount == accessoryCount(), 'Image count must remain the same');
    }

    function updateBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        uint256 originalCount = bodyCount();
        art.updateBodies(encodedCompressed, decompressedLength, imageCount);
        require(originalCount == bodyCount(), 'Image count must remain the same');
    }

    function updateHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        uint256 originalCount = headCount();
        art.updateHeads(encodedCompressed, decompressedLength, imageCount);
        require(originalCount == headCount(), 'Image count must remain the same');
    }

    function updateAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        uint256 originalCount = accessoryCount();
        art.updateAccessoriesFromPointer(pointer, decompressedLength, imageCount);
        require(originalCount == accessoryCount(), 'Image count must remain the same');
    }

    function updateBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        uint256 originalCount = bodyCount();
        art.updateBodiesFromPointer(pointer, decompressedLength, imageCount);
        require(originalCount == bodyCount(), 'Image count must remain the same');
    }

    function updateHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external override onlyOwner whenPartsNotLocked {
        uint256 originalCount = headCount();
        art.updateHeadsFromPointer(pointer, decompressedLength, imageCount);
        require(originalCount == headCount(), 'Image count must remain the same');
    }
}
