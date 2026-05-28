// SPDX-License-Identifier: GPL-3.0

/// @title Common interface for ShwounsDescriptor, used by ShwounsToken and ShwounsSeeder.
/// @notice Forked from INounsDescriptorMinimal — `glassesCount` removed.

pragma solidity ^0.8.6;

import { IShwounsSeeder } from './IShwounsSeeder.sol';

interface IShwounsDescriptorMinimal {
    function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view returns (string memory);

    function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view returns (string memory);

    function backgroundCount() external view returns (uint256);

    function bodyCount() external view returns (uint256);

    function accessoryCount() external view returns (uint256);

    function headCount() external view returns (uint256);
}
