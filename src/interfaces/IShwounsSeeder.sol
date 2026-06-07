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

    /// @notice Deterministically derive a 4-trait seed for a token from the prior blockhash.
    /// @param nounId The token id to generate a seed for.
    /// @param descriptor The descriptor providing each trait's count (the modulus per trait).
    /// @return The generated seed (background, body, accessory, head).
    function generateSeed(uint256 nounId, IShwounsDescriptorMinimal descriptor) external view returns (Seed memory);
}
