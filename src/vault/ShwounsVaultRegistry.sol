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
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IERC6551Registry} from "./erc6551/interfaces/IERC6551Registry.sol";
import {IShwounsVaultRegistry} from "./IShwounsVaultRegistry.sol";
import {GovernedOwnable} from "../governance/GovernedOwnable.sol";

contract ShwounsVaultRegistry is IShwounsVaultRegistry, GovernedOwnable {
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
    /// @notice True once `vaultImplementation` has been set, after which it can never change.
    bool public vaultImplementationLocked;

    /// @notice The Shwouns DAOLogic. Vaults gate pullProRata on this address. Settable once,
    ///         then locked.
    address public daoLogic;
    /// @notice True once `daoLogic` has been set, after which it can never change.
    bool public daoLogicLocked;

    /// @notice Token IDs whose vaults have been marked active (i.e., received a deposit).
    ///         May contain false positives (vault was funded then drained without notification);
    ///         DAOLogic must re-check current balances at queue time.
    EnumerableSet.UintSet private _activeVaults;

    /// @notice Emitted once when the vault implementation is set and locked.
    event VaultImplementationSet(address indexed impl);
    /// @notice Emitted once when the DAOLogic reference is set and locked.
    event DAOLogicSet(address indexed daoLogic);
    /// @notice Emitted the first time a token's vault enters the active set.
    event VaultMarkedActive(uint256 indexed tokenId);
    /// @notice Reserved for active-set removal; never emitted (the set is append-only).
    event VaultMarkedInactive(uint256 indexed tokenId);

    /// @notice Thrown when a setter or the constructor is given a zero address.
    error InvalidAddress();
    /// @notice Thrown when a one-time setter is called after it has already been locked.
    error AlreadyLocked();
    /// @notice Thrown when `markActive` is called by an address other than the token's own vault.
    error NotAuthorizedVault();
    /// @notice Thrown when `vaultOf`/`createVaultFor` is called before the implementation is set.
    error VaultImplementationNotSet();
    /// @notice Thrown when a vault is requested for a token id that does not exist (C-03 gate).
    error TokenDoesNotExist();

    constructor(address _shwounsToken, address _governanceAuth) GovernedOwnable(_governanceAuth) {
        if (_shwounsToken == address(0)) revert InvalidAddress();
        shwounsToken = _shwounsToken;
    }

    // -------------------------------------------------------------------------
    // One-time setters (lock after first use)
    // -------------------------------------------------------------------------

    /// @notice Set the vault implementation address. Callable once.
    /// @param impl The ShwounsVault implementation address; locked permanently after this call.
    function setVaultImplementation(address impl) external onlyOwner {
        if (vaultImplementationLocked) revert AlreadyLocked();
        if (impl == address(0)) revert InvalidAddress();
        vaultImplementation = impl;
        vaultImplementationLocked = true;
        emit VaultImplementationSet(impl);
    }

    /// @notice Set the DAOLogic address. Callable once.
    /// @param _daoLogic The DAOLogic address vaults will gate `pullProRata` on; locked after this call.
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
    /// @param tokenId The Shwoun token id.
    /// @return The deterministic vault address.
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
    ///         deployed. Called by ShwounsToken on mint; can also be called by anyone post-mint.
    /// @dev C-03: the bound token MUST exist. Without this gate anyone could deploy vaults for
    ///      unminted token IDs and inflate the active set until proposal queueing exceeds block gas.
    /// @param tokenId The Shwoun token id.
    /// @return The vault address (existing if already deployed).
    function createVaultFor(uint256 tokenId) external returns (address) {
        if (vaultImplementation == address(0)) revert VaultImplementationNotSet();
        _requireTokenExists(tokenId);
        return IERC6551Registry(CANONICAL_ERC6551_REGISTRY).createAccount(
            vaultImplementation,
            SALT,
            block.chainid,
            shwounsToken,
            tokenId
        );
    }

    /// @dev C-03 existence gate: the bound token must exist (ownerOf succeeds and is non-zero).
    function _requireTokenExists(uint256 tokenId) internal view {
        try IERC721(shwounsToken).ownerOf(tokenId) returns (address tokenOwner) {
            if (tokenOwner == address(0)) revert TokenDoesNotExist();
        } catch {
            revert TokenDoesNotExist();
        }
    }

    // -------------------------------------------------------------------------
    // Vault → Registry callbacks (active-set maintenance)
    // -------------------------------------------------------------------------

    /// @inheritdoc IShwounsVaultRegistry
    /// @dev C-03 defense-in-depth: only a real, minted token's vault can enter the active set.
    function markActive(uint256 tokenId) external {
        _requireCallerIsVault(tokenId);
        _requireTokenExists(tokenId);
        if (_activeVaults.add(tokenId)) {
            emit VaultMarkedActive(tokenId);
        }
    }

    /// @inheritdoc IShwounsVaultRegistry
    /// @dev M-02: the active set is APPEND-ONLY ("ever funded"). recordSnapshot skips zero-balance
    ///      vaults at snapshot time, so correctness never required removal — and balance-inferred
    ///      removal was the M-02 eviction bug (a zero-ETH but ERC-20-funded vault could be evicted,
    ///      and `withdrawERC20(..., 0)` could grief). Append-only is also the precondition that
    ///      makes the paged queue-freeze sound (M-05): indices [0, freezeTarget) never shift.
    ///      Retained as a no-op for vault-callback / interface compatibility.
    function markPossiblyInactive(uint256) external {}

    /// @dev Auth gate for `markActive`: the caller must be the token's OWN deterministic vault
    ///      address, so a vault can only mark itself (not another token) into the active set.
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
