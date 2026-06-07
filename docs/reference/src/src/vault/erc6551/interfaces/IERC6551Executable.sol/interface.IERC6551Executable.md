# IERC6551Executable
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/erc6551/interfaces/IERC6551Executable.sol)

the ERC-165 identifier for this interface is `0x51945447`


## Functions
### execute

Executes a low-level operation if the caller is a valid signer on the account.
Reverts and bubbles up error if operation fails.
Accounts implementing this interface MUST accept the following operation parameter values:
- 0 = CALL
- 1 = DELEGATECALL
- 2 = CREATE
- 3 = CREATE2
Accounts implementing this interface MAY support additional operations or restrict a signer's
ability to execute certain operations.


```solidity
function execute(address to, uint256 value, bytes calldata data, uint8 operation)
    external
    payable
    returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|       The target address of the operation|
|`value`|`uint256`|    The Ether value to be sent to the target|
|`data`|`bytes`|     The encoded operation calldata|
|`operation`|`uint8`|A value indicating the type of operation to perform|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The result of the operation|


