# Inflator
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/Inflator.sol)

**Inherits:**
[IInflator](/src/interfaces/IInflator.sol/interface.IInflator.md)

**Title:**
A contract used to decompress data compressed using the Deflate algorithm.
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
### puff

Decompresses Deflated bytes using the Puff algorithm
based on Based on https://github.com/adlerjohn/inflate-sol.


```solidity
function puff(bytes memory source, uint256 destlen) public pure returns (Inflate.ErrorCode, bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`source`|`bytes`|the bytes to decompress.|
|`destlen`|`uint256`|the length of the original decompressed bytes.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Inflate.ErrorCode`|Inflate.ErrorCode 0 if successful, otherwise an error code specifying the reason for failure.|
|`<none>`|`bytes`|bytes the decompressed bytes.|


