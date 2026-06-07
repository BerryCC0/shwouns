# ERC6551BytecodeLib
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/erc6551/lib/ERC6551BytecodeLib.sol)


## Functions
### getCreationCode

Returns the creation code of the token bound account for a non-fungible token.


```solidity
function getCreationCode(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address tokenContract,
    uint256 tokenId
) internal pure returns (bytes memory result);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`result`|`bytes`|The creation code of the token bound account|


### computeAddress

Returns the create2 address computed from `salt`, `bytecodeHash`, `deployer`.


```solidity
function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer)
    internal
    pure
    returns (address result);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`result`|`address`|The create2 address computed from `salt`, `bytecodeHash`, `deployer`|


