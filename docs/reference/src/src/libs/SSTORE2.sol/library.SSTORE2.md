# SSTORE2
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/libs/SSTORE2.sol)

**Authors:**
Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SSTORE2.sol), Modified from 0xSequence (https://github.com/0xSequence/sstore2/blob/master/contracts/SSTORE2.sol)

Read and write to persistent storage at a fraction of the cost.


## Constants
### DATA_OFFSET

```solidity
uint256 internal constant DATA_OFFSET = 1
```


## Functions
### write


```solidity
function write(bytes memory data) internal returns (address pointer);
```

### read


```solidity
function read(address pointer) internal view returns (bytes memory);
```

### read


```solidity
function read(address pointer, uint256 start) internal view returns (bytes memory);
```

### read


```solidity
function read(address pointer, uint256 start, uint256 end) internal view returns (bytes memory);
```

### readBytecode


```solidity
function readBytecode(address pointer, uint256 start, uint256 size) private view returns (bytes memory data);
```

