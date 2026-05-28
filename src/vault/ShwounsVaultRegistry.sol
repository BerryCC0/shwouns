// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

/// @title ShwounsVaultRegistry
/// @notice Single source of truth for per-Noun vault addresses, the active-set, and the
///         currently-authorized DAOLogic. Wraps the canonical ERC-6551 registry (deployed at
///         the same address on every chain) and adds:
///           - markActive/markPossiblyInactive callbacks from vaults to maintain a funded set
///           - daoLogic reference that vaults consult to gate pullProRata
///           - createVaultFor convenience used by ShwounsToken on mint
///
/// Deployment order (must follow this sequence for circular constructor deps):
///   1. Deploy ShwounsToken
///   2. Deploy ShwounsVaultRegistry(token)        — vaultImplementation is unset
///   3. Deploy ShwounsVault impl(registry)        — registry address baked in
///   4. registry.setVaultImplementation(impl)     — locks vaultImplementation forever
///   5. Wire ShwounsToken.setMinter(auctionHouse) etc.
///   6. Deploy ShwounsDAOLogic
///   7. registry.setDAOLogic(daoLogic)            — locks daoLogic forever
///
/// After step 4 and step 7, the registry is fully configured and immutable in practice.

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC6551Registry} from "./erc6551/interfaces/IERC6551Registry.sol";
import {IShwounsVaultRegistry} from "./IShwounsVaultRegistry.sol";

contract ShwounsVaultRegistry is IShwounsVaultRegistry, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice The canonical ERC-6551 Registry. Same address on every major chain per EIP-6551.
    address public constant CANONICAL_ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    /// @notice Salt used for deterministic vault addressing. We use 0 — one vault per (impl, NFT).
    bytes32 public constant SALT = bytes32(0);

    /// @notice The ShwounsToken contract whose tokens are bound to each vault. Immutable.
    address public immutable shwounsToken;

    /// @notice The ShwounsVault implementation contract. Settable once via setVaultImplementation,
    ///         then locked. All vaults are ERC-1167 proxies pointing at this impl.
    address public vaultImplementation;
    bool public vaultImplementationLocked;

    /// @notice The Shwouns DAOLogic. Vaults gate pullProRata on this address. Settable once,
    ///         then locked.
    address public daoLogic;
    bool public daoLogicLocked;

    /// @notice Token IDs whose vaults have been marked active (i.e., received a deposit).
    ///         May contain false positives (vault was funded then drained without notification);
    ///         DAOLogic must re-check current balances at queue time.
    EnumerableSet.UintSet private _activeVaults;

    event VaultImplementationSet(address indexed impl);
    event DAOLogicSet(address indexed daoLogic);
    event VaultMarkedActive(uint256 indexed tokenId);
    event VaultMarkedInactive(uint256 indexed tokenId);

    error InvalidAddress();
    error AlreadyLocked();
    error NotAuthorizedVault();
    error VaultImplementationNotSet();

    constructor(address _shwounsToken) {
        if (_shwounsToken == address(0)) revert InvalidAddress();
        shwounsToken = _shwounsToken;
    }

    // -------------------------------------------------------------------------
    // One-time setters (lock after first use)
    // -------------------------------------------------------------------------

    /// @notice Set the vault implementation address. Callable once.
    function setVaultImplementation(address impl) external onlyOwner {
        if (vaultImplementationLocked) revert AlreadyLocked();
        if (impl == address(0)) revert InvalidAddress();
        vaultImplementation = impl;
        vaultImplementationLocked = true;
        emit VaultImplementationSet(impl);
    }

    /// @notice Set the DAOLogic address. Callable once.
    function setDAOLogic(address _daoLogic) external onlyOwner {
        if (daoLogicLocked) revert AlreadyLocked();
        if (_daoLogic == address(0)) revert InvalidAddress();
        daoLogic = _daoLogic;
        daoLogicLocked = true;
        emit DAOLogicSet(_daoLogic);
    }

    // -------------------------------------------------------------------------
    // Vault address resolution + deployment
    // -------------------------------------------------------------------------

    /// @notice Compute the deterministic vault address for a token ID. Works before the vault
    ///         is actually deployed — the address is determined by the CREATE2 formula.
    function vaultOf(uint256 tokenId) public view returns (address) {
        if (vaultImplementation == address(0)) revert VaultImplementationNotSet();
        return IERC6551Registry(CANONICAL_ERC6551_REGISTRY).account(
            vaultImplementation,
            SALT,
            block.chainid,
            shwounsToken,
            tokenId
        );
    }

    /// @notice Deploy the vault for a token ID. Idempotent — returns existing address if already
    ///         deployed. Called by ShwounsToken in _mintTo; can also be called by anyone post-mint.
    function createVaultFor(uint256 tokenId) external returns (address) {
        if (vaultImplementation == address(0)) revert VaultImplementationNotSet();
        return IERC6551Registry(CANONICAL_ERC6551_REGISTRY).createAccount(
            vaultImplementation,
            SALT,
            block.chainid,
            shwounsToken,
            tokenId
        );
    }

    // -------------------------------------------------------------------------
    // Vault → Registry callbacks (active-set maintenance)
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsVaultRegistry
    function markActive(uint256 tokenId) external {
        _requireCallerIsVault(tokenId);
        if (_activeVaults.add(tokenId)) {
            emit VaultMarkedActive(tokenId);
        }
    }

    /// @inheritdoc IShwounsVaultRegistry
    /// @dev Only removes the vault from the active set if its current ETH balance is zero.
    ///      Vaults may still hold ERC-20s — those are tracked per-asset by DAOLogic at queue time.
    function markPossiblyInactive(uint256 tokenId) external {
        _requireCallerIsVault(tokenId);
        if (msg.sender.balance == 0) {
            if (_activeVaults.remove(tokenId)) {
                emit VaultMarkedInactive(tokenId);
            }
        }
    }

    function _requireCallerIsVault(uint256 tokenId) internal view {
        if (msg.sender != vaultOf(tokenId)) revert NotAuthorizedVault();
    }

    // -------------------------------------------------------------------------
    // Active-set enumeration (used by DAOLogic at queue time)
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsVaultRegistry
    function activeVaultsLength() external view returns (uint256) {
        return _activeVaults.length();
    }

    /// @inheritdoc IShwounsVaultRegistry
    function activeVaultAt(uint256 index) external view returns (uint256) {
        return _activeVaults.at(index);
    }

    /// @inheritdoc IShwounsVaultRegistry
    /// @dev Gas-expensive for large sets. Prefer paginated iteration via activeVaultAt
    ///      in on-chain contexts; this is for off-chain reads.
    function activeVaults() external view returns (uint256[] memory) {
        return _activeVaults.values();
    }
}
