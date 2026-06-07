# ShwounsSeeder
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/ShwounsSeeder.sol)

**Inherits:**
[IShwounsSeeder](/src/interfaces/IShwounsSeeder.sol/interface.IShwounsSeeder.md)

**Title:**
The ShwounsToken pseudo-random seed generator

Forked from NounsSeeder (nouns-monorepo @ main). Glasses trait removed.


## Functions
### generateSeed

Deterministically derive a 4-trait seed for a token from the prior blockhash.


```solidity
function generateSeed(uint256 nounId, IShwounsDescriptorMinimal descriptor)
    external
    view
    override
    returns (Seed memory);
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


