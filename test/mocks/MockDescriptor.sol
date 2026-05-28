// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";
import {IShwounsSeeder} from "../../src/interfaces/IShwounsSeeder.sol";

/// @dev Returns hardcoded trait counts and stub URIs. Sufficient for Token tests that
///      only exercise mint() (which calls generateSeed → trait counts) and tokenURI views.
contract MockDescriptor is IShwounsDescriptorMinimal {
    function tokenURI(uint256 tokenId, IShwounsSeeder.Seed memory) external pure returns (string memory) {
        return string(abi.encodePacked("shwoun://", _toString(tokenId)));
    }
    function dataURI(uint256 tokenId, IShwounsSeeder.Seed memory) external pure returns (string memory) {
        return string(abi.encodePacked("data:shwoun:", _toString(tokenId)));
    }
    function backgroundCount() external pure returns (uint256) { return 2; }
    function bodyCount()       external pure returns (uint256) { return 30; }
    function accessoryCount()  external pure returns (uint256) { return 140; }
    function headCount()       external pure returns (uint256) { return 240; }

    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 length = 0;
        while (j != 0) { length++; j /= 10; }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (v != 0) { k--; bstr[k] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(bstr);
    }
}
