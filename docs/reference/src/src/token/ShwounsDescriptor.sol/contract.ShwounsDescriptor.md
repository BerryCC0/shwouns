# ShwounsDescriptor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/ShwounsDescriptor.sol)

**Inherits:**
[IShwounsDescriptor](/src/interfaces/IShwounsDescriptor.sol/interface.IShwounsDescriptor.md), [GovernedOwnable](/src/governance/GovernedOwnable.sol/abstract.GovernedOwnable.md)

**Title:**
The Shwouns NFT descriptor

Forked from NounsDescriptorV3 (nouns-monorepo @ main). Glasses trait removed:
- No `glasses(uint256)` / `glassesCount` views
- No `addGlasses` / `addGlassesFromPointer` / `updateGlasses` / `updateGlassesFromPointer`
- `getPartsForSeed` returns 4 parts (background, body, accessory, head) instead of 5


## Constants
### COPYRIGHT_CC0_1_0_UNIVERSAL_LICENSE

```solidity
bytes32 constant COPYRIGHT_CC0_1_0_UNIVERSAL_LICENSE =
    0xa2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499
```


## State Variables
### art
The art storage contract this descriptor reads trait images/palettes from.


```solidity
IShwounsArt public art
```


### renderer
The SVG renderer used to compose trait images into an SVG.


```solidity
ISVGRenderer public renderer
```


### arePartsLocked
Whether traits/palettes are permanently locked.


```solidity
bool public override arePartsLocked
```


### isDataURIEnabled
Whether tokenURI returns an on-chain data URI (vs the base URI form).


```solidity
bool public override isDataURIEnabled = true
```


### baseURI
The fallback base URI used when data URIs are disabled.


```solidity
string public override baseURI
```


## Functions
### whenPartsNotLocked


```solidity
modifier whenPartsNotLocked() ;
```

### constructor


```solidity
constructor(IShwounsArt _art, ISVGRenderer _renderer, address _governanceAuth) GovernedOwnable(_governanceAuth);
```

### setArt

Point the descriptor at a new art contract. Owner only, until parts are locked.


```solidity
function setArt(IShwounsArt _art) external onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_art`|`IShwounsArt`|The new art storage contract.|


### setRenderer

Set the SVG renderer. Owner only.


```solidity
function setRenderer(ISVGRenderer _renderer) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_renderer`|`ISVGRenderer`|The new SVG renderer.|


### setArtDescriptor

Re-point the art contract's `descriptor` (its sole authorized writer). Owner only,
until parts are locked.

M-06: gated by whenPartsNotLocked. Without it, after lockParts() the owner could hand
Art authority to a fresh unlocked descriptor and mutate palettes/traits — bypassing the
lock. Authority-changing Art ops must respect the parts lock.


```solidity
function setArtDescriptor(address descriptor) external onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`descriptor`|`address`|The new descriptor address for the art contract.|


### setArtInflator

Set the art contract's inflator. Owner only, until parts are locked.


```solidity
function setArtInflator(IInflator inflator) external onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`inflator`|`IInflator`|The new inflator for the art contract.|


### backgroundCount


```solidity
function backgroundCount() public view override returns (uint256);
```

### bodyCount


```solidity
function bodyCount() public view override returns (uint256);
```

### accessoryCount


```solidity
function accessoryCount() public view override returns (uint256);
```

### headCount


```solidity
function headCount() public view override returns (uint256);
```

### addManyBackgrounds

Add many background colors. Owner only, until parts are locked.


```solidity
function addManyBackgrounds(string[] calldata _backgrounds) external override onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_backgrounds`|`string[]`||


### addBackground

Add a single background color. Owner only, until parts are locked.


```solidity
function addBackground(string calldata _background) external override onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_background`|`string`||


### setPalette

Set a palette inline. Owner only, until parts are locked.


```solidity
function setPalette(uint8 paletteIndex, bytes calldata palette) external override onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`palette`|`bytes`|The palette bytes (length a multiple of 3).|


### addBodies

Add a compressed page of body images. Owner only, until parts are locked.


```solidity
function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
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
function addAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
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
function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded image batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### setPalettePointer

Set a palette by SSTORE2 pointer. Owner only, until parts are locked.


```solidity
function setPalettePointer(uint8 paletteIndex, address pointer) external override onlyOwner whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`pointer`|`address`|The SSTORE2 pointer holding the palette bytes.|


### addBodiesFromPointer

Add a page of body images from an SSTORE2 pointer. Owner only, until parts are locked.


```solidity
function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
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
function addAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
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
function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### backgrounds

The background hex string at an index.


```solidity
function backgrounds(uint256 index) public view override returns (string memory);
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
function heads(uint256 index) public view override returns (bytes memory);
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
function bodies(uint256 index) public view override returns (bytes memory);
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
function accessories(uint256 index) public view override returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The accessory index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The accessory image bytes.|


### palettes

The color palette at an index.


```solidity
function palettes(uint8 index) public view override returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint8`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The palette bytes (concatenated RGB triples).|


### lockParts

Permanently lock all traits/palettes. Owner only. Irreversible.


```solidity
function lockParts() external override onlyOwner whenPartsNotLocked;
```

### toggleDataURIEnabled

Toggle on-chain data URI rendering on/off. Owner only.


```solidity
function toggleDataURIEnabled() external override onlyOwner;
```

### setBaseURI

Set the fallback base URI (used when data URIs are disabled). Owner only.


```solidity
function setBaseURI(string calldata _baseURI) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_baseURI`|`string`||


### tokenURI


```solidity
function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view override returns (string memory);
```

### dataURI


```solidity
function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) public view override returns (string memory);
```

### genericDataURI

A data URI for arbitrary name/description with a given seed's art.


```solidity
function genericDataURI(string memory name, string memory description, IShwounsSeeder.Seed memory seed)
    public
    view
    override
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
function generateSVGImage(IShwounsSeeder.Seed memory seed) external view override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`seed`|`IShwounsSeeder.Seed`|The trait seed to render.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The base64-encoded SVG.|


### getPartsForSeed

Get all Shwoun parts for the passed `seed`. Returns 3 parts (body, accessory, head) — no glasses.


```solidity
function getPartsForSeed(IShwounsSeeder.Seed memory seed) public view returns (ISVGRenderer.Part[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`seed`|`IShwounsSeeder.Seed`|The trait seed to resolve into images + palettes.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ISVGRenderer.Part[]`|The renderer parts (body, accessory, head), each with its image bytes and palette.|


### _getPalette


```solidity
function _getPalette(bytes memory part) private view returns (bytes memory);
```

### updateAccessories

Replace ALL accessory images (count must stay the same). Owner only, until locked.


```solidity
function updateAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded replacement batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current accessory count).|


### updateBodies

Replace ALL body images (count must stay the same). Owner only, until parts are locked.


```solidity
function updateBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded replacement batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current body count).|


### updateHeads

Replace ALL head images (count must stay the same). Owner only, until parts are locked.


```solidity
function updateHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`encodedCompressed`|`bytes`|The DEFLATE-compressed, RLE-encoded replacement batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current head count).|


### updateAccessoriesFromPointer

Replace ALL accessory images from an SSTORE2 pointer (count must match). Owner only, until locked.


```solidity
function updateAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current accessory count).|


### updateBodiesFromPointer

Replace ALL body images from an SSTORE2 pointer (count must match). Owner only, until locked.


```solidity
function updateBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current body count).|


### updateHeadsFromPointer

Replace ALL head images from an SSTORE2 pointer (count must match). Owner only, until locked.


```solidity
function updateHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyOwner
    whenPartsNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current head count).|


