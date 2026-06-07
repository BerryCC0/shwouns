# IDAOLogicForRewards
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/rewards/GovernanceRewards.sol)

**Title:**
GovernanceRewards — accumulator + voter incentive distribution + gas refunds

Receives auction proceeds (Phase 3). In Phase 5 also distributes:
- **Voter incentives**: per-proposal reward pool divvied pro-rata by votes among For/Against
voters who hold an approved GI NFT.
- **Refundable votes**: gas refunds when DAOLogic invokes castRefundableVote.
Architecture:
- DAOLogic calls allocateProposalReward(proposalId) inside finalize() — sets aside
`proposalRewardAmount` for that proposal.
- Voters call claimVotingReward(proposalId, giTokenId) — eligibility check via
ApprovalRegistry, pro-rata share calculation against DAOLogic's vote totals.
- DAOLogic calls refundGas(voter, amount) when castRefundableVote fires — capped to
prevent griefing.
Funding flow: auction proceeds → GR balance. Mint proceeds from GI NFT → GR balance
(when GR is set as GI NFT owner). Out: voter rewards (lazy, per-claim), gas refunds.

Minimal interface for the bits of DAOLogic that GR reads from. Uses *Unpacked
naming to avoid clashing with DAOLogic's existing struct-returning getReceipt.


## Functions
### getReceiptUnpacked

A voter's receipt for a proposal, in unpacked form.


```solidity
function getReceiptUnpacked(uint256 proposalId, address voter)
    external
    view
    returns (bool hasVoted, uint8 support, uint96 votes);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|
|`voter`|`address`|The voter address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`hasVoted`|`bool`|Whether the voter cast a vote.|
|`support`|`uint8`|The vote: 0=against, 1=for, 2=abstain.|
|`votes`|`uint96`|The voting weight recorded for the vote.|


### proposalVotes

A proposal's vote tallies.


```solidity
function proposalVotes(uint256 proposalId)
    external
    view
    returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`forVotes`|`uint256`|Total For votes.|
|`againstVotes`|`uint256`|Total Against votes.|
|`abstainVotes`|`uint256`|Total Abstain votes.|


