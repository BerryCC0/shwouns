# Flow: Auction → proceeds → voter rewards

How a Shwoun is minted and auctioned, how 100% of proceeds fund the rewards accumulator, and how
voters claim incentives. Reference pages: `ShwounsAuctionHouse`, `GovernanceRewards`,
`GovernanceIncentivesNFT`, `ApprovalRegistry` in the [generated docs](../reference/SUMMARY.md).

## Auction + settlement

A new Shwoun is minted and auctioned each `duration` (24h). On settle, the Shwoun goes to the winner
(or to `GovernanceRewards` if there were no bids — it is **not** burned), and **100% of the winning
bid goes to `GovernanceRewards`**. There is no treasury cut. Every minted Shwoun (auction winner and
founder reward) gets its ERC-6551 vault deployed via the registry.

```mermaid
sequenceDiagram
    autonumber
    actor Bidder
    actor Settler as Anyone
    participant AH as ShwounsAuctionHouse
    participant Token as ShwounsToken
    participant VReg as ShwounsVaultRegistry
    participant GR as GovernanceRewards

    Note over AH: auction live for Shwoun N
    Bidder->>AH: createBid(N) [or createBid(N, clientId)]  payable
    Note over AH: must beat last bid by minBidIncrementPercentage<br/>late bid extends endTime by timeBuffer
    AH-->>Bidder: refund prior top bidder (WETH fallback)
    Settler->>AH: settleCurrentAndCreateNewAuction()
    alt had a winning bid
        AH->>Token: transferFrom(AH, winner, N)
        AH->>GR: 100% of winning bid (WETH fallback)
    else no bids
        AH->>GR: transferFrom(AH, GR, N)  (Shwoun, not burned)
    end
    AH->>Token: mint()  → Shwoun N+1 (+ founder Shwoun on cadence)
    AH->>VReg: createVaultFor(N+1)  (+ founder vault)
    Note over AH: emits AuctionSettled, AuctionCreated
```

Notes:
- **Founder cadence.** Every 10th Shwoun (ids 0, 10, 20, …) goes to the founders DAO, for the first
  1820 ids — mirroring Nouns. The auction house deploys the founder Shwoun's vault too.
- **Sanctions.** If a `sanctionsOracle` is configured, bids from sanctioned addresses revert.
- **Settlement history.** Per-Shwoun settlement data (price, winner, client id) is stored for
  off-chain analytics (`getSettlements`, `getPrices`, `biddingClient`).
- **Upgradeable.** The auction house is a UUPS proxy; upgrades flow only through an authenticated
  proposal escrow (see [escrow-execution.md](escrow-execution.md)).

## Where the money is

`GovernanceRewards` is the single accumulator. Inflows: auction proceeds, GI NFT mint proceeds, and
direct deposits. Outflows: per-proposal voter reward pools (lazy, per claim) and capped gas refunds.
Its accounting separates **reserved** funds (allocated reward pools that must stay claimable) from
**unreserved** balance (everything else) — gas refunds and owner sweeps may only touch unreserved
balance (M-01).

## Voter incentives: the two-stage gate

Earning a voter reward requires both halves of an anti-sybil gate (details in
[voter-incentives.md](../concepts/voter-incentives.md)):

1. **Mint** a `GovernanceIncentivesNFT` — open, permissionless, costs `mintPrice` (0.01 ETH default);
   proceeds flow to `GovernanceRewards`.
2. The DAO **approves** that specific token id in `ApprovalRegistry` (via a governance proposal).
   Approval is keyed by **token id, not holder** — it follows the NFT on transfer.

```mermaid
sequenceDiagram
    autonumber
    actor Anyone
    actor DAO as DAO (via proposal escrow)
    actor Voter
    participant GI as GovernanceIncentivesNFT
    participant AR as ApprovalRegistry
    participant GR as GovernanceRewards
    participant D as ShwounsDAOLogic

    Anyone->>GI: mint() payable
    GI->>GR: forward mint proceeds
    DAO->>AR: approve(giTokenId)  (or approveMany)
    Note over D: a proposal finalizes → D.finalize auto-calls:
    D->>GR: allocateProposalReward(proposalId)
    Note over GR: reserve proposalRewardAmount from unreserved balance<br/>set 180-day deadline
    Voter->>GR: claimVotingReward(proposalId, giTokenId)
    GR->>AR: isEligible(voter, giTokenId)?
    GR->>D: getReceiptUnpacked + proposalVotes
    Note over GR: must have voted For/Against (not Abstain)<br/>both voter+tokenId claim flags checked and set (H-03)
    GR-->>Voter: pro-rata share = pool × yourVotes / (for+against)
```

### Reward accounting rules

- The pool is split **pro-rata by voting weight** among For + Against voters (Abstain earns nothing).
- A voter can claim **once** per proposal (`voterClaimed`), and each approved GI token id can claim
  **once** per proposal (`claimedByTokenId`, H-03) — so an approved NFT passed hand-to-hand cannot
  authorize many voters.
- Claims have a **180-day deadline**. After it, anyone can call `releaseExpiredRewardRemainder` to
  return the unclaimed remainder to unreserved balance (pro-rata pools are rarely fully claimed).
- Allocation never over-commits: `allocateProposalReward` reserves against *unreserved* balance, so
  the sum of live pools can never exceed the contract's ETH.

### Gas refunds

`castRefundableVote` records the vote and then asks `GovernanceRewards.refundGas` to reimburse the
voter, capped at `maxRefundPerVote` and drawn only from unreserved balance. It never reverts the vote
if the refund can't be paid.

## Events to index

Auction: `AuctionCreated`, `AuctionBid` (+ `AuctionBidWithClientId`), `AuctionExtended`,
`AuctionSettled` (+ `AuctionSettledWithClientId`). Rewards: `Deposited`, `ProposalRewardAllocated`,
`VoterRewardClaimed`, `GasRefunded`, `RewardRemainderReleased`. GI/approval: `Minted`,
`TokenIdApproved` / `TokenIdRevoked`.
