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

/// @dev Candidate-implementation getter used by the A9 honest-upgrade safeguard.
interface IAuthed {
    /// @notice The auth registry a UUPS upgrade candidate reports (must match the canonical one).
    /// @return The candidate implementation's `governanceAuth` address.
    function governanceAuth() external view returns (address);
}

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

    /// @notice The minimum opening bid for an auction (wei).
    uint192 public reservePrice;
    /// @notice If a bid lands within this many seconds of the end, the auction extends by it.
    uint56 public timeBuffer;
    /// @notice Each new bid must exceed the previous by at least this percentage.
    uint8 public minBidIncrementPercentage;

    /// @notice The currently-active auction (packed V2 layout).
    IShwounsAuctionHouse.AuctionV2 public auctionStorage;
    mapping(uint256 => SettlementState) settlementHistory;
    /// @notice Optional Chainalysis sanctions oracle; bids from sanctioned addresses are rejected.
    IChainalysisSanctionsList public sanctionsOracle;

    /// @notice Recipient of all settlement proceeds. Settable once, then locked.
    address public governanceRewards;
    /// @notice True once `governanceRewards` has been set, after which it can never change.
    bool public governanceRewardsLocked;

    /// @notice Vault registry used to deploy per-Shwoun vaults. Settable once, then locked.
    IShwounsVaultRegistry public vaultRegistry;
    /// @notice True once `vaultRegistry` has been set, after which it can never change.
    bool public vaultRegistryLocked;

    /// @notice Thrown when a one-time setter is called after it has already been locked.
    error AlreadyLocked();
    /// @notice Thrown when a setter is given the zero address.
    error InvalidAddress();
    /// @notice Thrown when settling before `governanceRewards` (the proceeds recipient) is set.
    error GovernanceRewardsNotSet();
    /// @notice Thrown when creating an auction before the vault registry is set.
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

    /// @notice A10.5: once the auth registry is bound (post-bootstrap), ownership may only move to
    ///         the canonical DAO or address(0) — never an EOA. Pre-binding (bootstrap) is standard.
    /// @param newOwner The proposed owner; constrained to the DAO or `address(0)` once bound.
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        if (address(governanceAuth) != address(0)) {
            address dao = governanceAuth.daoLogic();
            if (dao != address(0) && newOwner != dao && newOwner != address(0)) {
                revert("AuctionHouse: owner must be DAO or zero");
            }
        }
        _transferOwnership(newOwner);
    }

    /// @notice Initialize the auction house. Sets initial knobs and pauses for setup.
    /// @param _reservePrice The minimum opening bid (wei).
    /// @param _timeBuffer The end-of-auction extension window (seconds).
    /// @param _minBidIncrementPercentage The minimum bid increment over the prior bid (percent).
    /// @param _sanctionsOracle The Chainalysis sanctions oracle (or zero to disable the check).
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

    /// @notice Set the settlement-proceeds recipient (GovernanceRewards). Callable once, then locked.
    /// @param _governanceRewards The GovernanceRewards address.
    function setGovernanceRewards(address _governanceRewards) external onlyOwner {
        if (governanceRewardsLocked) revert AlreadyLocked();
        if (_governanceRewards == address(0)) revert InvalidAddress();
        governanceRewards = _governanceRewards;
        governanceRewardsLocked = true;
        emit GovernanceRewardsSet(_governanceRewards);
    }

    /// @notice Set the vault registry used to deploy per-Shwoun vaults. Callable once, then locked.
    /// @param _vaultRegistry The ShwounsVaultRegistry address.
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

    /// @dev UUPS upgrade gate (A9): authorize ONLY the active proposal escrow (governance), never a
    ///      standing EOA/admin, and require the candidate impl to report the canonical auth registry
    ///      (honest-upgrade safeguard against a storage-layout-only diff).
    function _authorizeUpgrade(address newImplementation) internal view override {
        // A9: auction-house upgrades flow ONLY through an authenticated active proposal escrow.
        if (address(governanceAuth) == address(0) || !governanceAuth.isActiveExecutor(msg.sender)) {
            revert("AuctionHouse: not active executor");
        }
        // Honest-upgrade safeguard (review §9): the candidate must report the canonical auth
        // registry (a storage-layout diff can't see this immutable). A fully malicious impl can
        // still fake the getter and is out of scope per the A9 trust boundary.
        if (IAuthed(newImplementation).governanceAuth() != address(governanceAuth)) {
            revert("AuctionHouse: candidate registry mismatch");
        }
    }

    // -------------------------------------------------------------------------
    // Auction lifecycle
    // -------------------------------------------------------------------------

    /// @notice Settle the current auction and immediately start the next one. Reverts while paused.
    function settleCurrentAndCreateNewAuction() external override whenNotPaused {
        _settleAuction();
        _createAuction();
    }

    /// @notice Settle the current auction without starting a new one. Only while paused.
    function settleAuction() external override whenPaused {
        _settleAuction();
    }

    /// @notice Bid on the Shwoun currently up for auction (no client attribution).
    /// @param shwounId The id of the Shwoun being bid on (must match the active auction).
    function createBid(uint256 shwounId) external payable override {
        createBid(shwounId, 0);
    }

    /// @notice Bid on the current Shwoun, attributing the bid to a front-end client id.
    /// @param shwounId The id of the Shwoun being bid on (must match the active auction).
    /// @param clientId The front-end client id to attribute the bid to (0 = none).
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

    /// @notice The current auction as an unpacked view struct.
    /// @return The active auction (shwounId, amount, start/end time, bidder, settled).
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

    /// @notice Pause the auction house (no settle-and-create while paused). Owner/governance only.
    function pause() external override onlyOwner {
        _pause();
    }

    /// @notice Unpause and, if no auction is live, start one. Owner/governance only.
    function unpause() external override onlyOwner {
        _unpause();
        if (auctionStorage.startTime == 0 || auctionStorage.settled) {
            _createAuction();
        }
    }

    /// @notice Set the end-of-auction extension window. Owner/governance only.
    /// @param _timeBuffer The new time buffer (seconds); capped at `MAX_TIME_BUFFER`.
    function setTimeBuffer(uint56 _timeBuffer) external override onlyOwner {
        require(_timeBuffer <= MAX_TIME_BUFFER, 'timeBuffer too large');
        timeBuffer = _timeBuffer;
        emit AuctionTimeBufferUpdated(_timeBuffer);
    }

    /// @notice Set the minimum opening bid. Owner/governance only.
    /// @param _reservePrice The new reserve price (wei).
    function setReservePrice(uint192 _reservePrice) external override onlyOwner {
        reservePrice = _reservePrice;
        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /// @notice Set the minimum bid increment over the prior bid. Owner/governance only.
    /// @param _minBidIncrementPercentage The new increment (percent); must be greater than zero.
    function setMinBidIncrementPercentage(uint8 _minBidIncrementPercentage) external override onlyOwner {
        require(_minBidIncrementPercentage > 0, 'must be greater than zero');
        minBidIncrementPercentage = _minBidIncrementPercentage;
        emit AuctionMinBidIncrementPercentageUpdated(_minBidIncrementPercentage);
    }

    /// @notice Set (or clear) the Chainalysis sanctions oracle. Owner/governance only.
    /// @param newSanctionsOracle The new oracle address, or zero to disable the sanctions check.
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

    /// @notice Backfill historical settlement prices (e.g. for analytics). Owner/governance only.
    /// @param settlements The (shwounId, blockTimestamp, amount, winner) records to write.
    function setPrices(SettlementNoClientId[] memory settlements) external onlyOwner {
        for (uint256 i = 0; i < settlements.length; ++i) {
            SettlementState storage settlementState = settlementHistory[settlements[i].shwounId];
            settlementState.blockTimestamp = settlements[i].blockTimestamp;
            settlementState.amount = ethPriceToUint64(settlements[i].amount);
            settlementState.winner = settlements[i].winner;
        }
    }

    /// @notice Pre-warm settlement-history storage slots over a range (gas optimization for future
    ///         settlements). Permissionless. Skips founder-mint ids.
    /// @param startId The first id to warm (inclusive).
    /// @param endId The id to stop at (exclusive).
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

    /// @notice The most recent `auctionCount` settlements, newest first.
    /// @param auctionCount The number of settlements to return.
    /// @param skipEmptyValues If true, skip ids with no recorded settlement data.
    /// @return settlements The settlement records (trimmed to those actually found).
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

    /// @notice The most recent `auctionCount` winning prices (excludes no-bid/founder ids).
    /// @param auctionCount The number of prices to return; reverts if history is insufficient.
    /// @return prices The winning bid amounts, newest first.
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

    /// @notice Settlements from `startId` forward until a record newer than `endTimestamp`.
    /// @param startId The first id to include (inclusive).
    /// @param endTimestamp Stop once a settlement's timestamp exceeds this.
    /// @param skipEmptyValues If true, skip ids with no recorded settlement data.
    /// @return settlements The settlement records (trimmed to those actually found).
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

    /// @notice Settlements over the half-open id range `[startId, endId)`.
    /// @param startId The first id to include (inclusive).
    /// @param endId The id to stop at (exclusive).
    /// @param skipEmptyValues If true, skip ids with no recorded settlement data.
    /// @return settlements The settlement records (trimmed to those actually found).
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

    /// @notice The front-end client id credited with the winning bid for a Shwoun.
    /// @param shwounId The Shwoun id.
    /// @return The winning bid's client id (0 if none).
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
