# ShwounsToken
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/token/ShwounsToken.sol)

**Inherits:**
[IShwounsToken](/src/interfaces/IShwounsToken.sol/interface.IShwounsToken.md), [GovernedOwnable](/src/governance/GovernedOwnable.sol/abstract.GovernedOwnable.md), [ERC721Checkpointable](/src/token/base/ERC721Checkpointable.sol/abstract.ERC721Checkpointable.md)

**Title:**
The Shwouns ERC-721 token

Forked from nouns-monorepo NounsToken.sol. Changes:
- Glasses field removed from Seed (matching IShwounsSeeder)
- OpenSea IProxyRegistry whitelist removed (Seaport-era; deprecated pattern)
- "nounders" renamed to "founders" for clarity
- Every 10th Noun goes to foundersDAO for the first 1820 IDs (matches Nouns)
- Vault auto-creation is NOT done here; AuctionHouse calls vaultRegistry.createVaultFor
after settlement. Token has no dependency on VaultRegistry.


## Constants
### FOUNDERS_REWARD_ENDS
Last token ID at which founders receive a reward. Matches Nouns' 1820
(5 years × 365 days at 1 founder Noun per 10 daily auctions = 1820).


```solidity
uint256 public constant FOUNDERS_REWARD_ENDS = 1820
```


## State Variables
### foundersDAO
The founders DAO address. Receives every 10th Shwoun up to FOUNDERS_REWARD_ENDS.


```solidity
address public foundersDAO
```


### minter
The only address authorized to mint (the AuctionHouse).


```solidity
address public minter
```


### descriptor
The descriptor that renders tokenURI / SVG from a seed.


```solidity
IShwounsDescriptorMinimal public descriptor
```


### seeder
The seeder that generates each Shwoun's trait seed.


```solidity
IShwounsSeeder public seeder
```


### isMinterLocked
True once the minter is permanently locked.


```solidity
bool public isMinterLocked
```


### isDescriptorLocked
True once the descriptor is permanently locked.


```solidity
bool public isDescriptorLocked
```


### isSeederLocked
True once the seeder is permanently locked.


```solidity
bool public isSeederLocked
```


### seeds
The trait seed for each Shwoun id, set at mint.


```solidity
mapping(uint256 => IShwounsSeeder.Seed) public seeds
```


### _currentShwounId

```solidity
uint256 private _currentShwounId
```


### _contractURIHash

```solidity
string private _contractURIHash = ""
```


## Functions
### whenMinterNotLocked


```solidity
modifier whenMinterNotLocked() ;
```

### whenDescriptorNotLocked


```solidity
modifier whenDescriptorNotLocked() ;
```

### whenSeederNotLocked


```solidity
modifier whenSeederNotLocked() ;
```

### onlyFoundersDAO


```solidity
modifier onlyFoundersDAO() ;
```

### onlyMinter


```solidity
modifier onlyMinter() ;
```

### constructor


```solidity
constructor(
    address _foundersDAO,
    address _minter,
    IShwounsDescriptorMinimal _descriptor,
    IShwounsSeeder _seeder,
    address _governanceAuth
) ERC721("Shwouns", "SHWN") GovernedOwnable(_governanceAuth);
```

### contractURI

The contract-level metadata URI (ipfs:// + the stored hash).


```solidity
function contractURI() public view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract URI.|


### setContractURIHash

Set the IPFS hash of the contract-level metadata. Owner only.


```solidity
function setContractURIHash(string memory newContractURIHash) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newContractURIHash`|`string`|The new IPFS content hash.|


### mint

Mint a Shwoun to the minter, with a possible founders reward Shwoun.

Founders reward Shwouns are minted every 10 IDs, starting at 0, until
FOUNDERS_REWARD_ENDS have been minted (5 years at 1/day auctions).


```solidity
function mint() public override onlyMinter returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The id of the minted (auction) Shwoun.|


### burn

Burn a Shwoun. Restricted to the minter (the AuctionHouse).
In normal operation the AuctionHouse routes no-bid Shwouns to GovernanceRewards
via transferFrom rather than calling burn. This is retained for emergencies.


```solidity
function burn(uint256 shwounId) public override onlyMinter;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shwounId`|`uint256`|The Shwoun id to burn.|


### tokenURI

The token URI for a Shwoun (delegates to the descriptor with the token's seed).


```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token URI.|


### dataURI

The data URI (on-chain JSON metadata) for a Shwoun.


```solidity
function dataURI(uint256 tokenId) public view override returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The data URI.|


### setFoundersDAO

Transfer the founders DAO role. Callable only by the current founders DAO.


```solidity
function setFoundersDAO(address _foundersDAO) external onlyFoundersDAO;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_foundersDAO`|`address`|The new founders DAO address.|


### setMinter

Set the authorized minter. Owner only, until locked.


```solidity
function setMinter(address _minter) external override onlyOwner whenMinterNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minter`|`address`||


### lockMinter

Permanently lock the minter. Owner only.


```solidity
function lockMinter() external override onlyOwner whenMinterNotLocked;
```

### setDescriptor

Set the descriptor. Owner only, until locked.


```solidity
function setDescriptor(IShwounsDescriptorMinimal _descriptor) external override onlyOwner whenDescriptorNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_descriptor`|`IShwounsDescriptorMinimal`||


### lockDescriptor

Permanently lock the descriptor. Owner only.


```solidity
function lockDescriptor() external override onlyOwner whenDescriptorNotLocked;
```

### setSeeder

Set the seeder. Owner only, until locked.


```solidity
function setSeeder(IShwounsSeeder _seeder) external override onlyOwner whenSeederNotLocked;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_seeder`|`IShwounsSeeder`||


### lockSeeder

Permanently lock the seeder. Owner only.


```solidity
function lockSeeder() external override onlyOwner whenSeederNotLocked;
```

### _mintTo

Mint a Shwoun with `shwounId` to the provided `to` address.


```solidity
function _mintTo(address to, uint256 shwounId) internal returns (uint256);
```

