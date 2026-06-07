// SPDX-License-Identifier: GPL-3.0

/// @title Common interface for ShwounsDescriptor, used by ShwounsToken and ShwounsSeeder.
/// @notice Forked from INounsDescriptorMinimal — `glassesCount` removed.

pragma solidity ^0.8.6;

import { IShwounsSeeder } from './IShwounsSeeder.sol';

interface IShwounsDescriptorMinimal {
    /// @notice The token URI for a Shwoun given its seed (data URI or baseURI form).
    /// @param tokenId The Shwoun id.
    /// @param seed The Shwoun's trait seed.
    /// @return The token URI string.
    function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view returns (string memory);

    /// @notice The on-chain data URI (base64 JSON) for a Shwoun given its seed.
    /// @param tokenId The Shwoun id.
    /// @param seed The Shwoun's trait seed.
    /// @return The data URI string.
    function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory seed) external view returns (string memory);

    /// @notice The number of available background traits.
    /// @return The background count.
    function backgroundCount() external view returns (uint256);

    /// @notice The number of available body traits.
    /// @return The body count.
    function bodyCount() external view returns (uint256);

    /// @notice The number of available accessory traits.
    /// @return The accessory count.
    function accessoryCount() external view returns (uint256);

    /// @notice The number of available head traits.
    /// @return The head count.
    function headCount() external view returns (uint256);
}
