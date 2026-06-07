# ShwounsDAOQuorum
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOQuorum.sol)

**Title:**
Shwouns DAO dynamic-quorum checkpoint-admin library

Split out of ShwounsDAOLogic to keep the facade under EIP-170 (audit F1). Holds ONLY the
dynamic-quorum CHECKPOINT-ADMIN: the bounds-checked setters that write a new
DynamicQuorumParamsCheckpoint, and the min/max absolute-vote views. The hot-path quorum
COMPUTE (quorumVotes / _getDynamicQuorumParamsAt) deliberately stays in
ShwounsDAOProposals so `state()` keeps an internal JUMP, not a cross-library delegatecall.

Delegatecalled by the facade on the same `ds` storage (via `using ... for Storage`), so all
writes land in the proxy's storage exactly as the inline facade code did. Bounds, errors and
events mirror the originals byte-for-byte (event topics match ShwounsDAOEvents).


## Constants
### MIN_QUORUM_VOTES_BPS_LOWER_BOUND

```solidity
uint16 internal constant MIN_QUORUM_VOTES_BPS_LOWER_BOUND = 200
```


### MIN_QUORUM_VOTES_BPS_UPPER_BOUND

```solidity
uint16 internal constant MIN_QUORUM_VOTES_BPS_UPPER_BOUND = 2_000
```


### MAX_QUORUM_VOTES_BPS_UPPER_BOUND

```solidity
uint16 internal constant MAX_QUORUM_VOTES_BPS_UPPER_BOUND = 6_000
```


## Functions
### setDynamicQuorumParams

Set all three dynamic-quorum params (bounds-checked). The facade's onlyAdmin wrapper
calls this; `initialize` also calls it directly to seed the first checkpoint, so the
bounds validation runs at init too.


```solidity
function setDynamicQuorumParams(
    ShwounsDAOTypes.Storage storage ds,
    uint16 newMinQuorumVotesBPS,
    uint16 newMaxQuorumVotesBPS,
    uint32 newQuorumCoefficient
) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`newMinQuorumVotesBPS`|`uint16`|New minimum quorum, in BPS of total supply (200..2000).|
|`newMaxQuorumVotesBPS`|`uint16`|New maximum quorum, in BPS of total supply (<= 6000).|
|`newQuorumCoefficient`|`uint32`|New coefficient scaling quorum by against-vote share (fixed-point 1e6).|


### _setDynamicQuorumParams

Bounds-checked checkpoint write. Internal so the public setters above share it without an
extra delegatecall hop.


```solidity
function _setDynamicQuorumParams(
    ShwounsDAOTypes.Storage storage ds,
    uint16 newMinQuorumVotesBPS,
    uint16 newMaxQuorumVotesBPS,
    uint32 newQuorumCoefficient
) internal;
```

### setMinQuorumVotesBPS

Update only the minimum quorum BPS (writes a new checkpoint, other params unchanged).


```solidity
function setMinQuorumVotesBPS(ShwounsDAOTypes.Storage storage ds, uint16 newMinQuorumVotesBPS) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`newMinQuorumVotesBPS`|`uint16`|New minimum quorum, in BPS of total supply (200..2000).|


### setMaxQuorumVotesBPS

Update only the maximum quorum BPS (writes a new checkpoint, other params unchanged).


```solidity
function setMaxQuorumVotesBPS(ShwounsDAOTypes.Storage storage ds, uint16 newMaxQuorumVotesBPS) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`newMaxQuorumVotesBPS`|`uint16`|New maximum quorum, in BPS of total supply (<= 6000).|


### setQuorumCoefficient

Update only the quorum coefficient (writes a new checkpoint, other params unchanged).


```solidity
function setQuorumCoefficient(ShwounsDAOTypes.Storage storage ds, uint32 newQuorumCoefficient) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ds`|`ShwounsDAOTypes.Storage`||
|`newQuorumCoefficient`|`uint32`|New coefficient scaling quorum by against-vote share (fixed-point 1e6).|


### minQuorumVotes

Current minimum quorum in absolute votes (minQuorumVotesBPS of total supply).


```solidity
function minQuorumVotes(ShwounsDAOTypes.Storage storage ds) external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The minimum quorum in votes.|


### maxQuorumVotes

Current maximum quorum in absolute votes (maxQuorumVotesBPS of total supply).


```solidity
function maxQuorumVotes(ShwounsDAOTypes.Storage storage ds) external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum quorum in votes.|


### latestDynamicQuorumParams


```solidity
function latestDynamicQuorumParams(ShwounsDAOTypes.Storage storage ds)
    internal
    view
    returns (ShwounsDAOTypes.DynamicQuorumParams memory);
```

### _writeQuorumParamsCheckpoint

Append a dynamic-quorum checkpoint at the current block, or overwrite the existing one if
a checkpoint already exists for this block (so multiple changes in one block coalesce).


```solidity
function _writeQuorumParamsCheckpoint(
    ShwounsDAOTypes.Storage storage ds,
    ShwounsDAOTypes.DynamicQuorumParams memory params
) internal;
```

## Events
### MinQuorumVotesBPSSet
Emitted when the minimum quorum BPS changes (a new checkpoint is written).


```solidity
event MinQuorumVotesBPSSet(uint16 oldMinQuorumVotesBPS, uint16 newMinQuorumVotesBPS);
```

### MaxQuorumVotesBPSSet
Emitted when the maximum quorum BPS changes (a new checkpoint is written).


```solidity
event MaxQuorumVotesBPSSet(uint16 oldMaxQuorumVotesBPS, uint16 newMaxQuorumVotesBPS);
```

### QuorumCoefficientSet
Emitted when the quorum coefficient changes (a new checkpoint is written).


```solidity
event QuorumCoefficientSet(uint32 oldQuorumCoefficient, uint32 newQuorumCoefficient);
```

## Errors
### InvalidMinQuorumVotesBPS
Thrown when minQuorumVotesBPS is outside [200, 2000].


```solidity
error InvalidMinQuorumVotesBPS();
```

### InvalidMaxQuorumVotesBPS
Thrown when maxQuorumVotesBPS exceeds 6000.


```solidity
error InvalidMaxQuorumVotesBPS();
```

### MinQuorumBPSGreaterThanMaxQuorumBPS
Thrown when minQuorumVotesBPS exceeds maxQuorumVotesBPS.


```solidity
error MinQuorumBPSGreaterThanMaxQuorumBPS();
```

