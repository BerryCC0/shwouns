# Concept: No treasury — per-Noun vaults

*Audience: the Shwouns community and newcomers. For the mechanics, see
[flows/governance-lifecycle.md](../flows/governance-lifecycle.md); for the code, the
[reference](../reference/SUMMARY.md).*

## The one-sentence idea

In mainline Nouns, all the money sits in one treasury that the DAO spends from. In Shwouns, **each
Noun carries its own wallet**, the holder controls it, and the DAO can only pull a fair share from
those wallets when a proposal actually passes.

## Why do this?

Standard Nouns ties two things together: holding a Noun gives you a vote, *and* your auction payment
goes into a shared pot the DAO controls. Shwouns separates them:

- **Holding a Shwoun makes you a voter.** That's it — governance authority.
- **Funding your vault is a separate, opt-in choice.** It's an act of conviction, not a requirement.

The bet is that decoupling "who governs" from "whose money is at stake" produces healthier dynamics:
nobody's capital is committed to the collective by default, and people fund the things they believe
in by choosing to keep their vaults funded.

## What's a vault, concretely?

Every Shwoun is permanently paired with a smart-contract wallet called a **Vault** (built on the
[ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) "token-bound account" standard). The vault is
created automatically when the Shwoun is minted. Whoever owns the Shwoun controls its vault and can:

- deposit and withdraw ETH or any ERC-20, anytime;
- delegate management to another address (e.g. a warm/cold wallet split, a council multisig, or a
  yield manager) without giving up ownership;
- use the vault as a normal smart-contract wallet — put assets to work in DeFi, bridge them, etc.

When you sell or transfer your Shwoun, its vault goes with it (the new holder controls it). The vault
is **non-upgradeable** and the DAO can never freeze it or seize its contents outright.

## How does the DAO ever spend, then?

When a proposal passes and is queued, the protocol:

1. takes a **snapshot** of which funded vaults exist;
2. **collects** each vault's *pro-rata share* of the amount the proposal requested — proportional to
   how much that vault holds;
3. **executes** the proposal using those collected funds, from a one-time escrow built just for that
   proposal.

So a proposal asking for 10 ETH draws proportionally from everyone's funded vaults, not from one
treasury. Bigger funded vaults contribute more; empty vaults contribute nothing.

## "But I can just withdraw before a proposal collects?"

Yes — and that's intended. **You are sovereign over your own capital.** Between a proposal's snapshot
and the moment your vault is actually collected, you can withdraw. If you do, your contribution to
that proposal simply shrinks (it's recorded as a "shortfall" and logged, not treated as an error).

The flip side: a proposal might end up under-funded if enough holders withdraw. Execution is
**all-or-nothing** — the proposal only runs if the requested amount was actually gathered (anyone can
"top up" the difference to push it through). A proposal that can't gather its funds simply doesn't
execute, and everything collected is returned to the vaults it came from.

This makes funding a proposal a continuous expression of support: keeping your vault funded through a
proposal's collection *is* your vote of confidence with capital, distinct from your governance vote.

## What about auction proceeds?

They don't go to a treasury either. 100% of each winning bid flows to a rewards contract that pays
**voter incentives** — see [voter-incentives.md](voter-incentives.md).

## Trade-offs to be honest about

- **No guaranteed war chest.** The DAO can't rely on a fixed treasury balance; proposal funding
  depends on holders choosing to keep vaults funded.
- **Funding is best-effort.** A proposal can be under-funded if holders withdraw; it then needs a
  top-up or it doesn't execute.
- **More moving parts at execution.** Snapshot → collect → finalize is paged across vaults, so
  spending a proposal is a multi-step (though permissionless) process rather than one timelock call.

These are deliberate consequences of putting capital sovereignty first. The mechanics that make it
safe (per-proposal isolation, fail-closed authorization) are in
[architecture/auth-and-trust.md](../architecture/auth-and-trust.md).
