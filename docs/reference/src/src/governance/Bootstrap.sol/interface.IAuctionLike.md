# IAuctionLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal ShwounsAuctionHouse surface used by the wiring/immutable checks + handoff unpause.


## Functions
### governanceRewards

The settlement-proceeds recipient. @return The GovernanceRewards address.


```solidity
function governanceRewards() external view returns (address);
```

### vaultRegistry

The vault registry. @return The registry address.


```solidity
function vaultRegistry() external view returns (address);
```

### shwouns

The Shwouns token. @return The token address.


```solidity
function shwouns() external view returns (address);
```

### governanceRewardsLocked

Whether the proceeds recipient is locked. @return True if locked.


```solidity
function governanceRewardsLocked() external view returns (bool);
```

### vaultRegistryLocked

Whether the vault registry is locked. @return True if locked.


```solidity
function vaultRegistryLocked() external view returns (bool);
```

### paused

Whether the auction house is paused. @return True if paused.


```solidity
function paused() external view returns (bool);
```

### unpause

Unpause the auction house (kicks off auction #1 during handoff).


```solidity
function unpause() external;
```

