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

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { ERC721Holder } from '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import { ApprovalRegistry } from './ApprovalRegistry.sol';

/// @dev Minimal interface for the bits of DAOLogic that GR reads from. Uses *Unpacked
///      naming to avoid clashing with DAOLogic's existing struct-returning getReceipt.
interface IDAOLogicForRewards {
    function getReceiptUnpacked(uint256 proposalId, address voter)
        external view returns (bool hasVoted, uint8 support, uint96 votes);
    function proposalVotes(uint256 proposalId)
        external view returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes);
}

contract GovernanceRewards is Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

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

    /// @notice ETH set aside for a given proposal's voter rewards.
    mapping(uint256 => uint256) public proposalRewardPool;
    /// @notice Per-(proposal, voter) claimed flag.
    mapping(uint256 => mapping(address => bool)) public voterClaimed;

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

    event DAOLogicSet(address indexed dao);
    event ApprovalRegistrySet(address indexed registry);
    event ProposalRewardAmountSet(uint256 oldAmount, uint256 newAmount);
    event MaxRefundPerVoteSet(uint256 oldAmount, uint256 newAmount);

    event ProposalRewardAllocated(uint256 indexed proposalId, uint256 amount);
    event VoterRewardClaimed(uint256 indexed proposalId, address indexed voter, uint256 indexed giTokenId, uint256 amount);
    event GasRefunded(address indexed voter, uint256 amount, bool sent);

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
    error NoVotesYet();

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
    ///         Called by DAOLogic inside finalize(). If GR's balance is insufficient,
    ///         allocates whatever's available (could be 0 — no rewards for that proposal).
    function allocateProposalReward(uint256 proposalId) external onlyDAO {
        uint256 desired = proposalRewardAmount;
        uint256 available = address(this).balance;
        uint256 allocated = desired < available ? desired : available;
        proposalRewardPool[proposalId] = allocated;
        emit ProposalRewardAllocated(proposalId, allocated);
    }

    // -------------------------------------------------------------------------
    // Voter claim
    // -------------------------------------------------------------------------

    /// @notice Claim your pro-rata voter reward for a proposal. You must hold an approved
    ///         GI NFT (passed as giTokenId) and have voted For or Against on the proposal.
    function claimVotingReward(uint256 proposalId, uint256 giTokenId) external {
        if (voterClaimed[proposalId][msg.sender]) revert AlreadyClaimed();
        if (!approvalRegistry.isEligible(msg.sender, giTokenId)) revert NotEligible();

        (bool hasVoted, uint8 support, uint96 votes) = dao.getReceiptUnpacked(proposalId, msg.sender);
        if (!hasVoted) revert DidNotVote();
        if (support == 2) revert AbstainNotEligible(); // 0=against, 1=for, 2=abstain

        (uint256 forVotes, uint256 againstVotes, ) = dao.proposalVotes(proposalId);
        uint256 totalEligibleVotes = forVotes + againstVotes;
        if (totalEligibleVotes == 0) revert NoVotesYet();

        uint256 pool = proposalRewardPool[proposalId];
        uint256 share = (pool * votes) / totalEligibleVotes;

        voterClaimed[proposalId][msg.sender] = true;
        if (share > 0) {
            (bool ok, ) = msg.sender.call{value: share}("");
            require(ok, "ETH transfer failed");
        }
        emit VoterRewardClaimed(proposalId, msg.sender, giTokenId, share);
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
        uint256 available = address(this).balance;
        if (toSend > available) toSend = available;
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
        (bool ok, ) = to.call{value: amount}('');
        require(ok, 'ETH sweep failed');
        emit ETHSwept(to, amount);
    }

    function sweepERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Swept(token, to, amount);
    }

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
