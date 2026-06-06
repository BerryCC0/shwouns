// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

/// @title ShwounsVault — per-Noun token-bound vault
/// @notice Forked from Tokenbound AccountV3 (https://github.com/tokenbound/contracts).
///   Removed: Lockable, Overridable, ERC4337Account, NestedAccountExecutor, OPAddressAliasHelper,
///            IAccountGuardian, ERC2771Context meta-tx forwarding.
///   Added: deposit/withdraw for ETH and ERC-20, pullProRata hook for DAOLogic, registry callbacks.
///
/// Security model:
///   - Anyone can deposit ETH or ERC-20s to a vault.
///   - The current owner of the bound Noun NFT (and any addresses they have granted permission to
///     via Permissioned) can withdraw and call arbitrary contracts via the inherited execute*
///     functions. This enables warm/cold wallet splits, council multisigs, and yield managers.
///   - The currently-configured DAOLogic (looked up via the immutable VaultRegistry) is the only
///     address that may call pullProRata. This drains a proposal's pro-rata share from this vault.
///   - There is no override/lock mechanism the owner can use to block pullProRata. Their recourse
///     is to withdraw funds before a proposal queues; the snapshot taken at queue caps the draw.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "erc6551/lib/ERC6551AccountLib.sol";
import "erc6551/interfaces/IERC6551Account.sol";

import "./abstract/Permissioned.sol";
import "./abstract/ERC6551Account.sol";
import "./abstract/execution/ERC6551Executor.sol";
import "./abstract/execution/BatchExecutor.sol";
import "./utils/Errors.sol";
import "./IShwounsVaultRegistry.sol";

contract ShwounsVault is
    ERC721Holder,
    ERC1155Holder,
    Permissioned,
    ERC6551Account,
    ERC6551Executor,
    BatchExecutor
{
    using SafeERC20 for IERC20;

    /// @notice The Shwouns VaultRegistry. Immutable per impl deployment.
    IShwounsVaultRegistry public immutable vaultRegistry;

    error InvalidVaultRegistry();
    error NotDAOLogic();
    error InsufficientBalance();
    error ETHTransferFailed();
    // OwnershipCycle, NotAuthorized, InvalidInput inherited from utils/Errors.sol

    event Deposited(address indexed asset, address indexed from, uint256 amount);
    event Withdrawn(address indexed asset, address indexed to, uint256 amount);
    event ProRataPulled(uint256 indexed proposalId, address indexed asset, address indexed recipient, uint256 amount);

    constructor(address _vaultRegistry) {
        if (_vaultRegistry == address(0)) revert InvalidVaultRegistry();
        vaultRegistry = IShwounsVaultRegistry(_vaultRegistry);
    }

    // -------------------------------------------------------------------------
    // Receive / deposit
    // -------------------------------------------------------------------------

    /// @dev Receive plain ETH transfers. Counts as a deposit; notifies registry.
    receive() external payable override {
        if (msg.value > 0) {
            emit Deposited(address(0), msg.sender, msg.value);
            _notifyActive();
        }
    }

    /// @notice Deposit ETH explicitly (identical to plain transfer, kept for ABI clarity).
    function deposit() external payable {
        if (msg.value > 0) {
            emit Deposited(address(0), msg.sender, msg.value);
            _notifyActive();
        }
    }

    /// @notice Deposit an ERC-20. Caller must have approved the vault first.
    function depositERC20(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(token, msg.sender, amount);
        if (amount > 0) _notifyActive();
    }

    // -------------------------------------------------------------------------
    // Withdraw
    // -------------------------------------------------------------------------

    /// @notice Withdraw ETH to a recipient. Restricted to owner or permissioned address.
    function withdraw(address recipient, uint256 amount) external {
        if (!_isValidExecutor(_msgSender())) revert NotAuthorized();
        _beforeExecute();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool ok, ) = recipient.call{value: amount}("");
        if (!ok) revert ETHTransferFailed();
        emit Withdrawn(address(0), recipient, amount);
        _notifyPossiblyInactive();
    }

    /// @notice Withdraw an ERC-20 to a recipient. Restricted to owner or permissioned address.
    function withdrawERC20(address token, address recipient, uint256 amount) external {
        if (!_isValidExecutor(_msgSender())) revert NotAuthorized();
        _beforeExecute();
        IERC20(token).safeTransfer(recipient, amount);
        emit Withdrawn(token, recipient, amount);
        _notifyPossiblyInactive();
    }

    /// @notice Batch withdraw multiple ERC-20s to a single recipient.
    function withdrawERC20s(
        address[] calldata tokens,
        address recipient,
        uint256[] calldata amounts
    ) external {
        if (!_isValidExecutor(_msgSender())) revert NotAuthorized();
        if (tokens.length != amounts.length) revert InvalidInput();
        _beforeExecute();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(recipient, amounts[i]);
            emit Withdrawn(tokens[i], recipient, amounts[i]);
        }
        _notifyPossiblyInactive();
    }

    // -------------------------------------------------------------------------
    // pullProRata — governance hook
    // -------------------------------------------------------------------------

    /// @notice Pull a specific amount of an asset to a recipient. Only callable by the currently
    ///         registered DAOLogic. Used during proposal execution to drain a vault's pro-rata
    ///         share, capped at the queue-time snapshot vs current balance.
    /// @param proposalId The proposal driving this pull. Logged for indexer correlation.
    /// @param asset The asset to transfer. Use address(0) for native ETH.
    /// @param recipient The proposal target receiving the funds.
    /// @param amount The amount to transfer. DAOLogic computes this from the snapshot pro-rata share.
    function pullProRata(uint256 proposalId, address asset, address recipient, uint256 amount) external {
        if (msg.sender != vaultRegistry.daoLogic()) revert NotDAOLogic();
        _updateState();

        if (asset == address(0)) {
            if (address(this).balance < amount) revert InsufficientBalance();
            (bool ok, ) = recipient.call{value: amount}("");
            if (!ok) revert ETHTransferFailed();
        } else {
            IERC20(asset).safeTransfer(recipient, amount);
        }

        emit ProRataPulled(proposalId, asset, recipient, amount);
        _notifyPossiblyInactive();
    }

    // -------------------------------------------------------------------------
    // Inherited from AccountV3 — owner / signer / executor authorization
    // -------------------------------------------------------------------------

    /// @notice Returns the current Noun NFT owner. Zero if the bound token doesn't exist on this chain.
    function owner() public view virtual returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = ERC6551AccountLib.token();
        return _tokenOwner(chainId, tokenContract, tokenId);
    }

    /// @inheritdoc ERC6551Account
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Receiver, ERC6551Account, ERC6551Executor)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Revert if the NFT being transferred IN is the same one this account is bound to.
    function onERC721Received(address, address, uint256 tokenId, bytes memory)
        public
        virtual
        override
        returns (bytes4)
    {
        (uint256 chainId, address tokenContract, uint256 _tokenId) = ERC6551AccountLib.token();
        if (msg.sender == tokenContract && tokenId == _tokenId && chainId == block.chainid) {
            revert OwnershipCycle();
        }
        return this.onERC721Received.selector;
    }

    function _isValidSigner(address signer, bytes memory)
        internal
        view
        virtual
        override
        returns (bool)
    {
        (uint256 chainId, address tokenContract, uint256 tokenId) = ERC6551AccountLib.token();
        address _owner = _tokenOwner(chainId, tokenContract, tokenId);
        if (signer == _owner) return true;
        return hasPermission(signer, _owner);
    }

    /// @dev ERC-1271 signature validation: ECDSA or smart-contract signatures (v=0).
    ///      L-01: malformed/short input returns false (the wrapper then returns a non-magic value),
    ///      never reverts — integrations rely on ERC-1271 returning "invalid", not throwing. This is
    ///      a deliberate divergence from upstream Tokenbound AccountV3, which read signature[64] and
    ///      dynamic offsets without bounds checks (this file is a fork).
    function _isValidSignature(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        override
        returns (bool)
    {
        // Need at least 65 bytes before reading signature[64].
        if (signature.length < 65) return false;

        // Smart-contract signature: v == 0 encodes (signer in r, sig offset in s)
        uint8 v = uint8(signature[64]);
        address signer;

        if (v == 0) {
            signer = address(uint160(uint256(bytes32(signature[:32]))));
            // The embedded offset must be in-bounds before slicing, else treat as invalid.
            uint256 offset = uint256(bytes32(signature[32:64]));
            if (offset > signature.length) return false;
            if (!_isValidSigner(signer, "") && signer != address(this)) {
                return false;
            }
            bytes calldata _signature = signature[offset:];
            return SignatureChecker.isValidERC1271SignatureNow(signer, hash, _signature);
        }

        ECDSA.RecoverError _error;
        (signer, _error) = ECDSA.tryRecover(hash, signature);
        if (_error != ECDSA.RecoverError.NoError) return false;
        return _isValidSigner(signer, "");
    }

    function _isValidExecutor(address executor) internal view virtual override returns (bool) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = ERC6551AccountLib.token();
        address _owner = _tokenOwner(chainId, tokenContract, tokenId);
        if (executor == _owner) return true;
        return hasPermission(executor, _owner);
    }

    function _rootTokenOwner(uint256 chainId, address tokenContract, uint256 tokenId)
        internal
        view
        virtual
        override(Permissioned)
        returns (address)
    {
        // Simplified: no nested-account traversal. The Noun owner IS the root owner.
        return _tokenOwner(chainId, tokenContract, tokenId);
    }

    function _tokenOwner(uint256 chainId, address tokenContract, uint256 tokenId)
        internal
        view
        virtual
        returns (address)
    {
        if (chainId != block.chainid) return address(0);
        if (tokenContract.code.length == 0) return address(0);
        try IERC721(tokenContract).ownerOf(tokenId) returns (address _owner) {
            return _owner;
        } catch {
            return address(0);
        }
    }

    function _beforeExecute() internal virtual override {
        _updateState();
    }

    function _updateState() internal virtual {
        _state = uint256(keccak256(abi.encode(_state, _msgData())));
    }

    function _beforeSetPermissions() internal virtual override {
        _updateState();
    }

    // -------------------------------------------------------------------------
    // Registry notifications (active-set hints)
    // -------------------------------------------------------------------------

    function _notifyActive() internal {
        (, , uint256 tokenId) = ERC6551AccountLib.token();
        try vaultRegistry.markActive(tokenId) {} catch {}
    }

    function _notifyPossiblyInactive() internal {
        (, , uint256 tokenId) = ERC6551AccountLib.token();
        try vaultRegistry.markPossiblyInactive(tokenId) {} catch {}
    }
}
