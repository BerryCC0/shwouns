# GovernedOwnable
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/GovernedOwnable.sol)

**Inherits:**
Ownable

**Title:**
GovernedOwnable — Ownable whose owner-gated functions also accept the active escrow

An `Ownable` variant whose `onlyOwner` functions are ALSO callable by the currently-
authenticated active proposal escrow (resolved through the fail-closed
GovernanceAuthRegistry). This is how an approved governance action — executing from its
own per-proposal escrow — manages a DAO-owned contract, without any standing EOA
authority. Used by the six non-upgradeable governed contracts (A5). The upgradeable
AuctionHouse applies the same rule inline against OwnableUpgradeable.

Stateless beyond an `immutable governanceAuth` reference — immutables live in contract
bytecode, not storage, so this adds NO storage slot (safe for every governed contract,
including ones whose layout matters). `governanceAuth == address(0)` reduces behavior to
plain Ownable (used by unit/test setups that don't exercise governance).


## Constants
### governanceAuth
The fail-closed registry consulted to recognize the active proposal escrow as an
authorized caller of `onlyOwner` functions. `address(0)` reduces this to plain Ownable.


```solidity
IGovernanceAuthRegistry public immutable governanceAuth
```


## Functions
### constructor


```solidity
constructor(address _governanceAuth) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_governanceAuth`|`address`|The GovernanceAuthRegistry, or `address(0)` for plain-Ownable behavior.|


### _checkOwner

Accept the structural owner OR the active proposal escrow. Mirrors OZ's revert message
so existing integrations/tests that match on it keep working.


```solidity
function _checkOwner() internal view virtual override;
```

### transferOwnership

A10.5: once the auth registry is bound (post-bootstrap), ownership may only move to
the canonical DAO or to address(0) — never to an EOA. Before binding (the bootstrap
window, when only the trusted Bootstrap coordinator owns these contracts) this is
standard Ownable, so Bootstrap can wire and hand off. renounceOwnership (→ zero) is
always permitted.


```solidity
function transferOwnership(address newOwner) public virtual override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOwner`|`address`|The proposed owner. Once the registry is bound, must be the canonical DAO or `address(0)`; before binding, any address (so Bootstrap can wire and hand off).|


## Errors
### OwnerMustBeDAOOrZero
Thrown when, after the auth registry is bound, ownership transfer targets an address
that is neither the canonical DAO nor `address(0)`.


```solidity
error OwnerMustBeDAOOrZero();
```

