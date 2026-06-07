# IOwnableLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

**Title:**
Bootstrap — minimal generic operator-gated deployment coordinator (A10, audit F1/F2/F3)

A small, GENERIC coordinator that holds NO embedded contract creation code (the old
deploy-everything Bootstrap was 143KB — far over EIP-170, undeployable; audit F1). The
ephemeral deploy script supplies each contract's creation bytecode; Bootstrap CREATE2-
deploys it, so Bootstrap is `msg.sender` in every constructor and thus the transient
owner/admin/art-descriptor/auth-binder of the whole system — no permanent EOA ever holds
a role (A10.1). A single `finalizeBootstrap()` validates the complete wiring and atomically
hands every role to the DAO, then permanently disables itself.

Minimal Ownable surface: read owner + transfer it (used for ownership prechecks + handoff).

Security model (audit F2 — the old deploy()/finalize() were permissionless and front-runnable):
- `operator` is the trusted deployer, pinned to `msg.sender` at construction.
- `onlyOperator` gates deploy/execute/registerManifest/finalize.
- `notFinalized` is a one-way latch: after finalize, deploy/execute/registerManifest revert
forever, so no residual authority survives the handoff.
- `execute` may only target Bootstrap-deployed (`isRegistered`) contracts.
- `finalizeBootstrap` operates on a STORED manifest (not caller-supplied addresses), and
asserts ownership + every one-shot lock + the operational wiring + the IMMUTABLE/
constructor wiring matrix BEFORE the handoff, and the destination state AFTER — so a
wiring or omission mistake reverts a finalize, never silently strands or mis-wires a role.


## Functions
### owner

The current owner. @return The owner address.


```solidity
function owner() external view returns (address);
```

### transferOwnership

Transfer ownership. @param newOwner The new owner.


```solidity
function transferOwnership(address newOwner) external;
```

