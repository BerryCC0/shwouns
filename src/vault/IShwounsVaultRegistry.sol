// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

/// @title Shwouns Vault Registry interface
/// @notice The full external surface of ShwounsVaultRegistry. Vaults call markActive /
///         markPossiblyInactive and read daoLogic. ShwounsToken calls createVaultFor on mint.
///         DAOLogic iterates activeVaults at queue time.
interface IShwounsVaultRegistry {
    // -- Vault → Registry callbacks --
    function daoLogic() external view returns (address);
    function shwounsToken() external view returns (address);
    function markActive(uint256 tokenId) external;
    function markPossiblyInactive(uint256 tokenId) external;

    // -- Deployment helpers --
    function vaultImplementation() external view returns (address);
    function vaultOf(uint256 tokenId) external view returns (address);
    function createVaultFor(uint256 tokenId) external returns (address);

    // -- Active-set enumeration (called by DAOLogic at queue time) --
    function activeVaultsLength() external view returns (uint256);
    function activeVaultAt(uint256 index) external view returns (uint256);
    function activeVaults() external view returns (uint256[] memory);
}
