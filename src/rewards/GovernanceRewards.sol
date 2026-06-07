// SPDX-License-Identifier: GPL-3.0

/// @title GovernanceRewards — accumulator + voter incentive distribution + gas refunds
///
/// @notice Receives auction proceeds (Phase 3). In Phase 5 also distributes:
///   - **Voter incentives**: per-proposal reward pool divvied pro-rata by votes among For/Against
///     voters who hold an approved GI NFT.
///   - **Refundable votes**: gas refunds when DAOLogic invokes castRefundableVote.
///
/// Architecture:
///   - DAOLogic calls allocateProposalReward(proposalId) inside finalize() — sets aside
///     `proposalRewardAmount` for that proposal.
///   - Voters call claimVotingReward(proposalId, giTokenId) — eligibility check via
///     ApprovalRegistry, pro-rata share calculation against DAOLogic's vote totals.
///   - DAOLogic calls refundGas(voter, amount) when castRefundableVote fires — capped to
///     prevent griefing.
///
/// Funding flow: auction proceeds → GR balance. Mint proceeds from GI NFT → GR balance
///   (when GR is set as GI NFT owner). Out: voter rewards (lazy, per-claim), gas refunds.

pragma solidity ^0.8.19;

import { ERC721Holder } from '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import { ERC1155Holder } from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IERC1155 } from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import { ApprovalRegistry } from './ApprovalRegistry.sol';
import { GovernedOwnable } from '../governance/GovernedOwnable.sol';

/// @dev Minimal interface for the bits of DAOLogic that GR reads from. Uses *Unpacked
///      naming to avoid clashing with DAOLogic's existing struct-returning getReceipt.
interface IDAOLogicForRewards {
    /// @notice A voter's receipt for a proposal, in unpacked form.
    /// @param proposalId The proposal id.
    /// @param voter The voter address.
    /// @return hasVoted Whether the voter cast a vote.
    /// @return support The vote: 0=against, 1=for, 2=abstain.
    /// @return votes The voting weight recorded for the vote.
    function getReceiptUnpacked(uint256 proposalId, address voter)
        external view returns (bool hasVoted, uint8 support, uint96 votes);

    /// @notice A proposal's vote tallies.
    /// @param proposalId The proposal id.
    /// @return forVotes Total For votes.
    /// @return againstVotes Total Against votes.
    /// @return abstainVotes Total Abstain votes.
    function proposalVotes(uint256 proposalId)
        external view returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);
}

contract GovernanceRewards is GovernedOwnable, ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    /// @param _governanceAuth The GovernanceAuthRegistry (so DAO governance can sweep / configure
    ///        via an authenticated proposal escrow). address(0) reduces to plain Ownable.
    constructor(address _governanceAuth) GovernedOwnable(_governanceAuth) {}

    // -------------------------------------------------------------------------
    // External wiring (set once, locked)
    // -------------------------------------------------------------------------

    /// @notice The DAOLogic proxy whose vote records and totals drive reward claims. Set once, locked.
    IDAOLogicForRewards public dao;
    /// @notice The allowlist consulted to verify a claimant's GI NFT is approved. Set once, locked.
    ApprovalRegistry public approvalRegistry;
    /// @notice True once `dao` has been set, after which it can never change.
    bool public daoLocked;
    /// @notice True once `approvalRegistry` has been set, after which it can never change.
    bool public approvalRegistryLocked;

    // -------------------------------------------------------------------------
    // Reward configuration
    // -------------------------------------------------------------------------

    /// @notice Reward pool allocated to each proposal that reaches finalize. Owner-settable.
    uint256 public proposalRewardAmount = 0.1 ether;

    /// @notice Max gas refund per castRefundableVote call (ETH). Prevents griefing.
    uint256 public maxRefundPerVote = 0.003 ether;

    // -------------------------------------------------------------------------
    // Per-proposal reward bookkeeping
    // -------------------------------------------------------------------------

    /// @notice ETH set aside for a given proposal's voter rewards (the original pool, for pro-rata).
    mapping(uint256 => uint256) public proposalRewardPool;
    /// @notice Unclaimed remainder of a proposal's pool (decremented as voters claim). M-01.
    mapping(uint256 => uint256) public remainingRewardPool;
    /// @notice Sum of all unclaimed allocations across proposals — funds that are RESERVED and may
    ///         not be re-allocated, gas-refunded, or swept. M-01.
    uint256 public totalReserved;
    /// @notice Per-(proposal, voter) claimed flag (stops one voter claiming twice via two NFTs).
    mapping(uint256 => mapping(address => bool)) public voterClaimed;
    /// @notice Per-(proposal, giTokenId) claimed flag (H-03: stops one approved NFT, passed
    ///         hand-to-hand, from authorizing many voters). Both flags are checked AND set.
    mapping(uint256 => mapping(uint256 => bool)) public claimedByTokenId;
    /// @notice Per-proposal claim deadline (block.timestamp). After it, claims revert and the
    ///         unclaimed remainder can be released permissionlessly.
    mapping(uint256 => uint256) public rewardDeadline;

    /// @notice How long after allocation voters may claim. Settled at 180 days.
    uint256 public constant CLAIM_PERIOD = 180 days;

    /// @notice Total ETH ever received via deposit() / receive() / NFT mint forwarding.
    uint256 public lifetimeETHReceived;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted on each ETH inflow (auction proceeds, mint forwarding, direct deposit).
    event Deposited(address indexed asset, address indexed from, uint256 amount);
    /// @notice Emitted when a Shwoun NFT is received (e.g. a no-bid auction routes the Shwoun here).
    event ShwounReceived(uint256 indexed shwounId, address indexed from);
    /// @notice Emitted when a held Shwoun is transferred out by governance.
    event ShwounTransferred(uint256 indexed shwounId, address indexed to);
    /// @notice Emitted when unreserved ETH is swept out by governance.
    event ETHSwept(address indexed to, uint256 amount);
    /// @notice Emitted when an ERC-20 balance is swept out by governance.
    event ERC20Swept(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when an ERC-721 is swept out by governance.
    event ERC721Swept(address indexed token, address indexed to, uint256 tokenId);
    /// @notice Emitted when an ERC-1155 balance is swept out by governance.
    event ERC1155Swept(address indexed token, address indexed to, uint256 id, uint256 amount);

    /// @notice Emitted once when the DAOLogic reference is set and locked.
    event DAOLogicSet(address indexed dao);
    /// @notice Emitted once when the ApprovalRegistry reference is set and locked.
    event ApprovalRegistrySet(address indexed registry);
    /// @notice Emitted when the per-proposal reward amount changes.
    event ProposalRewardAmountSet(uint256 oldAmount, uint256 newAmount);
    /// @notice Emitted when the per-vote gas-refund cap changes.
    event MaxRefundPerVoteSet(uint256 oldAmount, uint256 newAmount);

    /// @notice Emitted when a proposal's reward pool is reserved at finalize.
    event ProposalRewardAllocated(uint256 indexed proposalId, uint256 amount);
    /// @notice Emitted when a voter claims their pro-rata share of a proposal's reward pool.
    event VoterRewardClaimed(uint256 indexed proposalId, address indexed voter, uint256 indexed giTokenId, uint256 amount);
    /// @notice Emitted on each gas-refund attempt; `sent` is false if nothing was paid.
    event GasRefunded(address indexed voter, uint256 amount, bool sent);
    /// @notice Emitted when an expired pool's unclaimed remainder is released back to unreserved balance.
    event RewardRemainderReleased(uint256 indexed proposalId, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when a one-time setter is called after it has been locked.
    error AlreadyLocked();
    /// @notice Thrown when a setter is given a zero address.
    error InvalidAddress();
    /// @notice Thrown when an `onlyDAO` function is called by an address other than `dao`.
    error NotDAO();
    /// @notice Thrown when a reward pool lacks sufficient balance (reserved for future use).
    error InsufficientPool();
    /// @notice Thrown when a claimant's GI NFT is not approved or not owned by them.
    error NotEligible();
    /// @notice Thrown when a claimant did not vote on the proposal.
    error DidNotVote();
    /// @notice Thrown when a claimant's vote was Abstain (only For/Against earn rewards).
    error AbstainNotEligible();
    /// @notice Thrown when this voter has already claimed for this proposal.
    error AlreadyClaimed();
    /// @notice Thrown when this GI token id has already claimed for this proposal (H-03).
    error AlreadyClaimedByTokenId();
    /// @notice Thrown when a proposal has zero eligible (For+Against) votes.
    error NoVotesYet();
    /// @notice Thrown when claiming after the 180-day reward deadline.
    error RewardClaimExpired();
    /// @notice Thrown when releasing a remainder before the reward deadline has passed.
    error RewardClaimNotExpired();
    /// @notice Thrown when a sweep would exceed the unreserved (non-pool) balance.
    error ExceedsUnreserved();

    modifier onlyDAO() {
        if (msg.sender != address(dao)) revert NotDAO();
        _;
    }

    // -------------------------------------------------------------------------
    // Receive ETH
    // -------------------------------------------------------------------------

    receive() external payable {
        if (msg.value > 0) {
            lifetimeETHReceived += msg.value;
            emit Deposited(address(0), msg.sender, msg.value);
        }
    }

    /// @notice Deposit ETH into the rewards accumulator (identical to a plain transfer).
    function deposit() external payable {
        if (msg.value > 0) {
            lifetimeETHReceived += msg.value;
            emit Deposited(address(0), msg.sender, msg.value);
        }
    }

    // -------------------------------------------------------------------------
    // One-time setters
    // -------------------------------------------------------------------------

    /// @notice Set the DAOLogic reference. Callable once, then locked.
    /// @param _dao The DAOLogic proxy address.
    function setDAOLogic(address _dao) external onlyOwner {
        if (daoLocked) revert AlreadyLocked();
        if (_dao == address(0)) revert InvalidAddress();
        dao = IDAOLogicForRewards(_dao);
        daoLocked = true;
        emit DAOLogicSet(_dao);
    }

    /// @notice Set the ApprovalRegistry reference. Callable once, then locked.
    /// @param _registry The ApprovalRegistry address.
    function setApprovalRegistry(ApprovalRegistry _registry) external onlyOwner {
        if (approvalRegistryLocked) revert AlreadyLocked();
        if (address(_registry) == address(0)) revert InvalidAddress();
        approvalRegistry = _registry;
        approvalRegistryLocked = true;
        emit ApprovalRegistrySet(address(_registry));
    }

    /// @notice Set the per-proposal reward pool size. Governable (owner = DAO via the active escrow).
    /// @param newAmount The new reward amount in wei.
    function setProposalRewardAmount(uint256 newAmount) external onlyOwner {
        uint256 old = proposalRewardAmount;
        proposalRewardAmount = newAmount;
        emit ProposalRewardAmountSet(old, newAmount);
    }

    /// @notice Set the per-vote gas-refund cap. Governable (owner = DAO via the active escrow).
    /// @param newAmount The new per-vote cap in wei.
    function setMaxRefundPerVote(uint256 newAmount) external onlyOwner {
        uint256 old = maxRefundPerVote;
        maxRefundPerVote = newAmount;
        emit MaxRefundPerVoteSet(old, newAmount);
    }

    // -------------------------------------------------------------------------
    // Allocate reward pool (called by DAO on finalize)
    // -------------------------------------------------------------------------

    /// @notice Set aside `proposalRewardAmount` ETH for the given proposal's voter rewards.
    ///         Called by DAOLogic inside finalize(). M-01: allocates against UNRESERVED balance
    ///         (balance - totalReserved) so pools can never collectively exceed the contract's ETH;
    ///         the allocation is reserved and a 180-day claim deadline is set.
    /// @param proposalId The proposal being finalized.
    function allocateProposalReward(uint256 proposalId) external onlyDAO {
        uint256 bal = address(this).balance;
        uint256 unreserved = bal > totalReserved ? bal - totalReserved : 0;
        uint256 desired = proposalRewardAmount;
        uint256 allocated = desired < unreserved ? desired : unreserved;
        proposalRewardPool[proposalId] = allocated;
        remainingRewardPool[proposalId] = allocated;
        totalReserved += allocated;
        rewardDeadline[proposalId] = block.timestamp + CLAIM_PERIOD;
        emit ProposalRewardAllocated(proposalId, allocated);
    }

    // -------------------------------------------------------------------------
    // Voter claim
    // -------------------------------------------------------------------------

    /// @notice Claim your pro-rata voter reward for a proposal. You must hold an approved
    ///         GI NFT (passed as giTokenId) and have voted For or Against on the proposal.
    /// @param proposalId The finalized proposal to claim against.
    /// @param giTokenId The approved GI NFT token id you own and are claiming with.
    function claimVotingReward(uint256 proposalId, uint256 giTokenId) external {
        if (block.timestamp > rewardDeadline[proposalId]) revert RewardClaimExpired();
        if (voterClaimed[proposalId][msg.sender]) revert AlreadyClaimed(); // one claim per voter
        if (claimedByTokenId[proposalId][giTokenId]) revert AlreadyClaimedByTokenId(); // H-03
        if (!approvalRegistry.isEligible(msg.sender, giTokenId)) revert NotEligible();

        (bool hasVoted, uint8 support, uint96 votes) = dao.getReceiptUnpacked(proposalId, msg.sender);
        if (!hasVoted) revert DidNotVote();
        if (support == 2) revert AbstainNotEligible(); // 0=against, 1=for, 2=abstain

        (uint256 forVotes, uint256 againstVotes, ) = dao.proposalVotes(proposalId);
        uint256 totalEligibleVotes = forVotes + againstVotes;
        if (totalEligibleVotes == 0) revert NoVotesYet();

        uint256 share = (proposalRewardPool[proposalId] * votes) / totalEligibleVotes;
        uint256 remaining = remainingRewardPool[proposalId];
        if (share > remaining) share = remaining; // never pay beyond what's left in the pool

        // H-03: set BOTH flags. The token flag stops one NFT authorizing many voters; the voter
        // flag stops one voter claiming twice via multiple approved NFTs.
        voterClaimed[proposalId][msg.sender] = true;
        claimedByTokenId[proposalId][giTokenId] = true;

        if (share > 0) {
            // M-01: decrement the proposal's remainder AND the global reservation by the paid share.
            remainingRewardPool[proposalId] = remaining - share;
            totalReserved -= share;
            (bool ok, ) = msg.sender.call{value: share}("");
            require(ok, "ETH transfer failed");
        }
        emit VoterRewardClaimed(proposalId, msg.sender, giTokenId, share);
    }

    /// @notice After a proposal's 180-day claim deadline, permissionlessly release its UNCLAIMED
    ///         remainder back to unreserved balance (pro-rata pools are rarely fully claimed; this
    ///         avoids locking reserved-unclaimed ETH behind an owner who may never act). M-01.
    /// @param proposalId The proposal whose expired remainder to release.
    function releaseExpiredRewardRemainder(uint256 proposalId) external {
        if (block.timestamp <= rewardDeadline[proposalId]) revert RewardClaimNotExpired();
        uint256 remaining = remainingRewardPool[proposalId];
        if (remaining == 0) return;
        remainingRewardPool[proposalId] = 0;
        totalReserved -= remaining;
        emit RewardRemainderReleased(proposalId, remaining);
    }

    // -------------------------------------------------------------------------
    // Gas refund (called by DAO from castRefundableVote)
    // -------------------------------------------------------------------------

    /// @notice Send a gas refund to a voter. Only callable by DAOLogic. Refund is capped
    ///         at `maxRefundPerVote` regardless of `amount`. If GR has insufficient balance,
    ///         the refund silently sends whatever's available — never reverts (because the
    ///         vote was already recorded; we don't want to undo it).
    /// @param voter The voter to refund.
    /// @param amount The requested refund (capped at `maxRefundPerVote` and unreserved balance).
    function refundGas(address voter, uint256 amount) external onlyDAO {
        uint256 cap = maxRefundPerVote;
        uint256 toSend = amount < cap ? amount : cap;
        // M-01: gas refunds come only from UNRESERVED balance — never from reserved reward pools.
        uint256 bal = address(this).balance;
        uint256 unreserved = bal > totalReserved ? bal - totalReserved : 0;
        if (toSend > unreserved) toSend = unreserved;
        if (toSend == 0) {
            emit GasRefunded(voter, 0, false);
            return;
        }
        (bool ok, ) = voter.call{value: toSend}("");
        emit GasRefunded(voter, toSend, ok);
    }

    // -------------------------------------------------------------------------
    // Shwoun handling (Phase 3 — no-bid auctions transfer NFTs here)
    // -------------------------------------------------------------------------

    /// @notice ERC-721 receiver hook. Accepts any incoming NFT (e.g. a no-bid auction's Shwoun).
    /// @param from The address the NFT came from.
    /// @param tokenId The id of the NFT received.
    /// @return The ERC-721 receiver magic value.
    function onERC721Received(
        address /*operator*/,
        address from,
        uint256 tokenId,
        bytes memory /*data*/
    ) public override returns (bytes4) {
        emit ShwounReceived(tokenId, from);
        return this.onERC721Received.selector;
    }

    /// @notice Transfer a held Shwoun out. Governable (owner = DAO via the active escrow).
    /// @param shwouns The Shwouns token contract.
    /// @param shwounId The Shwoun id to transfer.
    /// @param to The recipient.
    function transferShwoun(IERC721 shwouns, uint256 shwounId, address to) external onlyOwner {
        shwouns.transferFrom(address(this), to, shwounId);
        emit ShwounTransferred(shwounId, to);
    }

    // -------------------------------------------------------------------------
    // Sweep (governance-level recovery)
    // -------------------------------------------------------------------------

    /// @notice Sweep unreserved ETH out. Reverts if `amount` exceeds the unreserved balance.
    ///         Governable (owner = DAO via the active escrow).
    /// @param to The recipient.
    /// @param amount The amount of ETH to sweep.
    function sweepETH(address payable to, uint256 amount) external onlyOwner {
        // M-01: sweeps may only touch UNRESERVED balance — reserved reward pools stay claimable.
        uint256 bal = address(this).balance;
        uint256 unreserved = bal > totalReserved ? bal - totalReserved : 0;
        if (amount > unreserved) revert ExceedsUnreserved();
        (bool ok, ) = to.call{value: amount}('');
        require(ok, 'ETH sweep failed');
        emit ETHSwept(to, amount);
    }

    /// @notice Sweep an ERC-20 balance out. Governable (owner = DAO via the active escrow).
    /// @param token The ERC-20 to sweep.
    /// @param to The recipient.
    /// @param amount The amount to sweep.
    function sweepERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Swept(token, to, amount);
    }

    /// @notice Generic ERC-721 sweep (A8) — lets governance recover NFT residuals routed here by
    ///         rescueFromEscrow. Governance-gated (owner = DAO via the escrow).
    /// @param token The ERC-721 collection.
    /// @param tokenId The token id to sweep.
    /// @param to The recipient.
    function sweepERC721(address token, uint256 tokenId, address to) external onlyOwner {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
        emit ERC721Swept(token, to, tokenId);
    }

    /// @notice Generic ERC-1155 sweep (A8). Governance-gated.
    /// @param token The ERC-1155 collection.
    /// @param id The token id.
    /// @param amount The amount to sweep.
    /// @param to The recipient.
    function sweepERC1155(address token, uint256 id, uint256 amount, address to) external onlyOwner {
        IERC1155(token).safeTransferFrom(address(this), to, id, amount, "");
        emit ERC1155Swept(token, to, id, amount);
    }

    /// @notice The contract's current ETH balance.
    /// @return The ETH balance in wei.
    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
