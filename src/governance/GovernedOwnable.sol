// SPDX-License-Identifier: GPL-3.0

/// @title GovernedOwnable — Ownable whose owner-gated functions also accept the active escrow
///
/// @notice An `Ownable` variant whose `onlyOwner` functions are ALSO callable by the currently-
///         authenticated active proposal escrow (resolved through the fail-closed
///         GovernanceAuthRegistry). This is how an approved governance action — executing from its
///         own per-proposal escrow — manages a DAO-owned contract, without any standing EOA
///         authority. Used by the six non-upgradeable governed contracts (A5). The upgradeable
///         AuctionHouse applies the same rule inline against OwnableUpgradeable.
///
/// @dev Stateless beyond an `immutable governanceAuth` reference — immutables live in contract
///      bytecode, not storage, so this adds NO storage slot (safe for every governed contract,
///      including ones whose layout matters). `governanceAuth == address(0)` reduces behavior to
///      plain Ownable (used by unit/test setups that don't exercise governance).
pragma solidity ^0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IGovernanceAuthRegistry } from "./GovernanceAuthRegistry.sol";

abstract contract GovernedOwnable is Ownable {
    IGovernanceAuthRegistry public immutable governanceAuth;

    constructor(address _governanceAuth) {
        governanceAuth = IGovernanceAuthRegistry(_governanceAuth);
    }

    error OwnerMustBeDAOOrZero();

    /// @dev Accept the structural owner OR the active proposal escrow. Mirrors OZ's revert message
    ///      so existing integrations/tests that match on it keep working.
    function _checkOwner() internal view virtual override {
        if (msg.sender == owner()) return;
        if (address(governanceAuth) != address(0) && governanceAuth.isActiveExecutor(msg.sender)) return;
        revert("Ownable: caller is not the owner");
    }

    /// @notice A10.5: once the auth registry is bound (post-bootstrap), ownership may only move to
    ///         the canonical DAO or to address(0) — never to an EOA. Before binding (the bootstrap
    ///         window, when only the trusted Bootstrap coordinator owns these contracts) this is
    ///         standard Ownable, so Bootstrap can wire and hand off. renounceOwnership (→ zero) is
    ///         always permitted.
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        if (address(governanceAuth) != address(0)) {
            address dao = governanceAuth.daoLogic();
            if (dao != address(0) && newOwner != dao && newOwner != address(0)) {
                revert OwnerMustBeDAOOrZero();
            }
        }
        _transferOwnership(newOwner);
    }
}
