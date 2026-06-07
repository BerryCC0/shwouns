# LibExecutor
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/lib/LibExecutor.sol)


## Constants
### OP_CALL

```solidity
uint8 constant OP_CALL = 0
```


### OP_DELEGATECALL

```solidity
uint8 constant OP_DELEGATECALL = 1
```


### OP_CREATE

```solidity
uint8 constant OP_CREATE = 2
```


### OP_CREATE2

```solidity
uint8 constant OP_CREATE2 = 3
```


## Functions
### _execute


```solidity
function _execute(address to, uint256 value, bytes calldata data, uint8 operation) internal returns (bytes memory);
```

### _call


```solidity
function _call(address to, uint256 value, bytes memory data) internal returns (bytes memory result);
```

### _create


```solidity
function _create(uint256 value, bytes memory data) internal returns (address created);
```

### _create2


```solidity
function _create2(uint256 value, bytes32 salt, bytes calldata data) internal returns (address created);
```

