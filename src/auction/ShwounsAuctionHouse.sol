// SPDX-License-Identifier: GPL-3.0

/// @title The Shwouns DAO auction house
///
/// @notice Forked from NounsAuctionHouseV3 (nouns-monorepo @ main). Changes:
///   - Add UUPSUpgradeable for governance-driven upgrades
///   - Replace INounsToken with IShwounsToken
///   - Replace INounsAuctionHouseV3 with IShwounsAuctionHouse
///   - Add settable governanceRewards (locks after first set) — settlement proceeds go here
///   - Add settable vaultRegistry (locks after first set) — for createVaultFor on mint/settle
///   - No-bid path: Shwoun goes to governanceRewards (not burned). Vault still created.
///   - On mint: also create vaults for any concurrently-minted founder Shwouns
///
/// LICENSE
/// Inherits from Zora's AuctionHouse via Nouns' modifications:
/// https://github.com/ourzora/auction-house/blob/54a12ec1a6cf562e49f0a4917990474b11350a2d/contracts/AuctionHouse.sol
/// Original Copyright Zora, GPL-3.0. Modifications by Nounders DAO and the Shwouns project.

pragma solidity ^0.8.19;

import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IShwounsAuctionHouse } from '../interfaces/IShwounsAuctionHouse.sol';
import { IShwounsToken } from '../interfaces/IShwounsToken.sol';
import { IWETH } from '../interfaces/IWETH.sol';
import { IChainalysisSanctionsList } from '../interfaces/IChainalysisSanctionsList.sol';
import { IShwounsVaultRegistry } from '../vault/IShwounsVaultRegistry.sol';
import { IGovernanceAuthRegistry } from '../governance/GovernanceAuthRegistry.sol';

contract ShwounsAuctionHouse is
    IShwounsAuctionHouse,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @notice Hard-cap on time buffer.
    uint56 public constant MAX_TIME_BUFFER = 1 days;

    /// @notice Last token ID at which founders receive a reward. Mirrors ShwounsToken.
    uint256 public constant FOUNDERS_REWARD_ENDS = 1820;

    /// @notice The Shwouns ERC-721 token contract.
    IShwounsToken public immutable shwouns;

    /// @notice WETH (settlement fallback if direct ETH transfer fails).
    address public immutable weth;

    /// @notice Duration of a single auction (seconds).
    uint256 public immutable duration;

    /// @notice Auth registry (A5). Immutable lives in impl bytecode, not proxy storage — so it adds
    ///         no storage slot. onlyOwner functions also accept the active proposal escrow via this.
    IGovernanceAuthRegistry public immutable governanceAuth;

    uint192 public reservePrice;
    uint56 public timeBuffer;
    uint8 public minBidIncrementPercentage;

    IShwounsAuctionHouse.AuctionV2 public auctionStorage;
    mapping(uint256 => SettlementState) settlementHistory;
    IChainalysisSanctionsList public sanctionsOracle;

    /// @notice Recipient of all settlement proceeds. Settable once, then locked.
    address public governanceRewards;
    bool public governanceRewardsLocked;

    /// @notice Vault registry used to deploy per-Shwoun vaults. Settable once, then locked.
    IShwounsVaultRegistry public vaultRegistry;
    bool public vaultRegistryLocked;

    error AlreadyLocked();
    error InvalidAddress();
    error GovernanceRewardsNotSet();
    error VaultRegistryNotSet();

    constructor(IShwounsToken _shwouns, address _weth, uint256 _duration, address _governanceAuth) initializer {
        shwouns = _shwouns;
        weth = _weth;
        duration = _duration;
        governanceAuth = IGovernanceAuthRegistry(_governanceAuth);
    }

    /// @dev onlyOwner also accepts the currently-authenticated active proposal escrow (A5), so DAO
    ///      governance can pause/upgrade/tune the auction house via an approved proposal. Mirrors
    ///      GovernedOwnable for this OwnableUpgradeable contract.
    function _checkOwner() internal view override {
        if (msg.sender == owner()) return;
        if (address(governanceAuth) != address(0) && governanceAuth.isActiveExecutor(msg.sender)) return;
        revert("Ownable: caller is not the owner");
    }

    /// @notice Initialize the auction house. Sets initial knobs and pauses for setup.
    function initialize(
        uint192 _reservePrice,
        uint56 _timeBuffer,
        uint8 _minBidIncrementPercentage,
        IChainalysisSanctionsList _sanctionsOracle
    ) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        _pause();

        reservePrice = _reservePrice;
        timeBuffer = _timeBuffer;
        minBidIncrementPercentage = _minBidIncrementPercentage;
        sanctionsOracle = _sanctionsOracle;

        emit SanctionsOracleSet(address(_sanctionsOracle));
    }

    // -------------------------------------------------------------------------
    // One-time setters (called during deployment, then locked)
    // -------------------------------------------------------------------------

    function setGovernanceRewards(address _governanceRewards) external onlyOwner {
        if (governanceRewardsLocked) revert AlreadyLocked();
        if (_governanceRewards == address(0)) revert InvalidAddress();
        governanceRewards = _governanceRewards;
        governanceRewardsLocked = true;
        emit GovernanceRewardsSet(_governanceRewards);
    }

    function setVaultRegistry(IShwounsVaultRegistry _vaultRegistry) external onlyOwner {
        if (vaultRegistryLocked) revert AlreadyLocked();
        if (address(_vaultRegistry) == address(0)) revert InvalidAddress();
        vaultRegistry = _vaultRegistry;
        vaultRegistryLocked = true;
        emit VaultRegistrySet(address(_vaultRegistry));
    }

    // -------------------------------------------------------------------------
    // UUPS upgrade authorization
    // -------------------------------------------------------------------------

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // -------------------------------------------------------------------------
    // Auction lifecycle
    // -------------------------------------------------------------------------

    function settleCurrentAndCreateNewAuction() external override whenNotPaused {
        _settleAuction();
        _createAuction();
    }

    function settleAuction() external override whenPaused {
        _settleAuction();
    }

    function createBid(uint256 shwounId) external payable override {
        createBid(shwounId, 0);
    }

    function createBid(uint256 shwounId, uint32 clientId) public payable override {
        IShwounsAuctionHouse.AuctionV2 memory _auction = auctionStorage;

        (uint192 _reservePrice, uint56 _timeBuffer, uint8 _minBidIncrementPercentage) = (
            reservePrice,
            timeBuffer,
            minBidIncrementPercentage
        );

        _requireNotSanctioned(msg.sender);
        require(_auction.shwounId == shwounId, 'Shwoun not up for auction');
        require(block.timestamp < _auction.endTime, 'Auction expired');
        require(msg.value >= _reservePrice, 'Must send at least reservePrice');
        require(
            msg.value >= _auction.amount + ((_auction.amount * _minBidIncrementPercentage) / 100),
            'Must send more than last bid by minBidIncrementPercentage amount'
        );

        auctionStorage.clientId = clientId;
        auctionStorage.amount = uint128(msg.value);
        auctionStorage.bidder = payable(msg.sender);

        bool extended = _auction.endTime - block.timestamp < _timeBuffer;

        emit AuctionBid(_auction.shwounId, msg.sender, msg.value, extended);
        if (clientId > 0) emit AuctionBidWithClientId(_auction.shwounId, msg.value, clientId);

        if (extended) {
            auctionStorage.endTime = _auction.endTime = uint40(block.timestamp + _timeBuffer);
            emit AuctionExtended(_auction.shwounId, _auction.endTime);
        }

        address payable lastBidder = _auction.bidder;
        if (lastBidder != address(0)) {
            _safeTransferETHWithFallback(lastBidder, _auction.amount);
        }
    }

    function auction() external view returns (AuctionV2View memory) {
        return AuctionV2View({
            shwounId: auctionStorage.shwounId,
            amount: auctionStorage.amount,
            startTime: auctionStorage.startTime,
            endTime: auctionStorage.endTime,
            bidder: auctionStorage.bidder,
            settled: auctionStorage.settled
        });
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
        if (auctionStorage.startTime == 0 || auctionStorage.settled) {
            _createAuction();
        }
    }

    function setTimeBuffer(uint56 _timeBuffer) external override onlyOwner {
        require(_timeBuffer <= MAX_TIME_BUFFER, 'timeBuffer too large');
        timeBuffer = _timeBuffer;
        emit AuctionTimeBufferUpdated(_timeBuffer);
    }

    function setReservePrice(uint192 _reservePrice) external override onlyOwner {
        reservePrice = _reservePrice;
        emit AuctionReservePriceUpdated(_reservePrice);
    }

    function setMinBidIncrementPercentage(uint8 _minBidIncrementPercentage) external override onlyOwner {
        require(_minBidIncrementPercentage > 0, 'must be greater than zero');
        minBidIncrementPercentage = _minBidIncrementPercentage;
        emit AuctionMinBidIncrementPercentageUpdated(_minBidIncrementPercentage);
    }

    function setSanctionsOracle(address newSanctionsOracle) public onlyOwner {
        sanctionsOracle = IChainalysisSanctionsList(newSanctionsOracle);
        emit SanctionsOracleSet(newSanctionsOracle);
    }

    // -------------------------------------------------------------------------
    // Internal: create + settle
    // -------------------------------------------------------------------------

    /// @notice Create an auction, minting the next Shwoun (and possibly a founder Shwoun).
    ///         Creates vaults for both newly-minted Shwouns via the registry.
    function _createAuction() internal {
        if (address(vaultRegistry) == address(0)) revert VaultRegistryNotSet();
        try shwouns.mint() returns (uint256 shwounId) {
            uint40 startTime = uint40(block.timestamp);
            uint40 endTime = startTime + uint40(duration);

            auctionStorage = AuctionV2({
                shwounId: uint96(shwounId),
                clientId: 0,
                amount: 0,
                startTime: startTime,
                endTime: endTime,
                bidder: payable(0),
                settled: false
            });

            // Deploy vault for the auction Shwoun.
            vaultRegistry.createVaultFor(shwounId);

            // If a founder Shwoun was also minted this cycle, deploy its vault.
            // Founder mints happen at IDs 0, 10, 20, ... up to FOUNDERS_REWARD_ENDS.
            // An auction Shwoun N implies a concurrent founder mint at N-1 iff
            // (N-1) % 10 == 0 AND (N-1) <= FOUNDERS_REWARD_ENDS.
            if (shwounId >= 1 && (shwounId - 1) % 10 == 0 && (shwounId - 1) <= FOUNDERS_REWARD_ENDS) {
                vaultRegistry.createVaultFor(shwounId - 1);
            }

            emit AuctionCreated(shwounId, startTime, endTime);
        } catch Error(string memory) {
            _pause();
        }
    }

    /// @notice Settle the current auction. Routes Shwoun + ETH to the right recipients.
    function _settleAuction() internal {
        IShwounsAuctionHouse.AuctionV2 memory _auction = auctionStorage;

        require(_auction.startTime != 0, "Auction hasn't begun");
        require(!_auction.settled, 'Auction has already been settled');
        require(block.timestamp >= _auction.endTime, "Auction hasn't completed");
        if (governanceRewards == address(0)) revert GovernanceRewardsNotSet();

        auctionStorage.settled = true;

        if (_auction.bidder == address(0)) {
            // No-bid: Shwoun goes to GovernanceRewards (NOT burned). Its vault is already deployed.
            shwouns.transferFrom(address(this), governanceRewards, _auction.shwounId);
        } else {
            shwouns.transferFrom(address(this), _auction.bidder, _auction.shwounId);
        }

        if (_auction.amount > 0) {
            // All proceeds → GovernanceRewards. WETH fallback if direct send fails.
            _safeTransferETHWithFallback(governanceRewards, _auction.amount);
        }

        SettlementState storage settlementState = settlementHistory[_auction.shwounId];
        settlementState.blockTimestamp = uint32(block.timestamp);
        settlementState.amount = ethPriceToUint64(_auction.amount);
        settlementState.winner = _auction.bidder;
        if (_auction.clientId > 0) settlementState.clientId = _auction.clientId;

        emit AuctionSettled(_auction.shwounId, _auction.bidder, _auction.amount);
        if (_auction.clientId > 0) emit AuctionSettledWithClientId(_auction.shwounId, _auction.clientId);
    }

    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(weth).deposit{ value: amount }();
            IERC20(weth).transfer(to, amount);
        }
    }

    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        bool success;
        assembly {
            success := call(30000, to, value, 0, 0, 0, 0)
        }
        return success;
    }

    function _requireNotSanctioned(address account) internal view {
        IChainalysisSanctionsList sanctionsOracle_ = sanctionsOracle;
        if (address(sanctionsOracle_) != address(0)) {
            require(!sanctionsOracle_.isSanctioned(account), 'Sanctioned bidder');
        }
    }

    // -------------------------------------------------------------------------
    // Settlement history (unchanged from V3)
    // -------------------------------------------------------------------------

    function setPrices(SettlementNoClientId[] memory settlements) external onlyOwner {
        for (uint256 i = 0; i < settlements.length; ++i) {
            SettlementState storage settlementState = settlementHistory[settlements[i].shwounId];
            settlementState.blockTimestamp = settlements[i].blockTimestamp;
            settlementState.amount = ethPriceToUint64(settlements[i].amount);
            settlementState.winner = settlements[i].winner;
        }
    }

    function warmUpSettlementState(uint256 startId, uint256 endId) external {
        for (uint256 i = startId; i < endId; ++i) {
            if (i <= FOUNDERS_REWARD_ENDS && i % 10 == 0) continue;
            SettlementState storage settlementState = settlementHistory[i];
            if (settlementState.blockTimestamp == 0) {
                settlementState.blockTimestamp = 1;
                settlementState.slotWarmedUp = 1;
            }
        }
    }

    function getSettlements(
        uint256 auctionCount,
        bool skipEmptyValues
    ) external view returns (Settlement[] memory settlements) {
        uint256 latestShwounId = auctionStorage.shwounId;
        if (!auctionStorage.settled && latestShwounId > 0) {
            latestShwounId -= 1;
        }

        settlements = new Settlement[](auctionCount);
        uint256 actualCount = 0;

        SettlementState memory settlementState;
        for (uint256 id = latestShwounId; actualCount < auctionCount; --id) {
            settlementState = settlementHistory[id];
            if (skipEmptyValues && settlementState.blockTimestamp <= 1) {
                if (id == 0) break;
                continue;
            }
            settlements[actualCount] = Settlement({
                blockTimestamp: settlementState.blockTimestamp,
                amount: uint64PriceToUint256(settlementState.amount),
                winner: settlementState.winner,
                shwounId: id,
                clientId: settlementState.clientId
            });
            ++actualCount;
            if (id == 0) break;
        }

        if (auctionCount > actualCount) {
            assembly { mstore(settlements, actualCount) }
        }
    }

    function getPrices(uint256 auctionCount) external view returns (uint256[] memory prices) {
        uint256 latestShwounId = auctionStorage.shwounId;
        if (!auctionStorage.settled && latestShwounId > 0) {
            latestShwounId -= 1;
        }

        prices = new uint256[](auctionCount);
        uint256 actualCount = 0;

        SettlementState memory settlementState;
        for (uint256 id = latestShwounId; id > 0 && actualCount < auctionCount; --id) {
            if (id <= FOUNDERS_REWARD_ENDS && id % 10 == 0) continue;
            settlementState = settlementHistory[id];
            require(settlementState.blockTimestamp > 1, 'Missing data');
            if (settlementState.winner == address(0)) continue;
            prices[actualCount] = uint64PriceToUint256(settlementState.amount);
            ++actualCount;
        }

        require(auctionCount == actualCount, 'Not enough history');
    }

    function getSettlementsFromIdtoTimestamp(
        uint256 startId,
        uint256 endTimestamp,
        bool skipEmptyValues
    ) public view returns (Settlement[] memory settlements) {
        uint256 maxId = auctionStorage.shwounId;
        require(startId <= maxId, 'startId too large');
        settlements = new Settlement[](maxId - startId + 1);
        uint256 actualCount = 0;
        SettlementState memory settlementState;
        for (uint256 id = startId; id <= maxId; ++id) {
            settlementState = settlementHistory[id];
            if (skipEmptyValues && settlementState.blockTimestamp <= 1) continue;
            if ((id == maxId) && (settlementState.blockTimestamp <= 1)) continue;
            if (settlementState.blockTimestamp > endTimestamp) break;
            settlements[actualCount] = Settlement({
                blockTimestamp: settlementState.blockTimestamp,
                amount: uint64PriceToUint256(settlementState.amount),
                winner: settlementState.winner,
                shwounId: id,
                clientId: settlementState.clientId
            });
            ++actualCount;
        }
        if (settlements.length > actualCount) {
            assembly { mstore(settlements, actualCount) }
        }
    }

    function getSettlements(
        uint256 startId,
        uint256 endId,
        bool skipEmptyValues
    ) external view returns (Settlement[] memory settlements) {
        settlements = new Settlement[](endId - startId);
        uint256 actualCount = 0;
        SettlementState memory settlementState;
        for (uint256 id = startId; id < endId; ++id) {
            settlementState = settlementHistory[id];
            if (skipEmptyValues && settlementState.blockTimestamp <= 1) continue;
            settlements[actualCount] = Settlement({
                blockTimestamp: settlementState.blockTimestamp,
                amount: uint64PriceToUint256(settlementState.amount),
                winner: settlementState.winner,
                shwounId: id,
                clientId: settlementState.clientId
            });
            ++actualCount;
        }
        if (settlements.length > actualCount) {
            assembly { mstore(settlements, actualCount) }
        }
    }

    function biddingClient(uint256 shwounId) external view returns (uint32) {
        return settlementHistory[shwounId].clientId;
    }

    function ethPriceToUint64(uint256 ethPrice) internal pure returns (uint64) {
        return uint64(ethPrice / 1e8);
    }

    function uint64PriceToUint256(uint64 price) internal pure returns (uint256) {
        return uint256(price) * 1e8;
    }
}
