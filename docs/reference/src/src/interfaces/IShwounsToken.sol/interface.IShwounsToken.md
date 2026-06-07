# IShwounsToken
[Git Source](https://github.com/BerryCC0/shwouns/blob/c3d3c49ecaba298c2a599310448a09b917927b54/src/interfaces/IShwounsToken.sol)

**Inherits:**
IERC721

**Title:**
Interface for ShwounsToken

Forked from INounsToken — uses IShwounsSeeder.Seed (no glasses) and
IShwounsDescriptorMinimal (no glassesCount).


## Functions
### mint

Mint the next Shwoun (and a founder Shwoun on the founder cadence). Minter only.


```solidity
function mint() external returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The id of the minted (auction) Shwoun.|


### burn

Burn a Shwoun. Minter only (retained for emergencies).


```solidity
function burn(uint256 tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id to burn.|


### dataURI

The data URI (on-chain JSON metadata) for a Shwoun.


```solidity
function dataURI(uint256 tokenId) external returns (string memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The Shwoun id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The data URI.|


### setMinter

Set the authorized minter. Owner only, until locked.


```solidity
function setMinter(address minter) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`minter`|`address`|The new minter address.|


### lockMinter

Permanently lock the minter. Owner only.


```solidity
function lockMinter() external;
```

### setDescriptor

Set the descriptor. Owner only, until locked.


```solidity
function setDescriptor(IShwounsDescriptorMinimal descriptor) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`descriptor`|`IShwounsDescriptorMinimal`|The new descriptor.|


### lockDescriptor

Permanently lock the descriptor. Owner only.


```solidity
function lockDescriptor() external;
```

### setSeeder

Set the seeder. Owner only, until locked.


```solidity
function setSeeder(IShwounsSeeder seeder) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`seeder`|`IShwounsSeeder`|The new seeder.|


### lockSeeder

Permanently lock the seeder. Owner only.


```solidity
function lockSeeder() external;
```

## Events
### ShwounCreated
Emitted when a Shwoun is minted, recording its trait seed.


```solidity
event ShwounCreated(uint256 indexed tokenId, IShwounsSeeder.Seed seed);
```

### ShwounBurned
Emitted when a Shwoun is burned.


```solidity
event ShwounBurned(uint256 indexed tokenId);
```

### FoundersDAOUpdated
Emitted when the founders DAO address changes.


```solidity
event FoundersDAOUpdated(address foundersDAO);
```

### MinterUpdated
Emitted when the authorized minter changes.


```solidity
event MinterUpdated(address minter);
```

### MinterLocked
Emitted when the minter is permanently locked.


```solidity
event MinterLocked();
```

### DescriptorUpdated
Emitted when the descriptor changes.


```solidity
event DescriptorUpdated(IShwounsDescriptorMinimal descriptor);
```

### DescriptorLocked
Emitted when the descriptor is permanently locked.


```solidity
event DescriptorLocked();
```

### SeederUpdated
Emitted when the seeder changes.


```solidity
event SeederUpdated(IShwounsSeeder seeder);
```

### SeederLocked
Emitted when the seeder is permanently locked.


```solidity
event SeederLocked();
```

