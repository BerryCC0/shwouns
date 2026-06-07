# IERC6551Registry
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/erc6551/interfaces/IERC6551Registry.sol)


## Functions
### createAccount

Creates a token bound account for a non-fungible token.
If account has already been created, returns the account address without calling create2.
Emits ERC6551AccountCreated event.


```solidity
function createAccount(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address tokenContract,
    uint256 tokenId
) external returns (address account);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the token bound account|


### account

Returns the computed token bound account address for a non-fungible token.


```solidity
function account(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
    external
    view
    returns (address account);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the token bound account|


## Events
### ERC6551AccountCreated
The registry MUST emit the ERC6551AccountCreated event upon successful account creation.


```solidity
event ERC6551AccountCreated(
    address account,
    address indexed implementation,
    bytes32 salt,
    uint256 chainId,
    address indexed tokenContract,
    uint256 indexed tokenId
);
```

## Errors
### AccountCreationFailed
The registry MUST revert with AccountCreationFailed error if the create2 operation fails.


```solidity
error AccountCreationFailed();
```

