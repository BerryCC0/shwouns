// SPDX-License-Identifier: GPL-3.0

/// @title Interface for ShwounsSeeder
/// @notice Forked from NounsSeeder — `glasses` field removed.

pragma solidity ^0.8.6;

import { IShwounsDescriptorMinimal } from './IShwounsDescriptorMinimal.sol';

interface IShwounsSeeder {
    struct Seed {
        uint48 background;
        uint48 body;
        uint48 accessory;
        uint48 head;
    }

    function generateSeed(uint256 nounId, IShwounsDescriptorMinimal descriptor) external view returns (Seed memory);
}
