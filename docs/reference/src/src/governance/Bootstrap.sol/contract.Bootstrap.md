# Bootstrap
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)


## Constants
### operator
The trusted deployer. Pinned at construction; the only address that may drive Bootstrap.


```solidity
address public immutable operator
```


## State Variables
### finalized
One-way latch. Once true, deploy/execute/registerManifest revert forever.


```solidity
bool public finalized
```


### manifestRegistered
Whether registerManifest has run (finalize requires it).


```solidity
bool public manifestRegistered
```


### isRegistered
Contracts CREATE2-deployed by this Bootstrap. `execute` may only target these.


```solidity
mapping(address => bool) public isRegistered
```


### manifest
The stored deployment manifest (set once).


```solidity
DeploymentManifest public manifest
```


## Functions
### constructor


```solidity
constructor() ;
```

### onlyOperator


```solidity
modifier onlyOperator() ;
```

### notFinalized


```solidity
modifier notFinalized() ;
```

### deploy

CREATE2-deploy supplied creation code (constructor args already appended by the
caller). Because Bootstrap executes the CREATE2, `msg.sender` in the constructor is
Bootstrap → every Ownable it deploys is owned by Bootstrap (A10.1: no EOA owns roles).


```solidity
function deploy(bytes calldata creationCode, bytes32 salt)
    external
    onlyOperator
    notFinalized
    returns (address addr);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`creationCode`|`bytes`|The full creation bytecode with constructor args already appended.|
|`salt`|`bytes32`|The CREATE2 salt.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|The deployed contract address.|


### execute

Drive an `onlyOwner`/`onlyAdmin`/`onlyDescriptor` call on a Bootstrap-deployed
contract (wiring + art load/lock). Restricted to registered targets and bubbles the
target's revert. Non-payable: no protocol wiring needs value, and the contracts are
funded later by auctions/governance.


```solidity
function execute(address target, bytes calldata data) external onlyOperator notFinalized returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`target`|`address`|The registered (Bootstrap-deployed) contract to call.|
|`data`|`bytes`|The calldata to forward.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|The target's return data.|


### executeBatch

Batched `execute` — for the ~20-30 art-load ops in a few txs. Same registered-target
+ revert-bubble semantics per call.


```solidity
function executeBatch(address[] calldata targets, bytes[] calldata datas) external onlyOperator notFinalized;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`targets`|`address[]`|The registered contracts to call (parallel to `datas`).|
|`datas`|`bytes[]`|The calldata to forward to each target.|


### registerManifest

Commit the complete deployment manifest. Each address must be Bootstrap-deployed
(isRegistered), nonzero, and pairwise-distinct — so the exact set finalize checks is
fixed up front and nothing can be omitted, duplicated, or foreign.


```solidity
function registerManifest(DeploymentManifest calldata m) external onlyOperator notFinalized;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`m`|`DeploymentManifest`|The complete deployment manifest (every address Bootstrap-deployed + distinct).|


### finalizeBootstrap

Validate the complete wiring on the STORED manifest, then atomically hand every role
to the DAO and permanently disable Bootstrap. Reverts (changing nothing but `finalized`,
which a revert rolls back) if any precheck fails — so a mis-wire can never be handed off.


```solidity
function finalizeBootstrap() external onlyOperator notFinalized;
```

### _checkOwnership

Every manifest Ownable (the 7 role-holders) must currently be owned by Bootstrap.


```solidity
function _checkOwnership() internal view;
```

### _checkLocksAndWiring

Every settable wiring relationship AND its one-shot lock (audit plan-review2 F2 / F3):
a successful finalize guarantees not just ownership but that the system is fully, lockably
wired and the art is finalized — so nothing can be handed off half-configured.


```solidity
function _checkLocksAndWiring() internal view;
```

### _checkImmutableMatrix

The IMMUTABLE / constructor wiring matrix (audit plan-review4): these are fixed at
construction and CANNOT be repaired post-deploy, so a mis-constructed dependency would be
handed off permanently broken. Assert them all against the stored manifest.


```solidity
function _checkImmutableMatrix() internal view;
```

### _handoffToDAO

The A10.5-validated handoff ordering. Bind the registry FIRST (so governed contracts
resolve the canonical DAO during the atomic handoff), KICK OFF auction #1 while Bootstrap
still owns the auction house (post-handoff, unpausing would need voting power that only
auctions mint — a deadlock), THEN transfer every Ownable to the DAO and set DAO admin.


```solidity
function _handoffToDAO() internal;
```

### _assertHandoffComplete

After the handoff: every role-holder is DAO-owned, the DAO is its own admin, the registry
is bound, and the auction is running. Bootstrap now holds NO role; `finalized` bars re-entry.


```solidity
function _assertHandoffComplete() internal view;
```

## Events
### Deployed
Emitted for each CREATE2 deployment Bootstrap performs.


```solidity
event Deployed(address indexed addr, bytes32 indexed salt);
```

### Executed
Emitted for each successful `execute`/`executeBatch` call against a registered target.


```solidity
event Executed(address indexed target);
```

### ManifestRegistered
Emitted when the deployment manifest is committed.


```solidity
event ManifestRegistered(address indexed dao);
```

### Finalized
Emitted when the one-shot handoff completes and Bootstrap is permanently disabled.


```solidity
event Finalized(address indexed dao);
```

## Errors
### NotOperator
Thrown when a non-operator calls an operator-gated function.


```solidity
error NotOperator();
```

### AlreadyFinalized
Thrown when any driving function is called after finalize.


```solidity
error AlreadyFinalized();
```

### NotRegistered
Thrown when `execute`/`executeBatch` targets a non-Bootstrap-deployed address.


```solidity
error NotRegistered(address target);
```

### DeployFailed
Thrown when a CREATE2 deployment returns the zero address.


```solidity
error DeployFailed();
```

### ManifestAlreadySet
Thrown when registerManifest is called more than once.


```solidity
error ManifestAlreadySet();
```

### ManifestNotSet
Thrown when finalize is called before the manifest is registered.


```solidity
error ManifestNotSet();
```

### BatchLengthMismatch
Thrown when executeBatch is given targets/datas arrays of unequal length.


```solidity
error BatchLengthMismatch();
```

## Structs
### DeploymentManifest
The complete, typed set of addresses finalizeBootstrap operates on. Set once via
registerManifest. Role-holders (transferred to the DAO) PLUS the impls/peripherals the
wiring asserts reference. NOT caller-supplied at finalize (audit plan-review F2): the
exact set is committed up front so nothing can be silently omitted.


```solidity
struct DeploymentManifest {
    // Role-holders — every one is an Ownable transferred to the DAO at handoff.
    address dao; // DAO proxy (admin handed over via setAdminToDAO, not transferOwnership)
    address authRegistry; // GovernanceAuthRegistry (binder is immutable; not Ownable)
    address auctionHouse;
    address token;
    address descriptor;
    address vaultRegistry;
    address rewards;
    address giNFT;
    address approvalRegistry;
    // Impls/peripherals referenced by the wiring asserts (NOT transferred — stateless or non-Ownable).
    address art;
    address vaultImpl;
    address proposalEscrowImpl;
}
```

