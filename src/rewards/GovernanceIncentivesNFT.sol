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
import { GovernedOwnable } from "../governance/GovernedOwnable.sol";

contract GovernanceIncentivesNFT is ERC721, GovernedOwnable {
    /// @notice Price (in wei) to mint one GI NFT. Owner-settable by the DAO.
    uint256 public mintPrice;
    /// @notice The id the next mint will assign (ids start at 1; 0 is reserved as "no token").
    uint256 public nextTokenId = 1;

    /// @notice Recipient of mint proceeds (A6). Decoupled from `owner()` so the DAO can OWN the GI
    ///         NFT (and govern `setMintPrice`) while proceeds still flow to GovernanceRewards.
    ///         Falls back to `owner()` until set.
    address public proceedsRecipient;

    /// @notice Emitted when the mint price changes.
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    /// @notice Emitted when the proceeds recipient changes.
    event ProceedsRecipientUpdated(address oldRecipient, address newRecipient);
    /// @notice Emitted on each mint, recording the buyer, token id, and ETH paid.
    event Minted(address indexed to, uint256 indexed tokenId, uint256 pricePaid);

    /// @notice Thrown when `mint` is sent less than `mintPrice`.
    error InsufficientPayment();
    /// @notice Thrown when forwarding mint proceeds to the recipient fails.
    error ProceedsForwardFailed();

    constructor(uint256 _mintPrice, address _governanceAuth)
        ERC721("Shwouns Governance Incentives", "SHWN-GI")
        GovernedOwnable(_governanceAuth)
    {
        mintPrice = _mintPrice;
    }

    /// @notice Mint a new GI NFT. Must send at least `mintPrice` ETH. Proceeds forward to
    ///         `proceedsRecipient` (GovernanceRewards), or `owner()` if unset.
    /// @return tokenId The id of the newly-minted GI NFT.
    function mint() external payable returns (uint256 tokenId) {
        if (msg.value < mintPrice) revert InsufficientPayment();
        tokenId = nextTokenId++;
        _mint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, msg.value);

        if (msg.value > 0) {
            address to = proceedsRecipient == address(0) ? owner() : proceedsRecipient;
            (bool ok, ) = to.call{value: msg.value}("");
            if (!ok) revert ProceedsForwardFailed();
        }
    }

    /// @notice Set the mint price. Governable (owner = DAO via the active escrow).
    /// @param newPrice The new mint price in wei.
    function setMintPrice(uint256 newPrice) external onlyOwner {
        uint256 old = mintPrice;
        mintPrice = newPrice;
        emit MintPriceUpdated(old, newPrice);
    }

    /// @notice Set where mint proceeds are forwarded (A6). Governable (owner = DAO via escrow).
    /// @param newRecipient The new proceeds recipient (typically GovernanceRewards).
    function setProceedsRecipient(address newRecipient) external onlyOwner {
        address old = proceedsRecipient;
        proceedsRecipient = newRecipient;
        emit ProceedsRecipientUpdated(old, newRecipient);
    }
}
