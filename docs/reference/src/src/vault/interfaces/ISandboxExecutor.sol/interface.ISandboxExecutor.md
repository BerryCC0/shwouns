# ISandboxExecutor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/interfaces/ISandboxExecutor.sol)


## Functions
### extcall


```solidity
function extcall(address to, uint256 value, bytes calldata data) external returns (bytes memory result);
```

### extcreate


```solidity
function extcreate(uint256 value, bytes calldata data) external returns (address);
```

### extcreate2


```solidity
function extcreate2(uint256 value, bytes32 salt, bytes calldata bytecode) external returns (address);
```

### extsload


```solidity
function extsload(bytes32 slot) external view returns (bytes32 value);
```

