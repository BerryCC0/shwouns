# GovernanceRewards
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/rewards/GovernanceRewards.sol)

**Inherits:**
[GovernedOwnable](/src/governance/GovernedOwnable.sol/abstract.GovernedOwnable.md), ERC721Holder, ERC1155Holder


## Constants
### CLAIM_PERIOD
How long after allocation voters may claim. Settled at 180 days.


```solidity
uint256 public constant CLAIM_PERIOD = 180 days
```


## State Variables
### dao
The DAOLogic proxy whose vote records and totals drive reward claims. Set once, locked.


```solidity
IDAOLogicForRewards public dao
```


### approvalRegistry
The allowlist consulted to verify a claimant's GI NFT is approved. Set once, locked.


```solidity
ApprovalRegistry public approvalRegistry
```


### daoLocked
True once `dao` has been set, after which it can never change.


```solidity
bool public daoLocked
```


### approvalRegistryLocked
True once `approvalRegistry` has been set, after which it can never change.


```solidity
bool public approvalRegistryLocked
```


### proposalRewardAmount
Reward pool allocated to each proposal that reaches finalize. Owner-settable.


```solidity
uint256 public proposalRewardAmount = 0.1 ether
```


### maxRefundPerVote
Max gas refund per castRefundableVote call (ETH). Prevents griefing.


```solidity
uint256 public maxRefundPerVote = 0.003 ether
```


### proposalRewardPool
ETH set aside for a given proposal's voter rewards (the original pool, for pro-rata).


```solidity
mapping(uint256 => uint256) public proposalRewardPool
```


### remainingRewardPool
Unclaimed remainder of a proposal's pool (decremented as voters claim). M-01.


```solidity
mapping(uint256 => uint256) public remainingRewardPool
```


### totalReserved
Sum of all unclaimed allocations across proposals — funds that are RESERVED and may
not be re-allocated, gas-refunded, or swept. M-01.


```solidity
uint256 public totalReserved
```


### voterClaimed
Per-(proposal, voter) claimed flag (stops one voter claiming twice via two NFTs).


```solidity
mapping(uint256 => mapping(address => bool)) public voterClaimed
```


### claimedByTokenId
Per-(proposal, giTokenId) claimed flag (H-03: stops one approved NFT, passed
hand-to-hand, from authorizing many voters). Both flags are checked AND set.


```solidity
mapping(uint256 => mapping(uint256 => bool)) public claimedByTokenId
```


### rewardDeadline
Per-proposal claim deadline (block.timestamp). After it, claims revert and the
unclaimed remainder can be released permissionlessly.


```solidity
mapping(uint256 => uint256) public rewardDeadline
```


### lifetimeETHReceived
Total ETH ever received via deposit() / receive() / NFT mint forwarding.


```solidity
uint256 public lifetimeETHReceived
```


## Functions
### constructor


```solidity
constructor(address _governanceAuth) GovernedOwnable(_governanceAuth);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_governanceAuth`|`address`|The GovernanceAuthRegistry (so DAO governance can sweep / configure via an authenticated proposal escrow). address(0) reduces to plain Ownable.|


### onlyDAO


```solidity
modifier onlyDAO() ;
```

### receive


```solidity
receive() external payable;
```

### deposit

Deposit ETH into the rewards accumulator (identical to a plain transfer).


```solidity
function deposit() external payable;
```

### setDAOLogic

Set the DAOLogic reference. Callable once, then locked.


```solidity
function setDAOLogic(address _dao) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dao`|`address`|The DAOLogic proxy address.|


### setApprovalRegistry

Set the ApprovalRegistry reference. Callable once, then locked.


```solidity
function setApprovalRegistry(ApprovalRegistry _registry) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`ApprovalRegistry`|The ApprovalRegistry address.|


### setProposalRewardAmount

Set the per-proposal reward pool size. Governable (owner = DAO via the active escrow).


```solidity
function setProposalRewardAmount(uint256 newAmount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newAmount`|`uint256`|The new reward amount in wei.|


### setMaxRefundPerVote

Set the per-vote gas-refund cap. Governable (owner = DAO via the active escrow).


```solidity
function setMaxRefundPerVote(uint256 newAmount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newAmount`|`uint256`|The new per-vote cap in wei.|


### allocateProposalReward

Set aside `proposalRewardAmount` ETH for the given proposal's voter rewards.
Called by DAOLogic inside finalize(). M-01: allocates against UNRESERVED balance
(balance - totalReserved) so pools can never collectively exceed the contract's ETH;
the allocation is reserved and a 180-day claim deadline is set.


```solidity
function allocateProposalReward(uint256 proposalId) external onlyDAO;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal being finalized.|


### claimVotingReward

Claim your pro-rata voter reward for a proposal. You must hold an approved
GI NFT (passed as giTokenId) and have voted For or Against on the proposal.


```solidity
function claimVotingReward(uint256 proposalId, uint256 giTokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The finalized proposal to claim against.|
|`giTokenId`|`uint256`|The approved GI NFT token id you own and are claiming with.|


### releaseExpiredRewardRemainder

After a proposal's 180-day claim deadline, permissionlessly release its UNCLAIMED
remainder back to unreserved balance (pro-rata pools are rarely fully claimed; this
avoids locking reserved-unclaimed ETH behind an owner who may never act). M-01.


```solidity
function releaseExpiredRewardRemainder(uint256 proposalId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The proposal whose expired remainder to release.|


### refundGas

Send a gas refund to a voter. Only callable by DAOLogic. Refund is capped
at `maxRefundPerVote` regardless of `amount`. If GR has insufficient balance,
the refund silently sends whatever's available — never reverts (because the
vote was already recorded; we don't want to undo it).


```solidity
function refundGas(address voter, uint256 amount) external onlyDAO;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`voter`|`address`|The voter to refund.|
|`amount`|`uint256`|The requested refund (capped at `maxRefundPerVote` and unreserved balance).|


### onERC721Received

ERC-721 receiver hook. Accepts any incoming NFT (e.g. a no-bid auction's Shwoun).


```solidity
function onERC721Received(
    address,
    /*operator*/
    address from,
    uint256 tokenId,
    bytes memory /*data*/
)
    public
    override
    returns (bytes4);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`||
|`from`|`address`|The address the NFT came from.|
|`tokenId`|`uint256`|The id of the NFT received.|
|`<none>`|`bytes`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4`|The ERC-721 receiver magic value.|


### transferShwoun

Transfer a held Shwoun out. Governable (owner = DAO via the active escrow).


```solidity
function transferShwoun(IERC721 shwouns, uint256 shwounId, address to) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwouns`|`IERC721`|The Shwouns token contract.|
|`shwounId`|`uint256`|The Shwoun id to transfer.|
|`to`|`address`|The recipient.|


### sweepETH

Sweep unreserved ETH out. Reverts if `amount` exceeds the unreserved balance.
Governable (owner = DAO via the active escrow).


```solidity
function sweepETH(address payable to, uint256 amount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address payable`|The recipient.|
|`amount`|`uint256`|The amount of ETH to sweep.|


### sweepERC20

Sweep an ERC-20 balance out. Governable (owner = DAO via the active escrow).


```solidity
function sweepERC20(address token, address to, uint256 amount) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-20 to sweep.|
|`to`|`address`|The recipient.|
|`amount`|`uint256`|The amount to sweep.|


### sweepERC721

Generic ERC-721 sweep (A8) — lets governance recover NFT residuals routed here by
rescueFromEscrow. Governance-gated (owner = DAO via the escrow).


```solidity
function sweepERC721(address token, uint256 tokenId, address to) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-721 collection.|
|`tokenId`|`uint256`|The token id to sweep.|
|`to`|`address`|The recipient.|


### sweepERC1155

Generic ERC-1155 sweep (A8). Governance-gated.


```solidity
function sweepERC1155(address token, uint256 id, uint256 amount, address to) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The ERC-1155 collection.|
|`id`|`uint256`|The token id.|
|`amount`|`uint256`|The amount to sweep.|
|`to`|`address`|The recipient.|


### ethBalance

The contract's current ETH balance.


```solidity
function ethBalance() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The ETH balance in wei.|


## Events
### Deposited
Emitted on each ETH inflow (auction proceeds, mint forwarding, direct deposit).


```solidity
event Deposited(address indexed asset, address indexed from, uint256 amount);
```

### ShwounReceived
Emitted when a Shwoun NFT is received (e.g. a no-bid auction routes the Shwoun here).


```solidity
event ShwounReceived(uint256 indexed shwounId, address indexed from);
```

### ShwounTransferred
Emitted when a held Shwoun is transferred out by governance.


```solidity
event ShwounTransferred(uint256 indexed shwounId, address indexed to);
```

### ETHSwept
Emitted when unreserved ETH is swept out by governance.


```solidity
event ETHSwept(address indexed to, uint256 amount);
```

### ERC20Swept
Emitted when an ERC-20 balance is swept out by governance.


```solidity
event ERC20Swept(address indexed token, address indexed to, uint256 amount);
```

### ERC721Swept
Emitted when an ERC-721 is swept out by governance.


```solidity
event ERC721Swept(address indexed token, address indexed to, uint256 tokenId);
```

### ERC1155Swept
Emitted when an ERC-1155 balance is swept out by governance.


```solidity
event ERC1155Swept(address indexed token, address indexed to, uint256 id, uint256 amount);
```

### DAOLogicSet
Emitted once when the DAOLogic reference is set and locked.


```solidity
event DAOLogicSet(address indexed dao);
```

### ApprovalRegistrySet
Emitted once when the ApprovalRegistry reference is set and locked.


```solidity
event ApprovalRegistrySet(address indexed registry);
```

### ProposalRewardAmountSet
Emitted when the per-proposal reward amount changes.


```solidity
event ProposalRewardAmountSet(uint256 oldAmount, uint256 newAmount);
```

### MaxRefundPerVoteSet
Emitted when the per-vote gas-refund cap changes.


```solidity
event MaxRefundPerVoteSet(uint256 oldAmount, uint256 newAmount);
```

### ProposalRewardAllocated
Emitted when a proposal's reward pool is reserved at finalize.


```solidity
event ProposalRewardAllocated(uint256 indexed proposalId, uint256 amount);
```

### VoterRewardClaimed
Emitted when a voter claims their pro-rata share of a proposal's reward pool.


```solidity
event VoterRewardClaimed(
    uint256 indexed proposalId, address indexed voter, uint256 indexed giTokenId, uint256 amount
);
```

### GasRefunded
Emitted on each gas-refund attempt; `sent` is false if nothing was paid.


```solidity
event GasRefunded(address indexed voter, uint256 amount, bool sent);
```

### RewardRemainderReleased
Emitted when an expired pool's unclaimed remainder is released back to unreserved balance.


```solidity
event RewardRemainderReleased(uint256 indexed proposalId, uint256 amount);
```

## Errors
### AlreadyLocked
Thrown when a one-time setter is called after it has been locked.


```solidity
error AlreadyLocked();
```

### InvalidAddress
Thrown when a setter is given a zero address.


```solidity
error InvalidAddress();
```

### NotDAO
Thrown when an `onlyDAO` function is called by an address other than `dao`.


```solidity
error NotDAO();
```

### InsufficientPool
Thrown when a reward pool lacks sufficient balance (reserved for future use).


```solidity
error InsufficientPool();
```

### NotEligible
Thrown when a claimant's GI NFT is not approved or not owned by them.


```solidity
error NotEligible();
```

### DidNotVote
Thrown when a claimant did not vote on the proposal.


```solidity
error DidNotVote();
```

### AbstainNotEligible
Thrown when a claimant's vote was Abstain (only For/Against earn rewards).


```solidity
error AbstainNotEligible();
```

### AlreadyClaimed
Thrown when this voter has already claimed for this proposal.


```solidity
error AlreadyClaimed();
```

### AlreadyClaimedByTokenId
Thrown when this GI token id has already claimed for this proposal (H-03).


```solidity
error AlreadyClaimedByTokenId();
```

### NoVotesYet
Thrown when a proposal has zero eligible (For+Against) votes.


```solidity
error NoVotesYet();
```

### RewardClaimExpired
Thrown when claiming after the 180-day reward deadline.


```solidity
error RewardClaimExpired();
```

### RewardClaimNotExpired
Thrown when releasing a remainder before the reward deadline has passed.


```solidity
error RewardClaimNotExpired();
```

### ExceedsUnreserved
Thrown when a sweep would exceed the unreserved (non-pool) balance.


```solidity
error ExceedsUnreserved();
```

