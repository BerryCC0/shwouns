# IDAOLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal ShwounsDAOLogic surface used by the wiring/immutable checks + admin handoff.


## Functions
### governanceRewards

The GovernanceRewards reference. @return The GR address.


```solidity
function governanceRewards() external view returns (address);
```

### governanceRewardsLocked

Whether the GR reference is locked. @return True if locked.


```solidity
function governanceRewardsLocked() external view returns (bool);
```

### proposalEscrowImplementation

The ProposalEscrow implementation. @return The implementation address.


```solidity
function proposalEscrowImplementation() external view returns (address);
```

### proposalEscrowImplementationLocked

Whether the escrow implementation is locked. @return True if locked.


```solidity
function proposalEscrowImplementationLocked() external view returns (bool);
```

### shwouns

The Shwouns token. @return The token address.


```solidity
function shwouns() external view returns (address);
```

### vaultRegistry

The vault registry. @return The registry address.


```solidity
function vaultRegistry() external view returns (address);
```

### admin

The current admin. @return The admin address.


```solidity
function admin() external view returns (address);
```

### setAdminToDAO

One-shot direct admin handoff to the DAO itself (called during finalize).


```solidity
function setAdminToDAO() external;
```

