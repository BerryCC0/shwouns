# ISVGRenderer
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/ISVGRenderer.sol)

**Title:**
Interface for SVGRenderer
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


## Functions
### generateSVG


```solidity
function generateSVG(SVGParams memory params) external view returns (string memory svg);
```

### generateSVGPart


```solidity
function generateSVGPart(Part memory part) external view returns (string memory partialSVG);
```

### generateSVGParts


```solidity
function generateSVGParts(Part[] memory parts) external view returns (string memory partialSVG);
```

## Structs
### Part

```solidity
struct Part {
    bytes image;
    bytes palette;
}
```

### SVGParams

```solidity
struct SVGParams {
    Part[] parts;
    string background;
}
```

