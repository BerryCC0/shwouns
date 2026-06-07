# LibSandbox
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/vault/lib/LibSandbox.sol)


## Constants
### header

```solidity
bytes public constant header = hex"604380600d600039806000f3fe73"
```


### footer

```solidity
bytes public constant footer =
    hex"3314601d573d3dfd5b363d3d373d3d6014360360143d5160601c5af43d6000803e80603e573d6000fd5b3d6000f3"
```


## Functions
### bytecode


```solidity
function bytecode(address owner) internal pure returns (bytes memory);
```

### sandbox


```solidity
function sandbox(address owner) internal view returns (address);
```

### deploy


```solidity
function deploy(address owner) internal;
```

