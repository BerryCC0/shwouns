# IAuthed
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/auction/ShwounsAuctionHouse.sol)

**Title:**
The Shwouns DAO auction house

Forked from NounsAuctionHouseV3 (nouns-monorepo @ main). Changes:
- Add UUPSUpgradeable for governance-driven upgrades
- Replace INounsToken with IShwounsToken
- Replace INounsAuctionHouseV3 with IShwounsAuctionHouse
- Add settable governanceRewards (locks after first set) — settlement proceeds go here
- Add settable vaultRegistry (locks after first set) — for createVaultFor on mint/settle
- No-bid path: Shwoun goes to governanceRewards (not burned). Vault still created.
- On mint: also create vaults for any concurrently-minted founder Shwouns
LICENSE
Inherits from Zora's AuctionHouse via Nouns' modifications:
https://github.com/ourzora/auction-house/blob/54a12ec1a6cf562e49f0a4917990474b11350a2d/contracts/AuctionHouse.sol
Original Copyright Zora, GPL-3.0. Modifications by Nounders DAO and the Shwouns project.

Candidate-implementation getter used by the A9 honest-upgrade safeguard.


## Functions
### governanceAuth

The auth registry a UUPS upgrade candidate reports (must match the canonical one).


```solidity
function governanceAuth() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The candidate implementation's `governanceAuth` address.|


