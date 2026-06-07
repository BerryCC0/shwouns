# Concept: Voter incentives

*Audience: the Shwouns community. For the mechanics + accounting, see
[flows/auction-and-rewards.md](../flows/auction-and-rewards.md); for the code, the
[reference](../reference/SUMMARY.md).*

## The one-sentence idea

Instead of a treasury, **auction money pays voters** — but only voters the DAO has approved, so the
rewards can't be farmed by sybils.

## Where the money comes from

100% of every auction's winning bid flows to a single contract, `GovernanceRewards`. (Mint fees from
the Governance Incentives NFT below flow there too.) This pool is what funds voter rewards and
optional gas refunds. There is no treasury skim.

## Who gets paid, and for what

When a proposal finishes executing, a fixed reward pool (0.1 ETH by default) is set aside for that
proposal's voters. **For** and **Against** voters can claim a share proportional to their voting
weight. **Abstain** voters earn nothing — the incentive rewards *taking a position*, not just showing
up.

You have 180 days to claim. Whatever isn't claimed by then can be returned to the general pool by
anyone.

## The anti-sybil gate: a two-stage design

If anyone could earn rewards just by voting, someone could split holdings across many wallets and farm
the pool. Shwouns gates eligibility in two stages:

1. **Open mint — the Governance Incentives (GI) NFT.** Anyone can mint one for a small fee (0.01 ETH
   default). Minting is permissionless and the fee flows to `GovernanceRewards`. Holding a GI NFT
   alone earns you *nothing*.
2. **DAO allowlist.** The DAO, by governance proposal, approves specific GI NFT token IDs. Only an
   approved token ID makes its holder eligible to claim voter rewards.

So eligibility = *the DAO has vouched for this specific identity*. The open mint keeps it permissionless
to participate; the allowlist keeps the DAO in control of who actually earns.

## Approval follows the NFT, not the wallet

A GI NFT's approval is tied to its **token ID**, not to whoever holds it. If you sell or transfer an
approved GI NFT, the approval goes with it to the new owner. This is intentional: the DAO is approving
a specific, auditable on-chain identity (an NFT), not a wallet address that could quietly change hands.
It also makes "eligibility" a transferable, legible thing.

To stop one approved NFT from being passed hand-to-hand to let many people claim the same proposal's
reward, the contract enforces **one claim per proposal per voter AND one claim per proposal per
approved token ID**.

## Gas refunds (optional)

Voters who don't want to pay gas can use a refundable vote, which reimburses their gas from the
rewards pool — capped per vote, and drawn only from funds not already reserved for someone's reward.
If the pool can't cover it, the vote still counts; the refund just isn't paid.

## Why this shape?

- It replaces Nouns' client-incentive system with something that rewards the behavior the DAO most
  wants: **informed, decisive voting.**
- It keeps participation **open** (anyone can mint and vote) while keeping reward eligibility **curated**
  (the DAO approves identities).
- It routes the protocol's only revenue stream (auctions) straight back to the people doing the
  governance work, with no treasury middleman.

The detailed reward math, claim flow, and the reserved-vs-unreserved accounting that keeps pools
always solvent are in [flows/auction-and-rewards.md](../flows/auction-and-rewards.md).
