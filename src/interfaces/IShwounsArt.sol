// SPDX-License-Identifier: GPL-3.0

/// @title Interface for ShwounsArt
/// @notice Forked from INounsArt — glasses trait removed (no glasses, no glassesCount, no addGlasses,
///   no updateGlasses, no GlassesAdded/Updated events, no getGlassesTrait).

pragma solidity ^0.8.6;

import { IInflator } from './IInflator.sol';

interface IShwounsArt {
    /// @notice Thrown when a descriptor-only function is called by another address.
    error SenderIsNotDescriptor();
    /// @notice Thrown when setting an empty palette.
    error EmptyPalette();
    /// @notice Thrown when a palette's byte length is not a multiple of 3 (RGB).
    error BadPaletteLength();
    /// @notice Thrown when adding empty image bytes.
    error EmptyBytes();
    /// @notice Thrown when the declared decompressed length is zero.
    error BadDecompressedLength();
    /// @notice Thrown when the declared image count is zero.
    error BadImageCount();
    /// @notice Thrown when an image index is out of range.
    error ImageNotFound();
    /// @notice Thrown when a referenced palette index has no stored palette.
    error PaletteNotFound();

    /// @notice Emitted when the descriptor (the only authorized writer) changes.
    event DescriptorUpdated(address oldDescriptor, address newDescriptor);
    /// @notice Emitted when the inflator (DEFLATE decompressor) changes.
    event InflatorUpdated(address oldInflator, address newInflator);
    /// @notice Emitted when background traits are added.
    event BackgroundsAdded(uint256 count);
    /// @notice Emitted when a palette is set.
    event PaletteSet(uint8 paletteIndex);
    /// @notice Emitted when body traits are added.
    event BodiesAdded(uint16 count);
    /// @notice Emitted when accessory traits are added.
    event AccessoriesAdded(uint16 count);
    /// @notice Emitted when head traits are added.
    event HeadsAdded(uint16 count);
    /// @notice Emitted when body traits are replaced (same count).
    event BodiesUpdated(uint16 count);
    /// @notice Emitted when accessory traits are replaced (same count).
    event AccessoriesUpdated(uint16 count);
    /// @notice Emitted when head traits are replaced (same count).
    event HeadsUpdated(uint16 count);

    struct ShwounsArtStoragePage {
        uint16 imageCount;
        uint80 decompressedLength;
        address pointer;
    }

    struct Trait {
        ShwounsArtStoragePage[] storagePages;
        uint256 storedImagesCount;
    }

    /// @notice The descriptor — the only address permitted to write art.
    /// @return The descriptor address.
    function descriptor() external view returns (address);

    /// @notice The DEFLATE inflator used to decompress stored image data.
    /// @return The inflator.
    function inflator() external view returns (IInflator);

    /// @notice Set the descriptor (the authorized writer). Descriptor only.
    /// @param descriptor The new descriptor address.
    function setDescriptor(address descriptor) external;

    /// @notice Set the inflator. Descriptor only.
    /// @param inflator The new inflator.
    function setInflator(IInflator inflator) external;

    /// @notice Add many background colors (hex strings). Descriptor only.
    /// @param _backgrounds The background hex strings to append.
    function addManyBackgrounds(string[] calldata _backgrounds) external;

    /// @notice Add a single background color (hex string). Descriptor only.
    /// @param _background The background hex string to append.
    function addBackground(string calldata _background) external;

    /// @notice The color palette at an index.
    /// @param paletteIndex The palette index.
    /// @return The palette bytes (concatenated RGB triples).
    function palettes(uint8 paletteIndex) external view returns (bytes memory);

    /// @notice Set a palette inline. Descriptor only.
    /// @param paletteIndex The palette index.
    /// @param palette The palette bytes (length a multiple of 3).
    function setPalette(uint8 paletteIndex, bytes calldata palette) external;

    /// @notice Set a palette by SSTORE2 pointer (cheaper for large palettes). Descriptor only.
    /// @param paletteIndex The palette index.
    /// @param pointer The SSTORE2 pointer holding the palette bytes.
    function setPalettePointer(uint8 paletteIndex, address pointer) external;

    /// @notice Add a compressed page of body images. Descriptor only.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded image batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a compressed page of accessory images. Descriptor only.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded image batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a compressed page of head images. Descriptor only.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded image batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a page of body images already stored at an SSTORE2 pointer. Descriptor only.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a page of accessory images already stored at an SSTORE2 pointer. Descriptor only.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Add a page of head images already stored at an SSTORE2 pointer. Descriptor only.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images in the page.
    function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice The number of stored background traits.
    /// @return The background count.
    function backgroundCount() external view returns (uint256);

    /// @notice The number of stored body traits.
    /// @return The body count.
    function bodyCount() external view returns (uint256);

    /// @notice The number of stored accessory traits.
    /// @return The accessory count.
    function accessoryCount() external view returns (uint256);

    /// @notice The number of stored head traits.
    /// @return The head count.
    function headCount() external view returns (uint256);

    /// @notice The background hex string at an index.
    /// @param index The background index.
    /// @return The background hex string.
    function backgrounds(uint256 index) external view returns (string memory);

    /// @notice The (decompressed) RLE bytes of a head image.
    /// @param index The head index.
    /// @return The head image bytes.
    function heads(uint256 index) external view returns (bytes memory);

    /// @notice The (decompressed) RLE bytes of a body image.
    /// @param index The body index.
    /// @return The body image bytes.
    function bodies(uint256 index) external view returns (bytes memory);

    /// @notice The (decompressed) RLE bytes of an accessory image.
    /// @param index The accessory index.
    /// @return The accessory image bytes.
    function accessories(uint256 index) external view returns (bytes memory);

    /// @notice The full body Trait (all storage pages + stored count).
    /// @return The body Trait.
    function getBodiesTrait() external view returns (Trait memory);

    /// @notice The full accessory Trait (all storage pages + stored count).
    /// @return The accessory Trait.
    function getAccessoriesTrait() external view returns (Trait memory);

    /// @notice The full head Trait (all storage pages + stored count).
    /// @return The head Trait.
    function getHeadsTrait() external view returns (Trait memory);

    /// @notice Replace ALL body images (the image count must stay the same). Descriptor only.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded replacement batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current body count).
    function updateBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL accessory images (the image count must stay the same). Descriptor only.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded replacement batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current accessory count).
    function updateAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL head images (the image count must stay the same). Descriptor only.
    /// @param encodedCompressed The DEFLATE-compressed, RLE-encoded replacement batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current head count).
    function updateHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL body images from an SSTORE2 pointer (count must match). Descriptor only.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current body count).
    function updateBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL accessory images from an SSTORE2 pointer (count must match). Descriptor only.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current accessory count).
    function updateAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;

    /// @notice Replace ALL head images from an SSTORE2 pointer (count must match). Descriptor only.
    /// @param pointer The SSTORE2 pointer holding the compressed batch.
    /// @param decompressedLength The byte length after decompression.
    /// @param imageCount The number of images (must equal the current head count).
    function updateHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
}
