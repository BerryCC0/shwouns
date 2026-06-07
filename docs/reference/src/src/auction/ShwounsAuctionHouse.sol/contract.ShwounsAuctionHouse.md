# ShwounsAuctionHouse
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/auction/ShwounsAuctionHouse.sol)

**Inherits:**
[IShwounsAuctionHouse](/src/interfaces/IShwounsAuctionHouse.sol/interface.IShwounsAuctionHouse.md), PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable


## Constants
### MAX_TIME_BUFFER
Hard-cap on time buffer.


```solidity
uint56 public constant MAX_TIME_BUFFER = 1 days
```


### FOUNDERS_REWARD_ENDS
Last token ID at which founders receive a reward. Mirrors ShwounsToken.


```solidity
uint256 public constant FOUNDERS_REWARD_ENDS = 1820
```


### shwouns
The Shwouns ERC-721 token contract.


```solidity
IShwounsToken public immutable shwouns
```


### weth
WETH (settlement fallback if direct ETH transfer fails).


```solidity
address public immutable weth
```


### duration
Duration of a single auction (seconds).


```solidity
uint256 public immutable duration
```


### governanceAuth
Auth registry (A5). Immutable lives in impl bytecode, not proxy storage — so it adds
no storage slot. onlyOwner functions also accept the active proposal escrow via this.


```solidity
IGovernanceAuthRegistry public immutable governanceAuth
```


## State Variables
### reservePrice
The minimum opening bid for an auction (wei).


```solidity
uint192 public reservePrice
```


### timeBuffer
If a bid lands within this many seconds of the end, the auction extends by it.


```solidity
uint56 public timeBuffer
```


### minBidIncrementPercentage
Each new bid must exceed the previous by at least this percentage.


```solidity
uint8 public minBidIncrementPercentage
```


### auctionStorage
The currently-active auction (packed V2 layout).


```solidity
IShwounsAuctionHouse.AuctionV2 public auctionStorage
```


### settlementHistory

```solidity
mapping(uint256 => SettlementState) settlementHistory
```


### sanctionsOracle
Optional Chainalysis sanctions oracle; bids from sanctioned addresses are rejected.


```solidity
IChainalysisSanctionsList public sanctionsOracle
```


### governanceRewards
Recipient of all settlement proceeds. Settable once, then locked.


```solidity
address public governanceRewards
```


### governanceRewardsLocked
True once `governanceRewards` has been set, after which it can never change.


```solidity
bool public governanceRewardsLocked
```


### vaultRegistry
Vault registry used to deploy per-Shwoun vaults. Settable once, then locked.


```solidity
IShwounsVaultRegistry public vaultRegistry
```


### vaultRegistryLocked
True once `vaultRegistry` has been set, after which it can never change.


```solidity
bool public vaultRegistryLocked
```


## Functions
### constructor


```solidity
constructor(IShwounsToken _shwouns, address _weth, uint256 _duration, address _governanceAuth) initializer;
```

### _checkOwner

onlyOwner also accepts the currently-authenticated active proposal escrow (A5), so DAO
governance can pause/upgrade/tune the auction house via an approved proposal. Mirrors
GovernedOwnable for this OwnableUpgradeable contract.


```solidity
function _checkOwner() internal view override;
```

### transferOwnership

A10.5: once the auth registry is bound (post-bootstrap), ownership may only move to
the canonical DAO or address(0) — never an EOA. Pre-binding (bootstrap) is standard.


```solidity
function transferOwnership(address newOwner) public virtual override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOwner`|`address`|The proposed owner; constrained to the DAO or `address(0)` once bound.|


### initialize

Initialize the auction house. Sets initial knobs and pauses for setup.


```solidity
function initialize(
    uint192 _reservePrice,
    uint56 _timeBuffer,
    uint8 _minBidIncrementPercentage,
    IChainalysisSanctionsList _sanctionsOracle
) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_reservePrice`|`uint192`|The minimum opening bid (wei).|
|`_timeBuffer`|`uint56`|The end-of-auction extension window (seconds).|
|`_minBidIncrementPercentage`|`uint8`|The minimum bid increment over the prior bid (percent).|
|`_sanctionsOracle`|`IChainalysisSanctionsList`|The Chainalysis sanctions oracle (or zero to disable the check).|


### setGovernanceRewards

Set the settlement-proceeds recipient (GovernanceRewards). Callable once, then locked.


```solidity
function setGovernanceRewards(address _governanceRewards) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_governanceRewards`|`address`|The GovernanceRewards address.|


### setVaultRegistry

Set the vault registry used to deploy per-Shwoun vaults. Callable once, then locked.


```solidity
function setVaultRegistry(IShwounsVaultRegistry _vaultRegistry) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vaultRegistry`|`IShwounsVaultRegistry`|The ShwounsVaultRegistry address.|


### _authorizeUpgrade

UUPS upgrade gate (A9): authorize ONLY the active proposal escrow (governance), never a
standing EOA/admin, and require the candidate impl to report the canonical auth registry
(honest-upgrade safeguard against a storage-layout-only diff).


```solidity
function _authorizeUpgrade(address newImplementation) internal view override;
```

### settleCurrentAndCreateNewAuction

Settle the current auction and immediately start the next one. Reverts while paused.


```solidity
function settleCurrentAndCreateNewAuction() external override whenNotPaused;
```

### settleAuction

Settle the current auction without starting a new one. Only while paused.


```solidity
function settleAuction() external override whenPaused;
```

### createBid

Bid on the Shwoun currently up for auction (no client attribution).


```solidity
function createBid(uint256 shwounId) external payable override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwounId`|`uint256`|The id of the Shwoun being bid on (must match the active auction).|


### createBid

Bid on the current Shwoun, attributing the bid to a front-end client id.


```solidity
function createBid(uint256 shwounId, uint32 clientId) public payable override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwounId`|`uint256`|The id of the Shwoun being bid on (must match the active auction).|
|`clientId`|`uint32`|The front-end client id to attribute the bid to (0 = none).|


### auction

The current auction as an unpacked view struct.


```solidity
function auction() external view returns (AuctionV2View memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`AuctionV2View`|The active auction (shwounId, amount, start/end time, bidder, settled).|


### pause

Pause the auction house (no settle-and-create while paused). Owner/governance only.


```solidity
function pause() external override onlyOwner;
```

### unpause

Unpause and, if no auction is live, start one. Owner/governance only.


```solidity
function unpause() external override onlyOwner;
```

### setTimeBuffer

Set the end-of-auction extension window. Owner/governance only.


```solidity
function setTimeBuffer(uint56 _timeBuffer) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_timeBuffer`|`uint56`|The new time buffer (seconds); capped at `MAX_TIME_BUFFER`.|


### setReservePrice

Set the minimum opening bid. Owner/governance only.


```solidity
function setReservePrice(uint192 _reservePrice) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_reservePrice`|`uint192`|The new reserve price (wei).|


### setMinBidIncrementPercentage

Set the minimum bid increment over the prior bid. Owner/governance only.


```solidity
function setMinBidIncrementPercentage(uint8 _minBidIncrementPercentage) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minBidIncrementPercentage`|`uint8`|The new increment (percent); must be greater than zero.|


### setSanctionsOracle

Set (or clear) the Chainalysis sanctions oracle. Owner/governance only.


```solidity
function setSanctionsOracle(address newSanctionsOracle) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newSanctionsOracle`|`address`|The new oracle address, or zero to disable the sanctions check.|


### _createAuction

Create an auction, minting the next Shwoun (and possibly a founder Shwoun).
Creates vaults for both newly-minted Shwouns via the registry.


```solidity
function _createAuction() internal;
```

### _settleAuction

Settle the current auction. Routes Shwoun + ETH to the right recipients.


```solidity
function _settleAuction() internal;
```

### _safeTransferETHWithFallback


```solidity
function _safeTransferETHWithFallback(address to, uint256 amount) internal;
```

### _safeTransferETH


```solidity
function _safeTransferETH(address to, uint256 value) internal returns (bool);
```

### _requireNotSanctioned


```solidity
function _requireNotSanctioned(address account) internal view;
```

### setPrices

Backfill historical settlement prices (e.g. for analytics). Owner/governance only.


```solidity
function setPrices(SettlementNoClientId[] memory settlements) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`settlements`|`SettlementNoClientId[]`|The (shwounId, blockTimestamp, amount, winner) records to write.|


### warmUpSettlementState

Pre-warm settlement-history storage slots over a range (gas optimization for future
settlements). Permissionless. Skips founder-mint ids.


```solidity
function warmUpSettlementState(uint256 startId, uint256 endId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`startId`|`uint256`|The first id to warm (inclusive).|
|`endId`|`uint256`|The id to stop at (exclusive).|


### getSettlements

The most recent `auctionCount` settlements, newest first.


```solidity
function getSettlements(uint256 auctionCount, bool skipEmptyValues)
    external
    view
    returns (Settlement[] memory settlements);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`auctionCount`|`uint256`|The number of settlements to return.|
|`skipEmptyValues`|`bool`|If true, skip ids with no recorded settlement data.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`settlements`|`Settlement[]`|The settlement records (trimmed to those actually found).|


### getPrices

The most recent `auctionCount` winning prices (excludes no-bid/founder ids).


```solidity
function getPrices(uint256 auctionCount) external view returns (uint256[] memory prices);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`auctionCount`|`uint256`|The number of prices to return; reverts if history is insufficient.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`prices`|`uint256[]`|The winning bid amounts, newest first.|


### getSettlementsFromIdtoTimestamp

Settlements from `startId` forward until a record newer than `endTimestamp`.


```solidity
function getSettlementsFromIdtoTimestamp(uint256 startId, uint256 endTimestamp, bool skipEmptyValues)
    public
    view
    returns (Settlement[] memory settlements);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`startId`|`uint256`|The first id to include (inclusive).|
|`endTimestamp`|`uint256`|Stop once a settlement's timestamp exceeds this.|
|`skipEmptyValues`|`bool`|If true, skip ids with no recorded settlement data.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`settlements`|`Settlement[]`|The settlement records (trimmed to those actually found).|


### getSettlements

Settlements over the half-open id range `[startId, endId)`.


```solidity
function getSettlements(uint256 startId, uint256 endId, bool skipEmptyValues)
    external
    view
    returns (Settlement[] memory settlements);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`startId`|`uint256`|The first id to include (inclusive).|
|`endId`|`uint256`|The id to stop at (exclusive).|
|`skipEmptyValues`|`bool`|If true, skip ids with no recorded settlement data.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`settlements`|`Settlement[]`|The settlement records (trimmed to those actually found).|


### biddingClient

The front-end client id credited with the winning bid for a Shwoun.


```solidity
function biddingClient(uint256 shwounId) external view returns (uint32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwounId`|`uint256`|The Shwoun id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint32`|The winning bid's client id (0 if none).|


### ethPriceToUint64


```solidity
function ethPriceToUint64(uint256 ethPrice) internal pure returns (uint64);
```

### uint64PriceToUint256


```solidity
function uint64PriceToUint256(uint64 price) internal pure returns (uint256);
```

## Errors
### AlreadyLocked
Thrown when a one-time setter is called after it has already been locked.


```solidity
error AlreadyLocked();
```

### InvalidAddress
Thrown when a setter is given the zero address.


```solidity
error InvalidAddress();
```

### GovernanceRewardsNotSet
Thrown when settling before `governanceRewards` (the proceeds recipient) is set.


```solidity
error GovernanceRewardsNotSet();
```

### VaultRegistryNotSet
Thrown when creating an auction before the vault registry is set.


```solidity
error VaultRegistryNotSet();
```

