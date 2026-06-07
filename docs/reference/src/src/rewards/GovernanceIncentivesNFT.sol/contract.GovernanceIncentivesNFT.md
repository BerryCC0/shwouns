# GovernanceIncentivesNFT
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/rewards/GovernanceIncentivesNFT.sol)

**Inherits:**
[ERC721](/src/token/base/ERC721.sol/contract.ERC721.md), [GovernedOwnable](/src/governance/GovernedOwnable.sol/abstract.GovernedOwnable.md)

**Title:**
GovernanceIncentivesNFT (GI NFT) — open-mint NFT that gates voter incentive eligibility

Anyone can mint a GI NFT by paying `mintPrice`. Mint proceeds are forwarded to
the contract owner (typically `GovernanceRewards`). Holding a GI NFT alone does
NOT qualify the holder for voter incentives — the tokenId must also be approved
in `ApprovalRegistry`. This two-layer gate (open mint + DAO allowlist) lets the
DAO curate which holders earn incentives without preventing anyone from minting.

Token IDs start at 1 (0 reserved as "no token").


## State Variables
### mintPrice
Price (in wei) to mint one GI NFT. Owner-settable by the DAO.


```solidity
uint256 public mintPrice
```


### nextTokenId
The id the next mint will assign (ids start at 1; 0 is reserved as "no token").


```solidity
uint256 public nextTokenId = 1
```


### proceedsRecipient
Recipient of mint proceeds (A6). Decoupled from `owner()` so the DAO can OWN the GI
NFT (and govern `setMintPrice`) while proceeds still flow to GovernanceRewards.
Falls back to `owner()` until set.


```solidity
address public proceedsRecipient
```


## Functions
### constructor


```solidity
constructor(uint256 _mintPrice, address _governanceAuth)
    ERC721("Shwouns Governance Incentives", "SHWN-GI")
    GovernedOwnable(_governanceAuth);
```

### mint

Mint a new GI NFT. Must send at least `mintPrice` ETH. Proceeds forward to
`proceedsRecipient` (GovernanceRewards), or `owner()` if unset.


```solidity
function mint() external payable returns (uint256 tokenId);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The id of the newly-minted GI NFT.|


### setMintPrice

Set the mint price. Governable (owner = DAO via the active escrow).


```solidity
function setMintPrice(uint256 newPrice) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPrice`|`uint256`|The new mint price in wei.|


### setProceedsRecipient

Set where mint proceeds are forwarded (A6). Governable (owner = DAO via escrow).


```solidity
function setProceedsRecipient(address newRecipient) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRecipient`|`address`|The new proceeds recipient (typically GovernanceRewards).|


## Events
### MintPriceUpdated
Emitted when the mint price changes.


```solidity
event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
```

### ProceedsRecipientUpdated
Emitted when the proceeds recipient changes.


```solidity
event ProceedsRecipientUpdated(address oldRecipient, address newRecipient);
```

### Minted
Emitted on each mint, recording the buyer, token id, and ETH paid.


```solidity
event Minted(address indexed to, uint256 indexed tokenId, uint256 pricePaid);
```

## Errors
### InsufficientPayment
Thrown when `mint` is sent less than `mintPrice`.


```solidity
error InsufficientPayment();
```

### ProceedsForwardFailed
Thrown when forwarding mint proceeds to the recipient fails.


```solidity
error ProceedsForwardFailed();
```

