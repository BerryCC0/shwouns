// SPDX-License-Identifier: GPL-3.0

/// @title Interface for ShwounsToken
/// @notice Forked from INounsToken — uses IShwounsSeeder.Seed (no glasses) and
///         IShwounsDescriptorMinimal (no glassesCount).

pragma solidity ^0.8.6;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IShwounsDescriptorMinimal } from './IShwounsDescriptorMinimal.sol';
import { IShwounsSeeder } from './IShwounsSeeder.sol';

interface IShwounsToken is IERC721 {
    event ShwounCreated(uint256 indexed tokenId, IShwounsSeeder.Seed seed);
    event ShwounBurned(uint256 indexed tokenId);
    event FoundersDAOUpdated(address foundersDAO);
    event MinterUpdated(address minter);
    event MinterLocked();
    event DescriptorUpdated(IShwounsDescriptorMinimal descriptor);
    event DescriptorLocked();
    event SeederUpdated(IShwounsSeeder seeder);
    event SeederLocked();

    function mint() external returns (uint256);
    function burn(uint256 tokenId) external;
    function dataURI(uint256 tokenId) external returns (string memory);
    function setMinter(address minter) external;
    function lockMinter() external;
    function setDescriptor(IShwounsDescriptorMinimal descriptor) external;
    function lockDescriptor() external;
    function setSeeder(IShwounsSeeder seeder) external;
    function lockSeeder() external;
}
