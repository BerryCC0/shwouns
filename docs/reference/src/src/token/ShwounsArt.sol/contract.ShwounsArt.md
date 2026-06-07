# ShwounsArt
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/ShwounsArt.sol)

**Inherits:**
[IShwounsArt](/src/interfaces/IShwounsArt.sol/interface.IShwounsArt.md)

**Title:**
The Shwouns art storage contract

Forked from NounsArt (nouns-monorepo @ main). Changes:
- Removed all glasses trait support (glassesTrait storage, addGlasses /
addGlassesFromPointer / updateGlasses / updateGlassesFromPointer,
getGlassesTrait, glasses(index), glassesCount, GlassesAdded / GlassesUpdated events).
- Interface swapped: INounsArt → IShwounsArt.
- Identical SSTORE2 storage layout for the remaining four trait types
(backgrounds, bodies, accessories, heads).
Original Copyright Nouns DAO, GPL-3.0. Modified for Shwouns.


## State Variables
### descriptor
Current Shwouns Descriptor address


```solidity
address public override descriptor
```


### inflator
Current inflator address


```solidity
IInflator public override inflator
```


### backgrounds
Shwouns Backgrounds (Hex Colors)


```solidity
string[] public override backgrounds
```


### palettesPointers
Shwouns Color Palettes (Index => Hex Colors, stored as a contract using SSTORE2)


```solidity
mapping(uint8 => address) public palettesPointers
```


### bodiesTrait
Shwouns Bodies Trait


```solidity
Trait public bodiesTrait
```


### accessoriesTrait
Shwouns Accessories Trait


```solidity
Trait public accessoriesTrait
```


### headsTrait
Shwouns Heads Trait


```solidity
Trait public headsTrait
```


## Functions
### onlyDescriptor

Require that the sender is the descriptor.


```solidity
modifier onlyDescriptor() ;
```

### constructor


```solidity
constructor(address _descriptor, IInflator _inflator) ;
```

### setDescriptor

Set the descriptor (the authorized writer). Descriptor only.


```solidity
function setDescriptor(address _descriptor) external override onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_descriptor`|`address`||


### setInflator

Set the inflator. Descriptor only.


```solidity
function setInflator(IInflator _inflator) external override onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_inflator`|`IInflator`||


### getBodiesTrait

The full body Trait (all storage pages + stored count).


```solidity
function getBodiesTrait() external view override returns (Trait memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Trait`|The body Trait.|


### getAccessoriesTrait

The full accessory Trait (all storage pages + stored count).


```solidity
function getAccessoriesTrait() external view override returns (Trait memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Trait`|The accessory Trait.|


### getHeadsTrait

The full head Trait (all storage pages + stored count).


```solidity
function getHeadsTrait() external view override returns (Trait memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Trait`|The head Trait.|


### addManyBackgrounds

Add many background colors (hex strings). Descriptor only.


```solidity
function addManyBackgrounds(string[] calldata _backgrounds) external override onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_backgrounds`|`string[]`|The background hex strings to append.|


### addBackground

Add a single background color (hex string). Descriptor only.


```solidity
function addBackground(string calldata _background) external override onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_background`|`string`|The background hex string to append.|


### _addBackground


```solidity
function _addBackground(string calldata _background) internal;
```

### setPalette

Set a palette inline. Descriptor only.


```solidity
function setPalette(uint8 paletteIndex, bytes calldata palette) external override onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`palette`|`bytes`|The palette bytes (length a multiple of 3).|


### setPalettePointer

Set a palette by SSTORE2 pointer (cheaper for large palettes). Descriptor only.


```solidity
function setPalettePointer(uint8 paletteIndex, address pointer) external override onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|
|`pointer`|`address`|The SSTORE2 pointer holding the palette bytes.|


### palettes

The color palette at an index.


```solidity
function palettes(uint8 paletteIndex) public view override returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paletteIndex`|`uint8`|The palette index.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The palette bytes (concatenated RGB triples).|


### addBodies

Add a compressed page of body images. Descriptor only.


```solidity
function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function addAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function addAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images in the page.|


### updateBodies

Replace ALL body images (the image count must stay the same). Descriptor only.


```solidity
function updateBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function updateAccessories(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function updateHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function updateBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function updateAccessoriesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
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
function updateHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
    external
    override
    onlyDescriptor;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`pointer`|`address`|The SSTORE2 pointer holding the compressed batch.|
|`decompressedLength`|`uint80`|The byte length after decompression.|
|`imageCount`|`uint16`|The number of images (must equal the current head count).|


### backgroundCount

The number of stored background traits.


```solidity
function backgroundCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The background count.|


### bodyCount

The number of stored body traits.


```solidity
function bodyCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The body count.|


### accessoryCount

The number of stored accessory traits.


```solidity
function accessoryCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The accessory count.|


### headCount

The number of stored head traits.


```solidity
function headCount() external view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The head count.|


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


### replaceTraitData


```solidity
function replaceTraitData(
    Trait storage trait,
    bytes calldata encodedCompressed,
    uint80 decompressedLength,
    uint16 imageCount
) internal;
```

### replaceTraitData


```solidity
function replaceTraitData(Trait storage trait, address pointer, uint80 decompressedLength, uint16 imageCount)
    internal;
```

### addPage


```solidity
function addPage(
    Trait storage trait,
    bytes calldata encodedCompressed,
    uint80 decompressedLength,
    uint16 imageCount
) internal;
```

### addPage


```solidity
function addPage(Trait storage trait, address pointer, uint80 decompressedLength, uint16 imageCount) internal;
```

### imageByIndex


```solidity
function imageByIndex(IShwounsArt.Trait storage trait, uint256 index) internal view returns (bytes memory);
```

### getPage

Given an image index, find the page it lives in and its index within that page.


```solidity
function getPage(IShwounsArt.ShwounsArtStoragePage[] storage pages, uint256 index)
    internal
    view
    returns (IShwounsArt.ShwounsArtStoragePage storage, uint256);
```

### decompressAndDecode


```solidity
function decompressAndDecode(IShwounsArt.ShwounsArtStoragePage storage page)
    internal
    view
    returns (bytes[] memory);
```

