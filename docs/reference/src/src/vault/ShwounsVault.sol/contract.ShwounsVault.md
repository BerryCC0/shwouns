# ShwounsVault
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/ShwounsVault.sol)

**Inherits:**
ERC721Holder, ERC1155Holder, [Permissioned](/src/vault/abstract/Permissioned.sol/abstract.Permissioned.md), [ERC6551Account](/src/vault/abstract/ERC6551Account.sol/abstract.ERC6551Account.md), [ERC6551Executor](/src/vault/abstract/execution/ERC6551Executor.sol/abstract.ERC6551Executor.md), [BatchExecutor](/src/vault/abstract/execution/BatchExecutor.sol/abstract.BatchExecutor.md)

**Title:**
ShwounsVault — per-Noun token-bound vault

Forked from Tokenbound AccountV3 (https://github.com/tokenbound/contracts).
Removed: Lockable, Overridable, ERC4337Account, NestedAccountExecutor, OPAddressAliasHelper,
IAccountGuardian, ERC2771Context meta-tx forwarding.
Added: deposit/withdraw for ETH and ERC-20, pullProRata hook for DAOLogic, registry callbacks.
Security model:
- Anyone can deposit ETH or ERC-20s to a vault.
- The current owner of the bound Noun NFT (and any addresses they have granted permission to
via Permissioned) can withdraw and call arbitrary contracts via the inherited execute*
functions. This enables warm/cold wallet splits, council multisigs, and yield managers.
- The currently-configured DAOLogic (looked up via the immutable VaultRegistry) is the only
address that may call pullProRata. This drains a proposal's pro-rata share from this vault.
- There is no override/lock mechanism the owner can use to block pullProRata. Their recourse
is to withdraw funds before a proposal queues; the snapshot taken at queue caps the draw.


## Constants
### vaultRegistry
The Shwouns VaultRegistry. Immutable per impl deployment.


```solidity
IShwounsVaultRegistry public immutable vaultRegistry
```


## Functions
### constructor


```solidity
constructor(address _vaultRegistry) ;
```

### receive

Receive plain ETH transfers. Counts as a deposit; notifies registry.


```solidity
receive() external payable override;
```

### deposit

Deposit ETH explicitly (identical to plain transfer, kept for ABI clarity).


```solidity
function deposit() external payable;
```

### depositERC20

Deposit an ERC-20. Caller must have approved the vault first.


```solidity
function depositERC20(address token, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-20 to pull from the caller.|
|`amount`|`uint256`|The amount to deposit.|


### withdraw

Withdraw ETH to a recipient. Restricted to owner or permissioned address.


```solidity
function withdraw(address recipient, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|The address to send ETH to.|
|`amount`|`uint256`|The amount of ETH to withdraw.|


### withdrawERC20

Withdraw an ERC-20 to a recipient. Restricted to owner or permissioned address.


```solidity
function withdrawERC20(address token, address recipient, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-20 to withdraw.|
|`recipient`|`address`|The address to send the tokens to.|
|`amount`|`uint256`|The amount to withdraw.|


### withdrawERC20s

Batch withdraw multiple ERC-20s to a single recipient.


```solidity
function withdrawERC20s(address[] calldata tokens, address recipient, uint256[] calldata amounts) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|The ERC-20s to withdraw (parallel to `amounts`).|
|`recipient`|`address`|The address to send all tokens to.|
|`amounts`|`uint256[]`|The amount to withdraw for each token in `tokens`.|


### pullProRata

Pull a specific amount of an asset to a recipient. Only callable by the currently
registered DAOLogic. Used during proposal execution to drain a vault's pro-rata
share, capped at the queue-time snapshot vs current balance.


```solidity
function pullProRata(uint256 proposalId, address asset, address recipient, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal driving this pull. Logged for indexer correlation.|
|`asset`|`address`|The asset to transfer. Use address(0) for native ETH.|
|`recipient`|`address`|The proposal target receiving the funds.|
|`amount`|`uint256`|The amount to transfer. DAOLogic computes this from the snapshot pro-rata share.|


### owner

Returns the current Noun NFT owner. Zero if the bound token doesn't exist on this chain.


```solidity
function owner() public view virtual returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address that owns the bound Shwoun, or `address(0)`.|


### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC1155Receiver, ERC6551Account, ERC6551Executor)
    returns (bool);
```

### onERC721Received

ERC-721 receiver hook. Accepts incoming NFTs except the bound Shwoun itself.

Revert if the NFT being transferred IN is the same one this account is bound to.


```solidity
function onERC721Received(address, address, uint256 tokenId, bytes memory)
    public
    virtual
    override
    returns (bytes4);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`||
|`<none>`|`address`||
|`tokenId`|`uint256`|The id of the NFT being received.|
|`<none>`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4`|The ERC-721 receiver magic value.|


### _isValidSigner

Signer is valid iff it is the bound Shwoun's owner or an address that owner has granted
permission to (Permissioned). Backs ERC-1271 validation.


```solidity
function _isValidSigner(address signer, bytes memory) internal view virtual override returns (bool);
```

### _isValidSignature

ERC-1271 signature validation: ECDSA or smart-contract signatures (v=0).
L-01: malformed/short input returns false (the wrapper then returns a non-magic value),
never reverts — integrations rely on ERC-1271 returning "invalid", not throwing. This is
a deliberate divergence from upstream Tokenbound AccountV3, which read signature[64] and
dynamic offsets without bounds checks (this file is a fork).


```solidity
function _isValidSignature(bytes32 hash, bytes calldata signature) internal view virtual override returns (bool);
```

### _isValidExecutor

Executor is authorized to withdraw / call from the vault iff it is the bound Shwoun's
owner or a Permissioned address of that owner. Gates withdraw/withdrawERC20/execute.


```solidity
function _isValidExecutor(address executor) internal view virtual override returns (bool);
```

### _rootTokenOwner


```solidity
function _rootTokenOwner(uint256 chainId, address tokenContract, uint256 tokenId)
    internal
    view
    virtual
    override(Permissioned)
    returns (address);
```

### _tokenOwner


```solidity
function _tokenOwner(uint256 chainId, address tokenContract, uint256 tokenId)
    internal
    view
    virtual
    returns (address);
```

### _beforeExecute


```solidity
function _beforeExecute() internal virtual override;
```

### _updateState


```solidity
function _updateState() internal virtual;
```

### _beforeSetPermissions


```solidity
function _beforeSetPermissions() internal virtual override;
```

### _notifyActive


```solidity
function _notifyActive() internal;
```

### _notifyPossiblyInactive


```solidity
function _notifyPossiblyInactive() internal;
```

## Events
### Deposited
Emitted on every deposit. `asset` is `address(0)` for native ETH.


```solidity
event Deposited(address indexed asset, address indexed from, uint256 amount);
```

### Withdrawn
Emitted on every withdrawal. `asset` is `address(0)` for native ETH.


```solidity
event Withdrawn(address indexed asset, address indexed to, uint256 amount);
```

### ProRataPulled
Emitted when DAOLogic pulls a proposal's pro-rata share from this vault.


```solidity
event ProRataPulled(uint256 indexed proposalId, address indexed asset, address indexed recipient, uint256 amount);
```

## Errors
### InvalidVaultRegistry
Thrown when the constructor is given a zero vault-registry address.


```solidity
error InvalidVaultRegistry();
```

### NotDAOLogic
Thrown when `pullProRata` is called by anything other than the registered DAOLogic.


```solidity
error NotDAOLogic();
```

### InsufficientBalance
Thrown when an ETH withdraw/pull exceeds the vault's balance.


```solidity
error InsufficientBalance();
```

### ETHTransferFailed
Thrown when a native-ETH transfer out of the vault fails.


```solidity
error ETHTransferFailed();
```

