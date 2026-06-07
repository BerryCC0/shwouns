# SandboxExecutor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/abstract/execution/SandboxExecutor.sol)

**Inherits:**
[ISandboxExecutor](/src/vault/interfaces/ISandboxExecutor.sol/interface.ISandboxExecutor.md)

**Title:**
Sandbox Executor

Allows the sandbox contract for an account to execute low-level operations


## Functions
### _requireFromSandbox

Ensures that a given caller is the sandbox for this account


```solidity
function _requireFromSandbox() internal view;
```

### extcall

Allows the sandbox contract to execute low-level calls from this account


```solidity
function extcall(address to, uint256 value, bytes calldata data) external returns (bytes memory result);
```

### extcreate

Allows the sandbox contract to create contracts on behalf of this account


```solidity
function extcreate(uint256 value, bytes calldata bytecode) external returns (address);
```

### extcreate2

Allows the sandbox contract to create deterministic contracts on behalf of this account


```solidity
function extcreate2(uint256 value, bytes32 salt, bytes calldata bytecode) external returns (address);
```

### extsload

Allows arbitrary storage reads on this account from external contracts


```solidity
function extsload(bytes32 slot) external view returns (bytes32 value);
```

