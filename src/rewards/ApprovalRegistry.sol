// SPDX-License-Identifier: GPL-3.0

/// @title ApprovalRegistry — DAO-curated allowlist of GI NFT tokenIds eligible for voter incentives
///
/// @notice The DAO (via governance proposal) approves or revokes specific GI NFT tokenIds.
///         When a voter claims a voter incentive, they pass the tokenId they want to claim with;
///         the registry verifies (a) the tokenId is approved AND (b) the caller owns it.
///
///         Tokenid-keyed approval (rather than address-keyed) means approvals follow the NFT.
///         If alice's approved tokenId 5 is transferred to bob, bob inherits the approval.
///         This is intentional — the DAO is approving a specific identity-bound asset, not an
///         address.

pragma solidity ^0.8.19;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { GovernedOwnable } from "../governance/GovernedOwnable.sol";

contract ApprovalRegistry is GovernedOwnable {
    IERC721 public immutable giNFT;
    mapping(uint256 => bool) public approvedTokenIds;

    event TokenIdApproved(uint256 indexed tokenId);
    event TokenIdRevoked(uint256 indexed tokenId);

    error AlreadyApproved();
    error NotApproved();
    error InvalidTokenId();

    constructor(IERC721 _giNFT, address _governanceAuth) GovernedOwnable(_governanceAuth) {
        if (address(_giNFT) == address(0)) revert InvalidTokenId();
        giNFT = _giNFT;
    }

    /// @notice Approve a tokenId. Only callable by owner (typically the DAOLogic post-deploy).
    function approve(uint256 tokenId) external onlyOwner {
        if (approvedTokenIds[tokenId]) revert AlreadyApproved();
        approvedTokenIds[tokenId] = true;
        emit TokenIdApproved(tokenId);
    }

    /// @notice Approve multiple tokenIds in one call.
    function approveMany(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (approvedTokenIds[tokenIds[i]]) continue; // idempotent
            approvedTokenIds[tokenIds[i]] = true;
            emit TokenIdApproved(tokenIds[i]);
        }
    }

    /// @notice Revoke approval of a tokenId.
    function revoke(uint256 tokenId) external onlyOwner {
        if (!approvedTokenIds[tokenId]) revert NotApproved();
        approvedTokenIds[tokenId] = false;
        emit TokenIdRevoked(tokenId);
    }

    /// @notice Check whether `holder` is eligible to claim using `tokenId`.
    function isEligible(address holder, uint256 tokenId) external view returns (bool) {
        if (!approvedTokenIds[tokenId]) return false;
        try giNFT.ownerOf(tokenId) returns (address owner) {
            return owner == holder;
        } catch {
            return false;
        }
    }
}
