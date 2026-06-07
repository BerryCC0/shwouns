# IGovernanceRewardsForDAO
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOLogic.sol)

**Title:**
Shwouns DAO Logic — facade contract

Thin facade over ShwounsDAOProposals library. Holds the canonical storage
(NounsDAO-style Storage struct accessed via the library). External entry
points delegate to the library where the real logic lives.

Minimal interface to GR for the wiring this contract needs.

MVP: governance lifecycle only. Admin / candidates / signed proposals /
objection period land in follow-up turns.


## Functions
### allocateProposalReward

Reserve a proposal's voter reward pool (called inside finalize).


```solidity
function allocateProposalReward(uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The finalized proposal.|


### refundGas

Refund a voter's gas for a refundable vote (capped by GR).


```solidity
function refundGas(address voter, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`voter`|`address`|The voter to refund.|
|`amount`|`uint256`|The requested refund amount.|


