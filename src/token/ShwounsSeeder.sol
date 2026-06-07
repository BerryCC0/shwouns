// SPDX-License-Identifier: GPL-3.0

/// @title The ShwounsToken pseudo-random seed generator
/// @notice Forked from NounsSeeder (nouns-monorepo @ main). Glasses trait removed.

pragma solidity ^0.8.6;

import { IShwounsSeeder } from '../interfaces/IShwounsSeeder.sol';
import { IShwounsDescriptorMinimal } from '../interfaces/IShwounsDescriptorMinimal.sol';

contract ShwounsSeeder is IShwounsSeeder {
    /// @inheritdoc IShwounsSeeder
    function generateSeed(uint256 nounId, IShwounsDescriptorMinimal descriptor) external view override returns (Seed memory) {
        uint256 pseudorandomness = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), nounId))
        );

        uint256 backgroundCount = descriptor.backgroundCount();
        uint256 bodyCount = descriptor.bodyCount();
        uint256 accessoryCount = descriptor.accessoryCount();
        uint256 headCount = descriptor.headCount();

        return Seed({
            background: uint48(uint48(pseudorandomness) % backgroundCount),
            body: uint48(uint48(pseudorandomness >> 48) % bodyCount),
            accessory: uint48(uint48(pseudorandomness >> 96) % accessoryCount),
            head: uint48(uint48(pseudorandomness >> 144) % headCount)
        });
    }
}
