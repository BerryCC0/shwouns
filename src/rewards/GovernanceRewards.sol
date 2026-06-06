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
    function getReceiptUnpacked(uint256 proposalId, address voter)
        external view returns (bool hasVoted, uint8 support, uint96 votes);
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

    IDAOLogicForRewards public dao;
    ApprovalRegistry public approvalRegistry;
    bool public daoLocked;
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

    event Deposited(address indexed asset, address indexed from, uint256 amount);
    event ShwounReceived(uint256 indexed shwounId, address indexed from);
    event ShwounTransferred(uint256 indexed shwounId, address indexed to);
    event ETHSwept(address indexed to, uint256 amount);
    event ERC20Swept(address indexed token, address indexed to, uint256 amount);
    event ERC721Swept(address indexed token, address indexed to, uint256 tokenId);
    event ERC1155Swept(address indexed token, address indexed to, uint256 id, uint256 amount);

    event DAOLogicSet(address indexed dao);
    event ApprovalRegistrySet(address indexed registry);
    event ProposalRewardAmountSet(uint256 oldAmount, uint256 newAmount);
    event MaxRefundPerVoteSet(uint256 oldAmount, uint256 newAmount);

    event ProposalRewardAllocated(uint256 indexed proposalId, uint256 amount);
    event VoterRewardClaimed(uint256 indexed proposalId, address indexed voter, uint256 indexed giTokenId, uint256 amount);
    event GasRefunded(address indexed voter, uint256 amount, bool sent);
    event RewardRemainderReleased(uint256 indexed proposalId, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error AlreadyLocked();
    error InvalidAddress();
    error NotDAO();
    error InsufficientPool();
    error NotEligible();
    error DidNotVote();
    error AbstainNotEligible();
    error AlreadyClaimed();
    error AlreadyClaimedByTokenId();
    error NoVotesYet();
    error RewardClaimExpired();
    error RewardClaimNotExpired();
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

    function deposit() external payable {
        if (msg.value > 0) {
            lifetimeETHReceived += msg.value;
            emit Deposited(address(0), msg.sender, msg.value);
        }
    }

    // -------------------------------------------------------------------------
    // One-time setters
    // -------------------------------------------------------------------------

    function setDAOLogic(address _dao) external onlyOwner {
        if (daoLocked) revert AlreadyLocked();
        if (_dao == address(0)) revert InvalidAddress();
        dao = IDAOLogicForRewards(_dao);
        daoLocked = true;
        emit DAOLogicSet(_dao);
    }

    function setApprovalRegistry(ApprovalRegistry _registry) external onlyOwner {
        if (approvalRegistryLocked) revert AlreadyLocked();
        if (address(_registry) == address(0)) revert InvalidAddress();
        approvalRegistry = _registry;
        approvalRegistryLocked = true;
        emit ApprovalRegistrySet(address(_registry));
    }

    function setProposalRewardAmount(uint256 newAmount) external onlyOwner {
        uint256 old = proposalRewardAmount;
        proposalRewardAmount = newAmount;
        emit ProposalRewardAmountSet(old, newAmount);
    }

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

    function onERC721Received(
        address /*operator*/,
        address from,
        uint256 tokenId,
        bytes memory /*data*/
    ) public override returns (bytes4) {
        emit ShwounReceived(tokenId, from);
        return this.onERC721Received.selector;
    }

    function transferShwoun(IERC721 shwouns, uint256 shwounId, address to) external onlyOwner {
        shwouns.transferFrom(address(this), to, shwounId);
        emit ShwounTransferred(shwounId, to);
    }

    // -------------------------------------------------------------------------
    // Sweep (governance-level recovery)
    // -------------------------------------------------------------------------

    function sweepETH(address payable to, uint256 amount) external onlyOwner {
        // M-01: sweeps may only touch UNRESERVED balance — reserved reward pools stay claimable.
        uint256 bal = address(this).balance;
        uint256 unreserved = bal > totalReserved ? bal - totalReserved : 0;
        if (amount > unreserved) revert ExceedsUnreserved();
        (bool ok, ) = to.call{value: amount}('');
        require(ok, 'ETH sweep failed');
        emit ETHSwept(to, amount);
    }

    function sweepERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Swept(token, to, amount);
    }

    /// @notice Generic ERC-721 sweep (A8) — lets governance recover NFT residuals routed here by
    ///         rescueFromEscrow. Governance-gated (owner = DAO via the escrow).
    function sweepERC721(address token, uint256 tokenId, address to) external onlyOwner {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
        emit ERC721Swept(token, to, tokenId);
    }

    /// @notice Generic ERC-1155 sweep (A8). Governance-gated.
    function sweepERC1155(address token, uint256 id, uint256 amount, address to) external onlyOwner {
        IERC1155(token).safeTransferFrom(address(this), to, id, amount, "");
        emit ERC1155Swept(token, to, id, amount);
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
