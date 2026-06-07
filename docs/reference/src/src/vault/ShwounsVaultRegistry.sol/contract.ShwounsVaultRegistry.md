# ShwounsVaultRegistry
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/ShwounsVaultRegistry.sol)

**Inherits:**
[IShwounsVaultRegistry](/src/vault/IShwounsVaultRegistry.sol/interface.IShwounsVaultRegistry.md), [GovernedOwnable](/src/governance/GovernedOwnable.sol/abstract.GovernedOwnable.md)

**Title:**
ShwounsVaultRegistry

Single source of truth for per-Noun vault addresses, the active-set, and the
currently-authorized DAOLogic. Wraps the canonical ERC-6551 registry (deployed at
the same address on every chain) and adds:
- markActive/markPossiblyInactive callbacks from vaults to maintain a funded set
- daoLogic reference that vaults consult to gate pullProRata
- createVaultFor convenience used by ShwounsToken on mint
Deployment order (must follow this sequence for circular constructor deps):
1. Deploy ShwounsToken
2. Deploy ShwounsVaultRegistry(token)        — vaultImplementation is unset
3. Deploy ShwounsVault impl(registry)        — registry address baked in
4. registry.setVaultImplementation(impl)     — locks vaultImplementation forever
5. Wire ShwounsToken.setMinter(auctionHouse) etc.
6. Deploy ShwounsDAOLogic
7. registry.setDAOLogic(daoLogic)            — locks daoLogic forever
After step 4 and step 7, the registry is fully configured and immutable in practice.


## Constants
### CANONICAL_ERC6551_REGISTRY
The canonical ERC-6551 Registry. Same address on every major chain per EIP-6551.


```solidity
address public constant CANONICAL_ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758
```


### SALT
Salt used for deterministic vault addressing. We use 0 — one vault per (impl, NFT).


```solidity
bytes32 public constant SALT = bytes32(0)
```


### shwounsToken
The ShwounsToken contract whose tokens are bound to each vault. Immutable.


```solidity
address public immutable shwounsToken
```


## State Variables
### vaultImplementation
The ShwounsVault implementation contract. Settable once via setVaultImplementation,
then locked. All vaults are ERC-1167 proxies pointing at this impl.


```solidity
address public vaultImplementation
```


### vaultImplementationLocked
True once `vaultImplementation` has been set, after which it can never change.


```solidity
bool public vaultImplementationLocked
```


### daoLogic
The Shwouns DAOLogic. Vaults gate pullProRata on this address. Settable once,
then locked.


```solidity
address public daoLogic
```


### daoLogicLocked
True once `daoLogic` has been set, after which it can never change.


```solidity
bool public daoLogicLocked
```


### _activeVaults
Token IDs whose vaults have been marked active (i.e., received a deposit).
May contain false positives (vault was funded then drained without notification);
DAOLogic must re-check current balances at queue time.


```solidity
EnumerableSet.UintSet private _activeVaults
```


## Functions
### constructor


```solidity
constructor(address _shwounsToken, address _governanceAuth) GovernedOwnable(_governanceAuth);
```

### setVaultImplementation

Set the vault implementation address. Callable once.


```solidity
function setVaultImplementation(address impl) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`impl`|`address`|The ShwounsVault implementation address; locked permanently after this call.|


### setDAOLogic

Set the DAOLogic address. Callable once.


```solidity
function setDAOLogic(address _daoLogic) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_daoLogic`|`address`|The DAOLogic address vaults will gate `pullProRata` on; locked after this call.|


### vaultOf

Compute the deterministic vault address for a token ID. Works before the vault
is actually deployed — the address is determined by the CREATE2 formula.


```solidity
function vaultOf(uint256 tokenId) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun token id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The deterministic vault address.|


### createVaultFor

Deploy the vault for a token ID. Idempotent — returns existing address if already
deployed. Called by ShwounsToken on mint; can also be called by anyone post-mint.

C-03: the bound token MUST exist. Without this gate anyone could deploy vaults for
unminted token IDs and inflate the active set until proposal queueing exceeds block gas.


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


### _requireTokenExists

C-03 existence gate: the bound token must exist (ownerOf succeeds and is non-zero).


```solidity
function _requireTokenExists(uint256 tokenId) internal view;
```

### markActive

Callback from a vault on deposit: add the bound token to the active ("ever-funded")
set. Only callable by the token's own deterministic vault.

C-03 defense-in-depth: only a real, minted token's vault can enter the active set.


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

M-02: the active set is APPEND-ONLY ("ever funded"). recordSnapshot skips zero-balance
vaults at snapshot time, so correctness never required removal — and balance-inferred
removal was the M-02 eviction bug (a zero-ETH but ERC-20-funded vault could be evicted,
and `withdrawERC20(..., 0)` could grief). Append-only is also the precondition that
makes the paged queue-freeze sound (M-05): indices [0, freezeTarget) never shift.
Retained as a no-op for vault-callback / interface compatibility.


```solidity
function markPossiblyInactive(uint256) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||


### _requireCallerIsVault

Auth gate for `markActive`: the caller must be the token's OWN deterministic vault
address, so a vault can only mark itself (not another token) into the active set.


```solidity
function _requireCallerIsVault(uint256 tokenId) internal view;
```

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

Gas-expensive for large sets. Prefer paginated iteration via activeVaultAt
in on-chain contexts; this is for off-chain reads.


```solidity
function activeVaults() external view returns (uint256[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|The array of active-set token ids.|


## Events
### VaultImplementationSet
Emitted once when the vault implementation is set and locked.


```solidity
event VaultImplementationSet(address indexed impl);
```

### DAOLogicSet
Emitted once when the DAOLogic reference is set and locked.


```solidity
event DAOLogicSet(address indexed daoLogic);
```

### VaultMarkedActive
Emitted the first time a token's vault enters the active set.


```solidity
event VaultMarkedActive(uint256 indexed tokenId);
```

### VaultMarkedInactive
Reserved for active-set removal; never emitted (the set is append-only).


```solidity
event VaultMarkedInactive(uint256 indexed tokenId);
```

## Errors
### InvalidAddress
Thrown when a setter or the constructor is given a zero address.


```solidity
error InvalidAddress();
```

### AlreadyLocked
Thrown when a one-time setter is called after it has already been locked.


```solidity
error AlreadyLocked();
```

### NotAuthorizedVault
Thrown when `markActive` is called by an address other than the token's own vault.


```solidity
error NotAuthorizedVault();
```

### VaultImplementationNotSet
Thrown when `vaultOf`/`createVaultFor` is called before the implementation is set.


```solidity
error VaultImplementationNotSet();
```

### TokenDoesNotExist
Thrown when a vault is requested for a token id that does not exist (C-03 gate).


```solidity
error TokenDoesNotExist();
```

