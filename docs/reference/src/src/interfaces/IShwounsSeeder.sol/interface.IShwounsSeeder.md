# IShwounsSeeder
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/IShwounsSeeder.sol)

**Title:**
Interface for ShwounsSeeder

Forked from NounsSeeder — `glasses` field removed.


## Functions
### generateSeed

Deterministically derive a 4-trait seed for a token from the prior blockhash.


```solidity
function generateSeed(uint256 nounId, IShwounsDescriptorMinimal descriptor) external view returns (Seed memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nounId`|`uint256`|The token id to generate a seed for.|
|`descriptor`|`IShwounsDescriptorMinimal`|The descriptor providing each trait's count (the modulus per trait).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Seed`|The generated seed (background, body, accessory, head).|


## Structs
### Seed

```solidity
struct Seed {
    uint48 background;
    uint48 body;
    uint48 accessory;
    uint48 head;
}
```

