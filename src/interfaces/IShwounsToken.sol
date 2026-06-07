// SPDX-License-Identifier: GPL-3.0

/// @title Interface for ShwounsToken
/// @notice Forked from INounsToken — uses IShwounsSeeder.Seed (no glasses) and
///         IShwounsDescriptorMinimal (no glassesCount).

pragma solidity ^0.8.6;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IShwounsDescriptorMinimal } from './IShwounsDescriptorMinimal.sol';
import { IShwounsSeeder } from './IShwounsSeeder.sol';

interface IShwounsToken is IERC721 {
    /// @notice Emitted when a Shwoun is minted, recording its trait seed.
    event ShwounCreated(uint256 indexed tokenId, IShwounsSeeder.Seed seed);
    /// @notice Emitted when a Shwoun is burned.
    event ShwounBurned(uint256 indexed tokenId);
    /// @notice Emitted when the founders DAO address changes.
    event FoundersDAOUpdated(address foundersDAO);
    /// @notice Emitted when the authorized minter changes.
    event MinterUpdated(address minter);
    /// @notice Emitted when the minter is permanently locked.
    event MinterLocked();
    /// @notice Emitted when the descriptor changes.
    event DescriptorUpdated(IShwounsDescriptorMinimal descriptor);
    /// @notice Emitted when the descriptor is permanently locked.
    event DescriptorLocked();
    /// @notice Emitted when the seeder changes.
    event SeederUpdated(IShwounsSeeder seeder);
    /// @notice Emitted when the seeder is permanently locked.
    event SeederLocked();

    /// @notice Mint the next Shwoun (and a founder Shwoun on the founder cadence). Minter only.
    /// @return The id of the minted (auction) Shwoun.
    function mint() external returns (uint256);

    /// @notice Burn a Shwoun. Minter only (retained for emergencies).
    /// @param tokenId The Shwoun id to burn.
    function burn(uint256 tokenId) external;

    /// @notice The data URI (on-chain JSON metadata) for a Shwoun.
    /// @param tokenId The Shwoun id.
    /// @return The data URI.
    function dataURI(uint256 tokenId) external returns (string memory);

    /// @notice Set the authorized minter. Owner only, until locked.
    /// @param minter The new minter address.
    function setMinter(address minter) external;

    /// @notice Permanently lock the minter. Owner only.
    function lockMinter() external;

    /// @notice Set the descriptor. Owner only, until locked.
    /// @param descriptor The new descriptor.
    function setDescriptor(IShwounsDescriptorMinimal descriptor) external;

    /// @notice Permanently lock the descriptor. Owner only.
    function lockDescriptor() external;

    /// @notice Set the seeder. Owner only, until locked.
    /// @param seeder The new seeder.
    function setSeeder(IShwounsSeeder seeder) external;

    /// @notice Permanently lock the seeder. Owner only.
    function lockSeeder() external;
}
