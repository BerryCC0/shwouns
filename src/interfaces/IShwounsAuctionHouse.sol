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

    /// @notice Emitted when a new auction starts (a Shwoun is minted and put up for bid).
    event AuctionCreated(uint256 indexed shwounId, uint256 startTime, uint256 endTime);
    /// @notice Emitted on each bid; `extended` is true if the bid pushed back the end time.
    event AuctionBid(uint256 indexed shwounId, address sender, uint256 value, bool extended);
    /// @notice Emitted alongside AuctionBid when the bid carried a non-zero client id.
    event AuctionBidWithClientId(uint256 indexed shwounId, uint256 value, uint32 indexed clientId);
    /// @notice Emitted when a late bid extends the auction end time.
    event AuctionExtended(uint256 indexed shwounId, uint256 endTime);
    /// @notice Emitted when an auction is settled (winner determined, proceeds routed).
    event AuctionSettled(uint256 indexed shwounId, address winner, uint256 amount);
    /// @notice Emitted alongside AuctionSettled when the winning bid carried a client id.
    event AuctionSettledWithClientId(uint256 indexed shwounId, uint32 indexed clientId);
    /// @notice Emitted when the time buffer changes.
    event AuctionTimeBufferUpdated(uint256 timeBuffer);
    /// @notice Emitted when the reserve price changes.
    event AuctionReservePriceUpdated(uint256 reservePrice);
    /// @notice Emitted when the minimum bid increment percentage changes.
    event AuctionMinBidIncrementPercentageUpdated(uint256 minBidIncrementPercentage);
    /// @notice Emitted when the sanctions oracle is set or cleared.
    event SanctionsOracleSet(address newSanctionsOracle);
    /// @notice Emitted once when the settlement-proceeds recipient is set and locked.
    event GovernanceRewardsSet(address indexed governanceRewards);
    /// @notice Emitted once when the vault registry is set and locked.
    event VaultRegistrySet(address indexed vaultRegistry);

    /// @notice Settle the current auction without starting a new one (only while paused).
    function settleAuction() external;

    /// @notice Settle the current auction and immediately create the next one.
    function settleCurrentAndCreateNewAuction() external;

    /// @notice Bid on the Shwoun currently up for auction.
    /// @param shwounId The id of the Shwoun being bid on (must match the active auction).
    function createBid(uint256 shwounId) external payable;

    /// @notice Bid on the current Shwoun, attributing the bid to a front-end client id.
    /// @param shwounId The id of the Shwoun being bid on (must match the active auction).
    /// @param clientId The front-end client id to attribute the bid to (0 = none).
    function createBid(uint256 shwounId, uint32 clientId) external payable;

    /// @notice Pause the auction house. Owner/governance only.
    function pause() external;

    /// @notice Unpause the auction house (starts an auction if none is live). Owner/governance only.
    function unpause() external;

    /// @notice Set the end-of-auction extension window. Owner/governance only.
    /// @param timeBuffer The new time buffer (seconds).
    function setTimeBuffer(uint56 timeBuffer) external;

    /// @notice Set the minimum opening bid. Owner/governance only.
    /// @param reservePrice The new reserve price (wei).
    function setReservePrice(uint192 reservePrice) external;

    /// @notice Set the minimum bid increment over the prior bid. Owner/governance only.
    /// @param minBidIncrementPercentage The new increment (percent).
    function setMinBidIncrementPercentage(uint8 minBidIncrementPercentage) external;
}
