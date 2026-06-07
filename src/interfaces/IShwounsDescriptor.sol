// SPDX-License-Identifier: GPL-3.0

/// @title Interface for ShwounsDescriptor
/// @notice Forked from INounsDescriptorV3 — glasses trait removed.

pragma solidity ^0.8.6;

import { IShwounsSeeder } from './IShwounsSeeder.sol';
import { ISVGRenderer } from './ISVGRenderer.sol';
import { IShwounsArt } from './IShwounsArt.sol';
import { IShwounsDescriptorMinimal } from './IShwounsDescriptorMinimal.sol';

interface IShwounsDescriptor is IShwounsDescriptorMinimal {
    /// @notice Emitted when parts are permanently locked.
    event PartsLocked();
    /// @notice Emitted when on-chain data URI rendering is toggled on/off.
    event DataURIToggled(bool enabled);
    /// @notice Emitted when the fallback base URI changes.
    event BaseURIUpdated(string baseURI);
    /// @notice Emitted when the art contract reference changes.
    event ArtUpdated(IShwounsArt art);
    /// @notice Emitted when the SVG renderer changes.
    event RendererUpdated(ISVGRenderer renderer);

    /// @notice Thrown when a palette operation is given an empty palette.
    error EmptyPalette();
    /// @notice Thrown when a palette's byte length is not a multiple of 3 (RGB).
    error BadPaletteLength();
    /// @notice Thrown when a referenced index is out of range.
    error IndexNotFound();

    /// @notice Whether traits/palettes are permanently locked.
    /// @return True once `lockParts` has been called.
    function arePartsLocked() external returns (bool);

    /// @notice Whether tokenURI returns an on-chain data URI (vs the base URI form).
    /// @return True if on-chain data URIs are enabled.
    function isDataURIEnabled() external returns (bool);

    /// @notice The fallback base URI used when data URIs are disabled.
    /// @return The base URI string.
    function baseURI() external returns (string memory);

    /// @notice The color palette at an index.
    /// @param paletteIndex The palette index.
    /// @return The palette bytes (concatenated RGB triples).
    function palettes(uint8 paletteIndex) external view returns (bytes memory);

    /// @notice The background hex string at an index.
    /// @param index The background index.
    /// @return The background hex string.
    function backgrounds(uint256 index) external view returns (string memory);

    /// @notice The (decompressed) RLE bytes of a body image.
    /// @param index The body index.
    /// @return The body image bytes.
    function bodies(uint256 index) external view returns (bytes memory);

    /// @notice The (decompressed) RLE bytes of an accessory image.
    /// @param index The accessory index.
    /// @return The accessory image bytes.
    function accessories(uint256 index) external view returns (bytes memory);

    /// @notice The (decompressed) RLE bytes of a head image.
    /// @param index The head index.
    /// @return The head image bytes.
    function heads(uint256 index) external view returns (bytes memory);

    /// @inheritdoc IShwounsDescriptorMinimal
    function backgroundCount() external view override returns (uint256);
    /// @inheritdoc IShwounsDescriptorMinimal
    function bodyCount() external view override returns (uint256);
    /// @inheritdoc IShwounsDescriptorMinimal
    function accessoryCount() external view override returns (uint256);
    /// @inheritdoc IShwounsDescriptorMinimal
    function headCount() external view override returns (uint256);

    /// @notice Add many background colors. Owner only, until parts are locked.
    /// @param backgrounds The background hex strings to append.
    function addManyBackgrounds(string[] calldata backgrounds) external;

    /// @notice Add a single background color. Owner only, until parts are locked.
    /// @param background The background hex string to append.
    function addBackground(string calldata background) external;

    /// @notice Set a palette inline. Owner only, until parts are locked.
    /// @param paletteIndex The palette index.
    /// @param palette The palette bytes (length a multiple of 3).
    function setPalette(uint8 paletteIndex, bytes calldata palette) external;

    /// @notice Set a palette by SSTORE2 pointer. Owner only, until parts are locked.
    /// @param paletteIndex The palette index.
    /// @param pointer The SSTORE2 pointer holding the palette bytes.
    function setPalettePointer(uint8 paletteIndex, address pointer) external;

    /// @notice Add a compressed page of body images. Owner only, until parts are locked.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded image batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a compressed page of accessory images. Owner only, until parts are locked.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded image batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a compressed page of head images. Owner only, until parts are locked.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded image batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a page of body images from an SSTORE2 pointer. Owner only, until parts are locked.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a page of accessory images from an SSTORE2 pointer. Owner only, until locked.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a page of head images from an SSTORE2 pointer. Owner only, until parts are locked.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Permanently lock all traits/palettes. Owner only. Irreversible.
    function lockParts() external;

    /// @notice Toggle on-chain data URI rendering on/off. Owner only.
    function toggleDataURIEnabled() external;

    /// @notice Set the fallback base URI (used when data URIs are disabled). Owner only.
    /// @param baseURI The new base URI.
    function setBaseURI(string calldata baseURI) external;

    /// @inheritdoc IShwounsDescriptorMinimal
    function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view override returns (string memory);
    /// @inheritdoc IShwounsDescriptorMinimal
    function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view override returns (string memory);

    /// @notice A data URI for arbitrary name/description with a given seed's art.
    /// @param name The NFT name field.
    /// @param description The NFT description field.
    /// @param seed The trait seed to render.
    /// @return The base64-encoded data URI.
    function genericDataURI(string calldata name, string calldata description, IShwounsSeeder.Seed memory seed) external view returns (string memory);

    /// @notice The raw SVG image (base64) for a given seed.
    /// @param seed The trait seed to render.
    /// @return The base64-encoded SVG.
    function generateSVGImage(IShwounsSeeder.Seed memory seed) external view returns (string memory);

    /// @notice Replace ALL body images (count must stay the same). Owner only, until parts are locked.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded replacement batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current body count).
    function updateBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL accessory images (count must stay the same). Owner only, until locked.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded replacement batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current accessory count).
    function updateAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL head images (count must stay the same). Owner only, until parts are locked.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded replacement batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current head count).
    function updateHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL body images from an SSTORE2 pointer (count must match). Owner only, until locked.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current body count).
    function updateBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL accessory images from an SSTORE2 pointer (count must match). Owner only, until locked.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current accessory count).
    function updateAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL head images from an SSTORE2 pointer (count must match). Owner only, until locked.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current head count).
    function updateHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
}
