# IShwounsAuctionHouse
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/IShwounsAuctionHouse.sol)

**Title:**
Interface for Shwouns Auction House

Forked from INounsAuctionHouseV3 (nouns-monorepo @ main). Mostly identical;
the only ABI change is the "noun" → "shwoun" terminology in events.


## Functions
### settleAuction

Settle the current auction without starting a new one (only while paused).


```solidity
function settleAuction() external;
```

### settleCurrentAndCreateNewAuction

Settle the current auction and immediately create the next one.


```solidity
function settleCurrentAndCreateNewAuction() external;
```

### createBid

Bid on the Shwoun currently up for auction.


```solidity
function createBid(uint256 shwounId) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwounId`|`uint256`|The id of the Shwoun being bid on (must match the active auction).|


### createBid

Bid on the current Shwoun, attributing the bid to a front-end client id.


```solidity
function createBid(uint256 shwounId, uint32 clientId) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwounId`|`uint256`|The id of the Shwoun being bid on (must match the active auction).|
|`clientId`|`uint32`|The front-end client id to attribute the bid to (0 = none).|


### pause

Pause the auction house. Owner/governance only.


```solidity
function pause() external;
```

### unpause

Unpause the auction house (starts an auction if none is live). Owner/governance only.


```solidity
function unpause() external;
```

### setTimeBuffer

Set the end-of-auction extension window. Owner/governance only.


```solidity
function setTimeBuffer(uint56 timeBuffer) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timeBuffer`|`uint56`|The new time buffer (seconds).|


### setReservePrice

Set the minimum opening bid. Owner/governance only.


```solidity
function setReservePrice(uint192 reservePrice) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`reservePrice`|`uint192`|The new reserve price (wei).|


### setMinBidIncrementPercentage

Set the minimum bid increment over the prior bid. Owner/governance only.


```solidity
function setMinBidIncrementPercentage(uint8 minBidIncrementPercentage) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`minBidIncrementPercentage`|`uint8`|The new increment (percent).|


## Events
### AuctionCreated
Emitted when a new auction starts (a Shwoun is minted and put up for bid).


```solidity
event AuctionCreated(uint256 indexed shwounId, uint256 startTime, uint256 endTime);
```

### AuctionBid
Emitted on each bid; `extended` is true if the bid pushed back the end time.


```solidity
event AuctionBid(uint256 indexed shwounId, address sender, uint256 value, bool extended);
```

### AuctionBidWithClientId
Emitted alongside AuctionBid when the bid carried a non-zero client id.


```solidity
event AuctionBidWithClientId(uint256 indexed shwounId, uint256 value, uint32 indexed clientId);
```

### AuctionExtended
Emitted when a late bid extends the auction end time.


```solidity
event AuctionExtended(uint256 indexed shwounId, uint256 endTime);
```

### AuctionSettled
Emitted when an auction is settled (winner determined, proceeds routed).


```solidity
event AuctionSettled(uint256 indexed shwounId, address winner, uint256 amount);
```

### AuctionSettledWithClientId
Emitted alongside AuctionSettled when the winning bid carried a client id.


```solidity
event AuctionSettledWithClientId(uint256 indexed shwounId, uint32 indexed clientId);
```

### AuctionTimeBufferUpdated
Emitted when the time buffer changes.


```solidity
event AuctionTimeBufferUpdated(uint256 timeBuffer);
```

### AuctionReservePriceUpdated
Emitted when the reserve price changes.


```solidity
event AuctionReservePriceUpdated(uint256 reservePrice);
```

### AuctionMinBidIncrementPercentageUpdated
Emitted when the minimum bid increment percentage changes.


```solidity
event AuctionMinBidIncrementPercentageUpdated(uint256 minBidIncrementPercentage);
```

### SanctionsOracleSet
Emitted when the sanctions oracle is set or cleared.


```solidity
event SanctionsOracleSet(address newSanctionsOracle);
```

### GovernanceRewardsSet
Emitted once when the settlement-proceeds recipient is set and locked.


```solidity
event GovernanceRewardsSet(address indexed governanceRewards);
```

### VaultRegistrySet
Emitted once when the vault registry is set and locked.


```solidity
event VaultRegistrySet(address indexed vaultRegistry);
```

## Structs
### AuctionV2

```solidity
struct AuctionV2 {
    uint96 shwounId;
    uint32 clientId;
    uint128 amount;
    uint40 startTime;
    uint40 endTime;
    address payable bidder;
    bool settled;
}
```

### AuctionV2View

```solidity
struct AuctionV2View {
    uint96 shwounId;
    uint128 amount;
    uint40 startTime;
    uint40 endTime;
    address payable bidder;
    bool settled;
}
```

### SettlementState

```solidity
struct SettlementState {
    uint32 blockTimestamp;
    uint64 amount;
    address winner;
    uint8 slotWarmedUp;
    uint32 clientId;
}
```

### Settlement

```solidity
struct Settlement {
    uint32 blockTimestamp;
    uint256 amount;
    address winner;
    uint256 shwounId;
    uint32 clientId;
}
```

### SettlementNoClientId

```solidity
struct SettlementNoClientId {
    uint32 blockTimestamp;
    uint256 amount;
    address winner;
    uint256 shwounId;
}
```

