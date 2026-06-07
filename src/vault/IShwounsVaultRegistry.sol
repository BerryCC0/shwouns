// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

/// @title Shwouns Vault Registry interface
/// @notice The full external surface of ShwounsVaultRegistry. Vaults call markActive /
///         markPossiblyInactive and read daoLogic. ShwounsToken calls createVaultFor on mint.
///         DAOLogic iterates activeVaults at queue time.
interface IShwounsVaultRegistry {
    // -- Vault → Registry callbacks --

    /// @notice The currently-registered DAOLogic — the only address a vault permits to call
    ///         `pullProRata`. Settable once at deployment, then locked.
    /// @return The DAOLogic address.
    function daoLogic() external view returns (address);

    /// @notice The ShwounsToken whose tokens are bound to each vault.
    /// @return The ShwounsToken address.
    function shwounsToken() external view returns (address);

    /// @notice Callback from a vault on deposit: add the bound token to the active ("ever-funded")
    ///         set. Only callable by the token's own deterministic vault.
    /// @param tokenId The bound Shwoun token id.
    function markActive(uint256 tokenId) external;

    /// @notice Callback from a vault on withdrawal. Retained for vault/interface compatibility; a
    ///         no-op because the active set is append-only (see the implementation's M-02 note).
    /// @param tokenId The bound Shwoun token id.
    function markPossiblyInactive(uint256 tokenId) external;

    // -- Deployment helpers --

    /// @notice The locked ShwounsVault implementation every vault clone points at.
    /// @return The vault implementation address.
    function vaultImplementation() external view returns (address);

    /// @notice The deterministic ERC-6551 account address for a token id (valid before deployment).
    /// @param tokenId The Shwoun token id.
    /// @return The vault address computed from the canonical-registry CREATE2 formula.
    function vaultOf(uint256 tokenId) external view returns (address);

    /// @notice Deploy the vault for a token id (idempotent). Requires the bound token to exist.
    /// @param tokenId The Shwoun token id.
    /// @return The vault address (existing if already deployed).
    function createVaultFor(uint256 tokenId) external returns (address);

    // -- Active-set enumeration (called by DAOLogic at queue time) --

    /// @notice Number of vaults in the append-only active set.
    /// @return The active-set length.
    function activeVaultsLength() external view returns (uint256);

    /// @notice The token id at a given index of the active set.
    /// @param index The active-set index, `[0, activeVaultsLength())`.
    /// @return The Shwoun token id at that index.
    function activeVaultAt(uint256 index) external view returns (uint256);

    /// @notice The full active set (gas-expensive; intended for off-chain reads).
    /// @return The array of active-set token ids.
    function activeVaults() external view returns (uint256[] memory);
}
