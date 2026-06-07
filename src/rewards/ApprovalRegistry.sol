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
    /// @notice The Governance Incentives NFT whose token ids this registry curates.
    IERC721 public immutable giNFT;
    /// @notice Whether a given GI NFT token id is approved to earn voter incentives.
    mapping(uint256 => bool) public approvedTokenIds;

    /// @notice Emitted when a token id is approved.
    event TokenIdApproved(uint256 indexed tokenId);
    /// @notice Emitted when a token id's approval is revoked.
    event TokenIdRevoked(uint256 indexed tokenId);

    /// @notice Thrown when approving a token id that is already approved.
    error AlreadyApproved();
    /// @notice Thrown when revoking a token id that is not approved.
    error NotApproved();
    /// @notice Thrown when the constructor is given a zero GI NFT address.
    error InvalidTokenId();

    constructor(IERC721 _giNFT, address _governanceAuth) GovernedOwnable(_governanceAuth) {
        if (address(_giNFT) == address(0)) revert InvalidTokenId();
        giNFT = _giNFT;
    }

    /// @notice Approve a tokenId. Only callable by owner (typically the DAOLogic post-deploy).
    /// @param tokenId The GI NFT token id to approve.
    function approve(uint256 tokenId) external onlyOwner {
        if (approvedTokenIds[tokenId]) revert AlreadyApproved();
        approvedTokenIds[tokenId] = true;
        emit TokenIdApproved(tokenId);
    }

    /// @notice Approve multiple tokenIds in one call.
    /// @param tokenIds The GI NFT token ids to approve (already-approved ids are skipped).
    function approveMany(uint256[] calldata tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (approvedTokenIds[tokenIds[i]]) continue; // idempotent
            approvedTokenIds[tokenIds[i]] = true;
            emit TokenIdApproved(tokenIds[i]);
        }
    }

    /// @notice Revoke approval of a tokenId.
    /// @param tokenId The GI NFT token id to revoke.
    function revoke(uint256 tokenId) external onlyOwner {
        if (!approvedTokenIds[tokenId]) revert NotApproved();
        approvedTokenIds[tokenId] = false;
        emit TokenIdRevoked(tokenId);
    }

    /// @notice Check whether `holder` is eligible to claim using `tokenId`.
    /// @param holder The address claiming a voter incentive.
    /// @param tokenId The GI NFT token id being claimed with.
    /// @return True iff `tokenId` is approved AND currently owned by `holder`.
    function isEligible(address holder, uint256 tokenId) external view returns (bool) {
        if (!approvedTokenIds[tokenId]) return false;
        try giNFT.ownerOf(tokenId) returns (address owner) {
            return owner == holder;
        } catch {
            return false;
        }
    }
}
