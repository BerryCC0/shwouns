# IShwounsDescriptor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/IShwounsDescriptor.sol)

**Inherits:**
[IShwounsDescriptorMinimal](/src/interfaces/IShwounsDescriptorMinimal.sol/interface.IShwounsDescriptorMinimal.md)

**Title:**
Interface for ShwounsDescriptor

Forked from INounsDescriptorV3 — glasses trait removed.


## Functions
### arePartsLocked

Whether traits/palettes are permanently locked.


```solidity
function arePartsLocked() external returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True once `lockParts` has been called.|


### isDataURIEnabled

Whether tokenURI returns an on-chain data URI (vs the base URI form).


```solidity
function isDataURIEnabled() external returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if on-chain data URIs are enabled.|


### baseURI

The fallback base URI used when data URIs are disabled.


```solidity
function baseURI() external returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The base URI string.|


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


### backgroundCount

The number of available background traits.


```solidity
function backgroundCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The background count.|


### bodyCount

The number of available body traits.


```solidity
function bodyCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The body count.|


### accessoryCount

The number of available accessory traits.


```solidity
function accessoryCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The accessory count.|


### headCount

The number of available head traits.


```solidity
function headCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The head count.|


### addManyBackgrounds

Add many background colors. Owner only, until parts are locked.


```solidity
function addManyBackgrounds(string[] calldata backgrounds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`backgrounds`|`string[]`|The background hex strings to append.|


### addBackground

Add a single background color. Owner only, until parts are locked.


```solidity
function addBackground(string calldata background) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`background`|`string`|The background hex string to append.|


### setPalette

Set a palette inline. Owner only, until parts are locked.


```solidity
function setPalette(uint8 paletteIndex, bytes calldata palette) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`palette`|`bytes`|The palette bytes (length a multiple of 3).|


### setPalettePointer

Set a palette by SSTORE2 pointer. Owner only, until parts are locked.


```solidity
function setPalettePointer(uint8 paletteIndex, address pointer) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`pointer`|`address`|The SSTORE2 pointer holding the palette bytes.|


### addBodies

Add a compressed page of body images. Owner only, until parts are locked.


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

Add a compressed page of accessory images. Owner only, until parts are locked.


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

Add a compressed page of head images. Owner only, until parts are locked.


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

Add a page of body images from an SSTORE2 pointer. Owner only, until parts are locked.


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

Add a page of accessory images from an SSTORE2 pointer. Owner only, until locked.


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

Add a page of head images from an SSTORE2 pointer. Owner only, until parts are locked.


```solidity
function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### lockParts

Permanently lock all traits/palettes. Owner only. Irreversible.


```solidity
function lockParts() external;
```

### toggleDataURIEnabled

Toggle on-chain data URI rendering on/off. Owner only.


```solidity
function toggleDataURIEnabled() external;
```

### setBaseURI

Set the fallback base URI (used when data URIs are disabled). Owner only.


```solidity
function setBaseURI(string calldata baseURI) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`baseURI`|`string`|The new base URI.|


### tokenURI

The token URI for a Shwoun given its seed (data URI or baseURI form).


```solidity
function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id.|
|`seed`|`IShwounsSeeder.Seed`|The Shwoun's trait seed.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token URI string.|


### dataURI

The on-chain data URI (base64 JSON) for a Shwoun given its seed.


```solidity
function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id.|
|`seed`|`IShwounsSeeder.Seed`|The Shwoun's trait seed.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The data URI string.|


### genericDataURI

A data URI for arbitrary name/description with a given seed's art.


```solidity
function genericDataURI(string calldata name, string calldata description, IShwounsSeeder.Seed memory seed)
    external
    view
    returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|The NFT name field.|
|`description`|`string`|The NFT description field.|
|`seed`|`IShwounsSeeder.Seed`|The trait seed to render.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The base64-encoded data URI.|


### generateSVGImage

The raw SVG image (base64) for a given seed.


```solidity
function generateSVGImage(IShwounsSeeder.Seed memory seed) external view returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`seed`|`IShwounsSeeder.Seed`|The trait seed to render.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The base64-encoded SVG.|


### updateBodies

Replace ALL body images (count must stay the same). Owner only, until parts are locked.


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

Replace ALL accessory images (count must stay the same). Owner only, until locked.


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

Replace ALL head images (count must stay the same). Owner only, until parts are locked.


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

Replace ALL body images from an SSTORE2 pointer (count must match). Owner only, until locked.


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

Replace ALL accessory images from an SSTORE2 pointer (count must match). Owner only, until locked.


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

Replace ALL head images from an SSTORE2 pointer (count must match). Owner only, until locked.


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
### PartsLocked
Emitted when parts are permanently locked.


```solidity
event PartsLocked();
```

### DataURIToggled
Emitted when on-chain data URI rendering is toggled on/off.


```solidity
event DataURIToggled(bool enabled);
```

### BaseURIUpdated
Emitted when the fallback base URI changes.


```solidity
event BaseURIUpdated(string baseURI);
```

### ArtUpdated
Emitted when the art contract reference changes.


```solidity
event ArtUpdated(IShwounsArt art);
```

### RendererUpdated
Emitted when the SVG renderer changes.


```solidity
event RendererUpdated(ISVGRenderer renderer);
```

## Errors
### EmptyPalette
Thrown when a palette operation is given an empty palette.


```solidity
error EmptyPalette();
```

### BadPaletteLength
Thrown when a palette's byte length is not a multiple of 3 (RGB).


```solidity
error BadPaletteLength();
```

### IndexNotFound
Thrown when a referenced index is out of range.


```solidity
error IndexNotFound();
```

