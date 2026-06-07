# IEscrowImplLike
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/Bootstrap.sol)

Minimal ProposalEscrow implementation surface used by the immutable-matrix check.


## Functions
### daoLogic

The DAOLogic baked into the escrow impl. @return The DAOLogic address.


```solidity
function daoLogic() external view returns (address);
```

### residualSink

The residual sink baked into the escrow impl. @return The sink address.


```solidity
function residualSink() external view returns (address);
```

