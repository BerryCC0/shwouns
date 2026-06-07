# ERC721
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/base/ERC721.sol)

**Inherits:**
Context, ERC165, IERC721, IERC721Metadata

**Title:**
ERC721 Token Implementation
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

Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
the Metadata extension, but not including the Enumerable extension, which is available separately as
{ERC721Enumerable}.


## State Variables
### _name

```solidity
string private _name
```


### _symbol

```solidity
string private _symbol
```


### _owners

```solidity
mapping(uint256 => address) private _owners
```


### _balances

```solidity
mapping(address => uint256) private _balances
```


### _tokenApprovals

```solidity
mapping(uint256 => address) private _tokenApprovals
```


### _operatorApprovals

```solidity
mapping(address => mapping(address => bool)) private _operatorApprovals
```


## Functions
### constructor

Initializes the contract by setting a `name` and a `symbol` to the token collection.


```solidity
constructor(string memory name_, string memory symbol_) ;
```

### supportsInterface

See [IERC165-supportsInterface](/src/token/base/ERC721Enumerable.sol/abstract.ERC721Enumerable.md#supportsinterface).


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool);
```

### balanceOf

See [IERC721-balanceOf](/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol/interface.IERC20.md#balanceof).


```solidity
function balanceOf(address owner) public view virtual override returns (uint256);
```

### ownerOf

See [IERC721-ownerOf](/src/governance/ShwounsDAOInterfaces.sol/interface.IShwounsTokenLike.md#ownerof).


```solidity
function ownerOf(uint256 tokenId) public view virtual override returns (address);
```

### name

See [IERC721Metadata-name](/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol/contract.ERC20.md#name).


```solidity
function name() public view virtual override returns (string memory);
```

### symbol

See [IERC721Metadata-symbol](/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol/contract.ERC20.md#symbol).


```solidity
function symbol() public view virtual override returns (string memory);
```

### tokenURI

See [IERC721Metadata-tokenURI](/src/interfaces/IShwounsDescriptorMinimal.sol/interface.IShwounsDescriptorMinimal.md#tokenuri).


```solidity
function tokenURI(uint256 tokenId) public view virtual override returns (string memory);
```

### _baseURI

Base URI for computing [tokenURI](/src/token/base/ERC721.sol/contract.ERC721.md#tokenuri). If set, the resulting URI for each
token will be the concatenation of the `baseURI` and the `tokenId`. Empty
by default, can be overridden in child contracts.


```solidity
function _baseURI() internal view virtual returns (string memory);
```

### approve

See [IERC721-approve](/src/rewards/ApprovalRegistry.sol/contract.ApprovalRegistry.md#approve).


```solidity
function approve(address to, uint256 tokenId) public virtual override;
```

### getApproved

See [IERC721-getApproved](/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol/contract.ERC721.md#getapproved).


```solidity
function getApproved(uint256 tokenId) public view virtual override returns (address);
```

### setApprovalForAll

See [IERC721-setApprovalForAll](/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol/contract.ERC721.md#setapprovalforall).


```solidity
function setApprovalForAll(address operator, bool approved) public virtual override;
```

### isApprovedForAll

See [IERC721-isApprovedForAll](/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol/contract.ERC721.md#isapprovedforall).


```solidity
function isApprovedForAll(address owner, address operator) public view virtual override returns (bool);
```

### transferFrom

See [IERC721-transferFrom](/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol/interface.IERC20.md#transferfrom).


```solidity
function transferFrom(address from, address to, uint256 tokenId) public virtual override;
```

### safeTransferFrom

See [IERC721-safeTransferFrom](/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol/library.SafeERC20.md#safetransferfrom).


```solidity
function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override;
```

### safeTransferFrom

See [IERC721-safeTransferFrom](/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol/library.SafeERC20.md#safetransferfrom).


```solidity
function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override;
```

### _safeTransfer

Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
are aware of the ERC721 protocol to prevent tokens from being forever locked.
`_data` is additional data, it has no specified format and it is sent in call to `to`.
This internal function is equivalent to [safeTransferFrom](/src/token/base/ERC721.sol/contract.ERC721.md#safetransferfrom), and can be used to e.g.
implement alternative mechanisms to perform token transfer, such as signature-based.
Requirements:
- `from` cannot be the zero address.
- `to` cannot be the zero address.
- `tokenId` token must exist and be owned by `from`.
- If `to` refers to a smart contract, it must implement [IERC721Receiver-onERC721Received](/src/rewards/GovernanceRewards.sol/contract.GovernanceRewards.md#onerc721received), which is called upon a safe transfer.
Emits a {Transfer} event.


```solidity
function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual;
```

### _exists

Returns whether `tokenId` exists.
Tokens can be managed by their owner or approved accounts via [approve](/src/token/base/ERC721.sol/contract.ERC721.md#approve) or [setApprovalForAll](/src/token/base/ERC721.sol/contract.ERC721.md#setapprovalforall).
Tokens start existing when they are minted (`_mint`),
and stop existing when they are burned (`_burn`).


```solidity
function _exists(uint256 tokenId) internal view virtual returns (bool);
```

### _isApprovedOrOwner

Returns whether `spender` is allowed to manage `tokenId`.
Requirements:
- `tokenId` must exist.


```solidity
function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool);
```

### _safeMint

Safely mints `tokenId`, transfers it to `to`, and emits two log events -
1. Credits the `minter` with the mint.
2. Shows transfer from the `minter` to `to`.
Requirements:
- `tokenId` must not exist.
- If `to` refers to a smart contract, it must implement [IERC721Receiver-onERC721Received](/src/rewards/GovernanceRewards.sol/contract.GovernanceRewards.md#onerc721received), which is called upon a safe transfer.
Emits a {Transfer} event.


```solidity
function _safeMint(address creator, address to, uint256 tokenId) internal virtual;
```

### _safeMint

Same as [`_safeMint`](/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol/contract.ERC721.md#_safemint), with an additional `data` parameter which is
forwarded in [IERC721Receiver-onERC721Received](/src/rewards/GovernanceRewards.sol/contract.GovernanceRewards.md#onerc721received) to contract recipients.


```solidity
function _safeMint(address creator, address to, uint256 tokenId, bytes memory _data) internal virtual;
```

### _mint

Mints `tokenId`, transfers it to `to`, and emits two log events -
1. Credits the `creator` with the mint.
2. Shows transfer from the `creator` to `to`.
WARNING: Usage of this method is discouraged, use [_safeMint](/src/token/base/ERC721.sol/contract.ERC721.md#_safemint) whenever possible
Requirements:
- `tokenId` must not exist.
- `to` cannot be the zero address.
Emits a {Transfer} event.


```solidity
function _mint(address creator, address to, uint256 tokenId) internal virtual;
```

### _burn

Destroys `tokenId`.
The approval is cleared when the token is burned.
Requirements:
- `tokenId` must exist.
Emits a {Transfer} event.


```solidity
function _burn(uint256 tokenId) internal virtual;
```

### _transfer

Transfers `tokenId` from `from` to `to`.
As opposed to [transferFrom](/src/token/base/ERC721.sol/contract.ERC721.md#transferfrom), this imposes no restrictions on msg.sender.
Requirements:
- `to` cannot be the zero address.
- `tokenId` token must be owned by `from`.
Emits a {Transfer} event.


```solidity
function _transfer(address from, address to, uint256 tokenId) internal virtual;
```

### _approve

Approve `to` to operate on `tokenId`
Emits a {Approval} event.


```solidity
function _approve(address to, uint256 tokenId) internal virtual;
```

### _checkOnERC721Received

Internal function to invoke [IERC721Receiver-onERC721Received](/src/rewards/GovernanceRewards.sol/contract.GovernanceRewards.md#onerc721received) on a target address.
The call is not executed if the target address is not a contract.


```solidity
function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
    private
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|address representing the previous owner of the given token ID|
|`to`|`address`|target address that will receive the tokens|
|`tokenId`|`uint256`|uint256 ID of the token to be transferred|
|`_data`|`bytes`|bytes optional data to send along with the call|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool whether the call correctly returned the expected magic value|


### _beforeTokenTransfer

Hook that is called before any token transfer. This includes minting
and burning.
Calling conditions:
- When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
transferred to `to`.
- When `from` is zero, `tokenId` will be minted for `to`.
- When `to` is zero, ``from``'s `tokenId` will be burned.
- `from` and `to` are never both zero.
To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].


```solidity
function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual;
```

