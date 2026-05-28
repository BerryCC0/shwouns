// SPDX-License-Identifier: GPL-3.0

/// @title GovernanceIncentivesNFT (GI NFT) — open-mint NFT that gates voter incentive eligibility
///
/// @notice Anyone can mint a GI NFT by paying `mintPrice`. Mint proceeds are forwarded to
///         the contract owner (typically `GovernanceRewards`). Holding a GI NFT alone does
///         NOT qualify the holder for voter incentives — the tokenId must also be approved
///         in `ApprovalRegistry`. This two-layer gate (open mint + DAO allowlist) lets the
///         DAO curate which holders earn incentives without preventing anyone from minting.
///
/// @dev Token IDs start at 1 (0 reserved as "no token").

pragma solidity ^0.8.19;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract GovernanceIncentivesNFT is ERC721, Ownable {
    uint256 public mintPrice;
    uint256 public nextTokenId = 1;

    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event Minted(address indexed to, uint256 indexed tokenId, uint256 pricePaid);

    error InsufficientPayment();
    error ProceedsForwardFailed();

    constructor(uint256 _mintPrice) ERC721("Shwouns Governance Incentives", "SHWN-GI") {
        mintPrice = _mintPrice;
    }

    /// @notice Mint a new GI NFT. Must send at least `mintPrice` ETH. Mint proceeds are
    ///         forwarded to the contract owner.
    function mint() external payable returns (uint256 tokenId) {
        if (msg.value < mintPrice) revert InsufficientPayment();
        tokenId = nextTokenId++;
        _mint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, msg.value);

        if (msg.value > 0) {
            (bool ok, ) = owner().call{value: msg.value}("");
            if (!ok) revert ProceedsForwardFailed();
        }
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        uint256 old = mintPrice;
        mintPrice = newPrice;
        emit MintPriceUpdated(old, newPrice);
    }
}
