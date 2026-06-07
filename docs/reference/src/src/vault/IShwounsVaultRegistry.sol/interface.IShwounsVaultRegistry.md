# IShwounsVaultRegistry
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/IShwounsVaultRegistry.sol)

**Title:**
Shwouns Vault Registry interface

The full external surface of ShwounsVaultRegistry. Vaults call markActive /
markPossiblyInactive and read daoLogic. ShwounsToken calls createVaultFor on mint.
DAOLogic iterates activeVaults at queue time.


## Functions
### daoLogic

The currently-registered DAOLogic — the only address a vault permits to call
`pullProRata`. Settable once at deployment, then locked.


```solidity
function daoLogic() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The DAOLogic address.|


### shwounsToken

The ShwounsToken whose tokens are bound to each vault.


```solidity
function shwounsToken() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The ShwounsToken address.|


### markActive

Callback from a vault on deposit: add the bound token to the active ("ever-funded")
set. Only callable by the token's own deterministic vault.


```solidity
function markActive(uint256 tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The bound Shwoun token id.|


### markPossiblyInactive

Callback from a vault on withdrawal. Retained for vault/interface compatibility; a
no-op because the active set is append-only (see the implementation's M-02 note).


```solidity
function markPossiblyInactive(uint256 tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The bound Shwoun token id.|


### vaultImplementation

The locked ShwounsVault implementation every vault clone points at.


```solidity
function vaultImplementation() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The vault implementation address.|


### vaultOf

The deterministic ERC-6551 account address for a token id (valid before deployment).


```solidity
function vaultOf(uint256 tokenId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun token id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The vault address computed from the canonical-registry CREATE2 formula.|


### createVaultFor

Deploy the vault for a token id (idempotent). Requires the bound token to exist.


```solidity
function createVaultFor(uint256 tokenId) external returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun token id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The vault address (existing if already deployed).|


### activeVaultsLength

Number of vaults in the append-only active set.


```solidity
function activeVaultsLength() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The active-set length.|


### activeVaultAt

The token id at a given index of the active set.


```solidity
function activeVaultAt(uint256 index) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`index`|`uint256`|The active-set index, `[0, activeVaultsLength())`.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The Shwoun token id at that index.|


### activeVaults

The full active set (gas-expensive; intended for off-chain reads).


```solidity
function activeVaults() external view returns (uint256[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|The array of active-set token ids.|


