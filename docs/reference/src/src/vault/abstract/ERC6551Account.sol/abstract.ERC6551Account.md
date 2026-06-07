# ERC6551Account
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/abstract/ERC6551Account.sol)

**Inherits:**
[IERC6551Account](/src/vault/erc6551/interfaces/IERC6551Account.sol/interface.IERC6551Account.md), ERC165, [Signatory](/src/vault/abstract/Signatory.sol/abstract.Signatory.md)

**Title:**
ERC-6551 Account Support

Implements the ERC-6551 Account interface


## State Variables
### _state

```solidity
uint256 _state
```


## Functions
### receive


```solidity
receive() external payable virtual;
```

### isValidSigner

See: [IERC6551Account-isValidSigner](/src/vault/erc6551/interfaces/IERC6551Account.sol/interface.IERC6551Account.md#isvalidsigner)


```solidity
function isValidSigner(address signer, bytes calldata data) external view returns (bytes4 magicValue);
```

### token

See: [IERC6551Account-token](/src/vault/erc6551/lib/ERC6551AccountLib.sol/library.ERC6551AccountLib.md#token)


```solidity
function token() public view returns (uint256 chainId, address tokenContract, uint256 tokenId);
```

### state

See: [IERC6551Account-state](/src/vault/erc6551/interfaces/IERC6551Account.sol/interface.IERC6551Account.md#state)


```solidity
function state() public view returns (uint256);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool);
```

### _isValidSigner

Returns true if a given signer is authorized to use this account


```solidity
function _isValidSigner(address signer, bytes memory) internal view virtual returns (bool);
```

