# IShwounsDescriptorMinimal
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/IShwounsDescriptorMinimal.sol)

**Title:**
Common interface for ShwounsDescriptor, used by ShwounsToken and ShwounsSeeder.

Forked from INounsDescriptorMinimal — `glassesCount` removed.


## Functions
### tokenURI

The token URI for a Shwoun given its seed (data URI or baseURI form).


```solidity
function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view returns (string memory);
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
function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view returns (string memory);
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


### backgroundCount

The number of available background traits.


```solidity
function backgroundCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The background count.|


### bodyCount

The number of available body traits.


```solidity
function bodyCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The body count.|


### accessoryCount

The number of available accessory traits.


```solidity
function accessoryCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The accessory count.|


### headCount

The number of available head traits.


```solidity
function headCount() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The head count.|


