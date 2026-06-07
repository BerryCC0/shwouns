# ShwounsDAOEvents
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/governance/ShwounsDAOInterfaces.sol)


## Events
### ProposalCreated
Emitted when a proposal is created.


```solidity
event ProposalCreated(
    uint256 id,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    string description
);
```

### VoteCast
Emitted on each vote cast, with the voter's weight and reason.


```solidity
event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 votes, string reason);
```

### ProposalCanceled
Emitted when a proposal is canceled.


```solidity
event ProposalCanceled(uint256 id);
```

### ProposalQueued
Emitted when a proposal is queued.


```solidity
event ProposalQueued(uint256 id);
```

### ProposalSnapshotted
Emitted once per asset when a proposal's snapshot phase completes.


```solidity
event ProposalSnapshotted(uint256 indexed id, address indexed asset, uint256 totalSnapshotBalance);
```

### ProposalCollected
Emitted when a proposal's collect phase completes.


```solidity
event ProposalCollected(uint256 indexed id);
```

### ProposalExecuted
Emitted when a proposal's actions execute successfully.


```solidity
event ProposalExecuted(uint256 id);
```

### ProposalVetoed
Emitted when a proposal is vetoed.


```solidity
event ProposalVetoed(uint256 id);
```

### VaultSnapshotted
Emitted per (proposal, vault, asset) during recordSnapshot.


```solidity
event VaultSnapshotted(
    uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 balance
);
```

### AssetCollectedFromVault
Emitted per (proposal, vault, asset) during collect when amount actually pulled.


```solidity
event AssetCollectedFromVault(
    uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 amount
);
```

### ShortfallRecorded
Emitted when a vault's actual balance at collect time is less than its snapshot share.


```solidity
event ShortfallRecorded(
    uint256 indexed proposalId, uint256 indexed shwounId, address indexed asset, uint256 missingAmount
);
```

### FinalizeAttemptFailed
Emitted when finalize() attempts and fails (proposal stays in Collected; can retry).


```solidity
event FinalizeAttemptFailed(uint256 indexed proposalId, uint256 actionIndex, bytes returnData);
```

### VotingDelaySet
Emitted when the voting delay changes.


```solidity
event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
```

### VotingPeriodSet
Emitted when the voting period changes.


```solidity
event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
```

### ProposalThresholdBPSSet
Emitted when the proposal threshold BPS changes.


```solidity
event ProposalThresholdBPSSet(uint256 oldProposalThresholdBPS, uint256 newProposalThresholdBPS);
```

### NewAdmin
Emitted when the admin changes.


```solidity
event NewAdmin(address oldAdmin, address newAdmin);
```

### NewPendingAdmin
Emitted when the pending admin changes.


```solidity
event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
```

### NewVetoer
Emitted when the vetoer changes (including burn-to-zero).


```solidity
event NewVetoer(address oldVetoer, address newVetoer);
```

### MinQuorumVotesBPSSet
Emitted when the minimum quorum BPS changes.


```solidity
event MinQuorumVotesBPSSet(uint16 oldMinQuorumVotesBPS, uint16 newMinQuorumVotesBPS);
```

### MaxQuorumVotesBPSSet
Emitted when the maximum quorum BPS changes.


```solidity
event MaxQuorumVotesBPSSet(uint16 oldMaxQuorumVotesBPS, uint16 newMaxQuorumVotesBPS);
```

### QuorumCoefficientSet
Emitted when the quorum coefficient changes.


```solidity
event QuorumCoefficientSet(uint32 oldQuorumCoefficient, uint32 newQuorumCoefficient);
```

