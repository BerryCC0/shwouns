// SPDX-License-Identifier: GPL-3.0

/// @title ProposalEscrow — per-proposal fund isolation + unique execution identity
///
/// @notice One escrow per proposal. It holds ONLY that proposal's collected assets and executes
///         ALL of the proposal's actions (value-bearing AND governance) from its own unique
///         identity. Because the executing identity is unique per proposal, a lingering approval
///         or a stray output asset is reachable only by the proposal that produced it — closing
///         C-01 (reentrant double-spend across the shared pool) and C-02 (cross-proposal allowance
///         drain) by construction, rather than by balance bookkeeping in a shared arbitrary-call
///         wallet (which is not enforceable isolation).
///
/// @dev Deployed as an EIP-1167 minimal-proxy clone (OpenZeppelin `Clones`, CREATE2 salt =
///      proposalId) of a single non-upgradeable implementation. EIP-1167 clones take no
///      constructor arguments, so the implementation bakes `daoLogic` and `residualSink` as
///      immutables into its runtime; every clone delegatecalls in and reads those immutables. Two
///      consequences the security model relies on:
///        1. ALL clones share one identical runtime codehash — required by DAOLogic's
///           executor-authentication codehash check (constructor-immutable per-escrow instances
///           would each have a distinct codehash and break that check).
///        2. There is deliberately NO `initialize()` anywhere. An initializer on a deterministic
///           clone address would be a front-running/takeover surface (anyone could init it first).
///           The escrow never stores its own proposalId; identity is established by DAOLogic from
///           the CREATE2 address.
///
///      The escrow is a DUMB executor: every entry point requires `msg.sender == daoLogic` (the
///      DAOLogic proxy address, which is upgrade-stable). DAOLogic supplies the action list and is
///      the sole driver of execution, refunds, and residual recovery.
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @notice The slim surface DAOLogic drives. Kept minimal so the library can call it without
///         importing the full contract.
interface IProposalEscrow {
    function daoLogic() external view returns (address);
    function residualSink() external view returns (address);
    function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas) external;
    function payOut(address asset, address to, uint256 amount) external;
    function sweepETHToSink() external;
    function sweepERC20ToSink(address token) external;
    function sweepERC721ToSink(address token, uint256 tokenId) external;
    function sweepERC1155ToSink(address token, uint256 id, uint256 amount) external;
}

contract ProposalEscrow is ERC721Holder, ERC1155Holder {
    using SafeERC20 for IERC20;

    /// @notice The Shwouns DAOLogic proxy — the ONLY address permitted to drive this escrow.
    ///         The proxy address is upgrade-stable, so DAOLogic upgrades never change it.
    address public immutable daoLogic;

    /// @notice The immutable residual sink (GovernanceRewards). Stray residuals recovered via the
    ///         terminal-gated rescue path (added in §A8) go here and nowhere else.
    address public immutable residualSink;

    error NotDAOLogic();
    error LengthMismatch();
    error ExecutionFailed(uint256 index);
    error ETHTransferFailed();
    error ZeroAddress();

    constructor(address _daoLogic, address _residualSink) {
        if (_daoLogic == address(0) || _residualSink == address(0)) revert ZeroAddress();
        daoLogic = _daoLogic;
        residualSink = _residualSink;
    }

    modifier onlyDAOLogic() {
        if (msg.sender != daoLogic) revert NotDAOLogic();
        _;
    }

    /// @notice Accept ETH: from `collect`/`topUp` routing, from swap change, or from funds an
    ///         action returns to the escrow during execution.
    receive() external payable {}

    /// @notice Execute the proposal's actions from this escrow's own identity and balance.
    ///         Callable only by DAOLogic, which sets its global execution lock + `activeProposalId`
    ///         (→ the transient `Executing` status) BEFORE calling, and clears them AFTER this
    ///         returns. Bubbles the first failing action's revert data — DAOLogic must NOT catch it
    ///         — so a failed action atomically rolls back the whole attempt and finalize stays
    ///         retryable.
    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external onlyDAOLogic {
        uint256 n = targets.length;
        if (values.length != n || calldatas.length != n) revert LengthMismatch();
        for (uint256 i = 0; i < n; i++) {
            (bool ok, bytes memory ret) = targets[i].call{ value: values[i] }(calldatas[i]);
            if (!ok) {
                if (ret.length > 0) {
                    assembly { revert(add(ret, 0x20), mload(ret)) }
                }
                revert ExecutionFailed(i);
            }
        }
    }

    /// @notice Pay a specific asset/amount to a recipient. Used ONLY by DAOLogic's contribution
    ///         refund path; the recipient is derived by DAOLogic from the vault registry
    ///         (`vaultOf(shwounId)` — the contributing vault, whose receive() never reverts), never
    ///         caller-supplied. Use `address(0)` for native ETH.
    /// @dev A plain constrained transfer — never an arbitrary call, and it never touches DAOLogic's
    ///      executor authentication.
    function payOut(address asset, address to, uint256 amount) external onlyDAOLogic {
        if (amount == 0) return;
        if (asset == address(0)) {
            (bool ok, ) = to.call{ value: amount }("");
            if (!ok) revert ETHTransferFailed();
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    // -------------------------------------------------------------------------
    // Residual recovery (A8) — typed transfers to the IMMUTABLE residual sink ONLY.
    //
    // Driven by DAOLogic's permissionless, strictly-terminal-gated rescueFromEscrow. These are the
    // ONLY way value leaves a finalized/refunded escrow besides payOut, and they can send ONLY to
    // `residualSink` (the escrow chooses the destination from its own immutable, never a caller-
    // supplied recipient). They never make an arbitrary call and never touch executor authentication.
    // -------------------------------------------------------------------------

    function sweepETHToSink() external onlyDAOLogic {
        uint256 bal = address(this).balance;
        if (bal == 0) return;
        (bool ok, ) = residualSink.call{ value: bal }("");
        if (!ok) revert ETHTransferFailed();
    }

    function sweepERC20ToSink(address token) external onlyDAOLogic {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal == 0) return;
        IERC20(token).safeTransfer(residualSink, bal);
    }

    function sweepERC721ToSink(address token, uint256 tokenId) external onlyDAOLogic {
        IERC721(token).safeTransferFrom(address(this), residualSink, tokenId);
    }

    function sweepERC1155ToSink(address token, uint256 id, uint256 amount) external onlyDAOLogic {
        IERC1155(token).safeTransferFrom(address(this), residualSink, id, amount, "");
    }
}
