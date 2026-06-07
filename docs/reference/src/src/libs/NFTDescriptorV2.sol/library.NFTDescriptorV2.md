# NFTDescriptorV2
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/libs/NFTDescriptorV2.sol)

**Title:**
A library used to construct ERC721 token URIs and SVG images
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
### constructTokenURI

Construct an ERC721 token URI.


```solidity
function constructTokenURI(ISVGRenderer renderer, TokenURIParams memory params)
    public
    view
    returns (string memory);
```

### generateSVGImage

Generate an SVG image for use in the ERC721 token URI.


```solidity
function generateSVGImage(ISVGRenderer renderer, ISVGRenderer.SVGParams memory params)
    public
    view
    returns (string memory svg);
```

## Structs
### TokenURIParams

```solidity
struct TokenURIParams {
    string name;
    string description;
    string background;
    ISVGRenderer.Part[] parts;
}
```

