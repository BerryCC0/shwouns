// SPDX-License-Identifier: GPL-3.0

/// @title Interface for Shwouns Auction House
/// @notice Forked from INounsAuctionHouseV3 (nouns-monorepo @ main). Mostly identical;
///         the only ABI change is the "noun" → "shwoun" terminology in events.

pragma solidity ^0.8.19;

interface IShwounsAuctionHouse {
    // Compact on-chain auction state (one storage slot).
    struct AuctionV2 {
        uint96 shwounId;
        uint32 clientId;
        uint128 amount;
        uint40 startTime;
        uint40 endTime;
        address payable bidder;
        bool settled;
    }

    // External-facing read view (drops clientId for backward-friendly callers).
    struct AuctionV2View {
        uint96 shwounId;
        uint128 amount;
        uint40 startTime;
        uint40 endTime;
        address payable bidder;
        bool settled;
    }

    struct SettlementState {
        uint32 blockTimestamp;
        uint64 amount;
        address winner;
        uint8 slotWarmedUp;
        uint32 clientId;
    }

    struct Settlement {
        uint32 blockTimestamp;
        uint256 amount;
        address winner;
        uint256 shwounId;
        uint32 clientId;
    }

    struct SettlementNoClientId {
        uint32 blockTimestamp;
        uint256 amount;
        address winner;
        uint256 shwounId;
    }

    event AuctionCreated(uint256 indexed shwounId, uint256 startTime, uint256 endTime);
    event AuctionBid(uint256 indexed shwounId, address sender, uint256 value, bool extended);
    event AuctionBidWithClientId(uint256 indexed shwounId, uint256 value, uint32 indexed clientId);
    event AuctionExtended(uint256 indexed shwounId, uint256 endTime);
    event AuctionSettled(uint256 indexed shwounId, address winner, uint256 amount);
    event AuctionSettledWithClientId(uint256 indexed shwounId, uint32 indexed clientId);
    event AuctionTimeBufferUpdated(uint256 timeBuffer);
    event AuctionReservePriceUpdated(uint256 reservePrice);
    event AuctionMinBidIncrementPercentageUpdated(uint256 minBidIncrementPercentage);
    event SanctionsOracleSet(address newSanctionsOracle);
    event GovernanceRewardsSet(address indexed governanceRewards);
    event VaultRegistrySet(address indexed vaultRegistry);

    function settleAuction() external;
    function settleCurrentAndCreateNewAuction() external;
    function createBid(uint256 shwounId) external payable;
    function createBid(uint256 shwounId, uint32 clientId) external payable;
    function pause() external;
    function unpause() external;
    function setTimeBuffer(uint56 timeBuffer) external;
    function setReservePrice(uint192 reservePrice) external;
    function setMinBidIncrementPercentage(uint8 minBidIncrementPercentage) external;
}
