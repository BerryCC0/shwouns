# SVGRenderer
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/SVGRenderer.sol)

**Inherits:**
[ISVGRenderer](/src/interfaces/ISVGRenderer.sol/interface.ISVGRenderer.md)

**Title:**
A contract used to convert multi-part RLE compressed images to SVG
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
░░░░░░█████████░░█████████░░░ *
░░░░░░██░░░████░░██░░░████░░░ *
░░██████░░░████████░░░████░░░ *
░░██░░██░░░████░░██░░░████░░░ *
░░██░░██░░░████░░██░░░████░░░ *
░░░░░░█████████░░█████████░░░ *
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *


## Constants
### _HEX_SYMBOLS

```solidity
bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef"
```


### _INDEX_TO_BYTES3_FACTOR

```solidity
uint256 private constant _INDEX_TO_BYTES3_FACTOR = 3
```


### _SVG_START_TAG

```solidity
string private constant _SVG_START_TAG =
    '<svg width="320" height="320" viewBox="0 0 320 320" xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges">'
```


### _SVG_END_TAG

```solidity
string private constant _SVG_END_TAG = "</svg>"
```


## Functions
### generateSVG

Given RLE image data and color palette pointers, merge to generate a single SVG image.


```solidity
function generateSVG(SVGParams calldata params) external pure override returns (string memory svg);
```

### generateSVGPart

Given RLE image data and a color palette pointer, merge to generate a partial SVG image.


```solidity
function generateSVGPart(Part calldata part) external pure override returns (string memory partialSVG);
```

### generateSVGParts

Given RLE image data and color palette pointers, merge to generate a partial SVG image.


```solidity
function generateSVGParts(Part[] calldata parts) external pure override returns (string memory partialSVG);
```

### _generateSVGRects

Given RLE image parts and color palettes, generate SVG rects.


```solidity
function _generateSVGRects(SVGParams memory params) private pure returns (string memory svg);
```

### _getRectLength

Given an x-coordinate, draw length, and right bound, return the draw
length for a single SVG rectangle.


```solidity
function _getRectLength(uint256 currentX, uint8 drawLength, uint8 rightBound) private pure returns (uint8);
```

### _getChunk

Return a string that consists of all rects in the provided `buffer`.


```solidity
function _getChunk(uint256 cursor, string[16] memory buffer) private pure returns (string memory);
```

### _decodeRLEImage

Decode a single RLE compressed image into a `DecodedImage`.


```solidity
function _decodeRLEImage(bytes memory image) private pure returns (DecodedImage memory);
```

### _getColor

Get the target hex color code from the cache. Populate the cache if
the color code does not yet exist.


```solidity
function _getColor(bytes memory palette, uint256 index, string[] memory cache)
    private
    pure
    returns (string memory);
```

### _toHexString

Convert `bytes` to a 6 character ASCII `string` hexadecimal representation.


```solidity
function _toHexString(bytes memory b) private pure returns (string memory);
```

## Structs
### ContentBounds

```solidity
struct ContentBounds {
    uint8 top;
    uint8 right;
    uint8 bottom;
    uint8 left;
}
```

### Draw

```solidity
struct Draw {
    uint8 length;
    uint8 colorIndex;
}
```

### DecodedImage

```solidity
struct DecodedImage {
    ContentBounds bounds;
    Draw[] draws;
}
```

