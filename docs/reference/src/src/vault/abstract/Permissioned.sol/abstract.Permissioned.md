# Permissioned
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/abstract/Permissioned.sol)

**Title:**
Account Permissions

Allows the root owner of a token bound account to allow another account to execute
operations from this account. Permissions are keyed by the root owner address, so will be
disabled upon transfer of the token which owns this account tree.


## State Variables
### permissions
mapping from owner => caller => has permissions


```solidity
mapping(address => mapping(address => bool)) public permissions
```


## Functions
### setPermissions

Grants or revokes execution permissions for a given array of callers on this account.
Can only be called by the root owner of the account


```solidity
function setPermissions(address[] calldata callers, bool[] calldata _permissions) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`callers`|`address[]`|Array of callers to grant permissions to|
|`_permissions`|`bool[]`|Array of booleans, true if execution permissions should be granted, false if permissions should be revoked|


### hasPermission

Returns true if caller has permissions to act on behalf of owner


```solidity
function hasPermission(address caller, address owner) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`caller`|`address`|Address to query permissions for|
|`owner`|`address`|Root owner address for which to query permissions|


### _beforeSetPermissions


```solidity
function _beforeSetPermissions() internal virtual;
```

### _rootTokenOwner


```solidity
function _rootTokenOwner(uint256 chainId, address tokenContract, uint256 tokenId)
    internal
    view
    virtual
    returns (address);
```

## Events
### PermissionUpdated

```solidity
event PermissionUpdated(address owner, address caller, bool hasPermission);
```

