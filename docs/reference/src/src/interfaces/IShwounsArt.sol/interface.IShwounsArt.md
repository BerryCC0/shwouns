# IShwounsArt
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/IShwounsArt.sol)

**Title:**
Interface for ShwounsArt

Forked from INounsArt — glasses trait removed (no glasses, no glassesCount, no addGlasses,
no updateGlasses, no GlassesAdded/Updated events, no getGlassesTrait).


## Functions
### descriptor

The descriptor — the only address permitted to write art.


```solidity
function descriptor() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The descriptor address.|


### inflator

The DEFLATE inflator used to decompress stored image data.


```solidity
function inflator() external view returns (IInflator);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IInflator`|The inflator.|


### setDescriptor

Set the descriptor (the authorized writer). Descriptor only.


```solidity
function setDescriptor(address descriptor) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`descriptor`|`address`|The new descriptor address.|


### setInflator

Set the inflator. Descriptor only.


```solidity
function setInflator(IInflator inflator) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`inflator`|`IInflator`|The new inflator.|


### addManyBackgrounds

Add many background colors (hex strings). Descriptor only.


```solidity
function addManyBackgrounds(string[] calldata _backgrounds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_backgrounds`|`string[]`|The background hex strings to append.|


### addBackground

Add a single background color (hex string). Descriptor only.


```solidity
function addBackground(string calldata _background) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_background`|`string`|The background hex string to append.|


### palettes

The color palette at an index.


```solidity
function palettes(uint8 paletteIndex) external view returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The palette bytes (concatenated RGB triples).|


### setPalette

Set a palette inline. Descriptor only.


```solidity
function setPalette(uint8 paletteIndex, bytes calldata palette) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`palette`|`bytes`|The palette bytes (length a multiple of 3).|


### setPalettePointer

Set a palette by SSTORE2 pointer (cheaper for large palettes). Descriptor only.


```solidity
function setPalettePointer(uint8 paletteIndex, address pointer) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`pointer`|`address`|The SSTORE2 pointer holding the palette bytes.|


### addBodies

Add a compressed page of body images. Descriptor only.


```solidity
function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded image batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### addAccessories

Add a compressed page of accessory images. Descriptor only.


```solidity
function addAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded image batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### addHeads

Add a compressed page of head images. Descriptor only.


```solidity
function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded image batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### addBodiesFromPointer

Add a page of body images already stored at an SSTORE2 pointer. Descriptor only.


```solidity
function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### addAccessoriesFromPointer

Add a page of accessory images already stored at an SSTORE2 pointer. Descriptor only.


```solidity
function addAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### addHeadsFromPointer

Add a page of head images already stored at an SSTORE2 pointer. Descriptor only.


```solidity
function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### backgroundCount

The number of stored background traits.


```solidity
function backgroundCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The background count.|


### bodyCount

The number of stored body traits.


```solidity
function bodyCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The body count.|


### accessoryCount

The number of stored accessory traits.


```solidity
function accessoryCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The accessory count.|


### headCount

The number of stored head traits.


```solidity
function headCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The head count.|


### backgrounds

The background hex string at an index.


```solidity
function backgrounds(uint256 index) external view returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The background index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The background hex string.|


### heads

The (decompressed) RLE bytes of a head image.


```solidity
function heads(uint256 index) external view returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The head index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The head image bytes.|


### bodies

The (decompressed) RLE bytes of a body image.


```solidity
function bodies(uint256 index) external view returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The body index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The body image bytes.|


### accessories

The (decompressed) RLE bytes of an accessory image.


```solidity
function accessories(uint256 index) external view returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The accessory index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The accessory image bytes.|


### getBodiesTrait

The full body Trait (all storage pages + stored count).


```solidity
function getBodiesTrait() external view returns (Trait memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Trait`|The body Trait.|


### getAccessoriesTrait

The full accessory Trait (all storage pages + stored count).


```solidity
function getAccessoriesTrait() external view returns (Trait memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Trait`|The accessory Trait.|


### getHeadsTrait

The full head Trait (all storage pages + stored count).


```solidity
function getHeadsTrait() external view returns (Trait memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Trait`|The head Trait.|


### updateBodies

Replace ALL body images (the image count must stay the same). Descriptor only.


```solidity
function updateBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded replacement batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current body count).|


### updateAccessories

Replace ALL accessory images (the image count must stay the same). Descriptor only.


```solidity
function updateAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded replacement batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current accessory count).|


### updateHeads

Replace ALL head images (the image count must stay the same). Descriptor only.


```solidity
function updateHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded replacement batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current head count).|


### updateBodiesFromPointer

Replace ALL body images from an SSTORE2 pointer (count must match). Descriptor only.


```solidity
function updateBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current body count).|


### updateAccessoriesFromPointer

Replace ALL accessory images from an SSTORE2 pointer (count must match). Descriptor only.


```solidity
function updateAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current accessory count).|


### updateHeadsFromPointer

Replace ALL head images from an SSTORE2 pointer (count must match). Descriptor only.


```solidity
function updateHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current head count).|


## Events
### DescriptorUpdated
Emitted when the descriptor (the only authorized writer) changes.


```solidity
event DescriptorUpdated(address oldDescriptor, address newDescriptor);
```

### InflatorUpdated
Emitted when the inflator (DEFLATE decompressor) changes.


```solidity
event InflatorUpdated(address oldInflator, address newInflator);
```

### BackgroundsAdded
Emitted when background traits are added.


```solidity
event BackgroundsAdded(uint256 count);
```

### PaletteSet
Emitted when a palette is set.


```solidity
event PaletteSet(uint8 paletteIndex);
```

### BodiesAdded
Emitted when body traits are added.


```solidity
event BodiesAdded(uint16 count);
```

### AccessoriesAdded
Emitted when accessory traits are added.


```solidity
event AccessoriesAdded(uint16 count);
```

### HeadsAdded
Emitted when head traits are added.


```solidity
event HeadsAdded(uint16 count);
```

### BodiesUpdated
Emitted when body traits are replaced (same count).


```solidity
event BodiesUpdated(uint16 count);
```

### AccessoriesUpdated
Emitted when accessory traits are replaced (same count).


```solidity
event AccessoriesUpdated(uint16 count);
```

### HeadsUpdated
Emitted when head traits are replaced (same count).


```solidity
event HeadsUpdated(uint16 count);
```

## Errors
### SenderIsNotDescriptor
Thrown when a descriptor-only function is called by another address.


```solidity
error SenderIsNotDescriptor();
```

### EmptyPalette
Thrown when setting an empty palette.


```solidity
error EmptyPalette();
```

### BadPaletteLength
Thrown when a palette's byte length is not a multiple of 3 (RGB).


```solidity
error BadPaletteLength();
```

### EmptyBytes
Thrown when adding empty image bytes.


```solidity
error EmptyBytes();
```

### BadDecompressedLength
Thrown when the declared decompressed length is zero.


```solidity
error BadDecompressedLength();
```

### BadImageCount
Thrown when the declared image count is zero.


```solidity
error BadImageCount();
```

### ImageNotFound
Thrown when an image index is out of range.


```solidity
error ImageNotFound();
```

### PaletteNotFound
Thrown when a referenced palette index has no stored palette.


```solidity
error PaletteNotFound();
```

## Structs
### ShwounsArtStoragePage

```solidity
struct ShwounsArtStoragePage {
    uint16 imageCount;
    uint80 decompressedLength;
    address pointer;
}
```

### Trait

```solidity
struct Trait {
    ShwounsArtStoragePage[] storagePages;
    uint256 storedImagesCount;
}
```

