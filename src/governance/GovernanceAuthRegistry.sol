// SPDX-License-Identifier: GPL-3.0

/// @title GovernanceAuthRegistry — fail-closed indirection for executor authentication
///
/// @notice The single place every governed contract consults to learn whether a caller is the
///         currently-authenticated active proposal escrow. It exists so the governed contracts can
///         take an `immutable governanceAuth` reference at CONSTRUCTION even though the DAOLogic
///         proxy is deployed AFTER them: the registry is deployed FIRST (by the Bootstrap
///         coordinator, which is its immutable binder), referenced by every governed contract, and
///         bound to the DAOLogic proxy exactly once afterwards.
///
/// @dev Authorization is the one thing that must NEVER fail open. The forward to DAOLogic is
///      therefore defensive: while unbound it returns false; once bound, a revert / short /
///      malformed / non-true return all resolve to false; only a well-formed boolean `true`
///      authorizes. The DAOLogic address, once bound, is permanent (no setter, no re-bind).
pragma solidity ^0.8.19;

interface IGovernanceAuthRegistry {
    function isActiveExecutor(address candidate) external view returns (bool);
    function daoLogic() external view returns (address);
}

/// @dev Minimal view of DAOLogic's canonical executor predicate (kept separate to avoid importing
///      the facade into every governed contract).
interface IDAOLogicExecutor {
    function isActiveExecutor(address candidate) external view returns (bool);
}

contract GovernanceAuthRegistry is IGovernanceAuthRegistry {
    /// @notice The only address permitted to bind DAOLogic — the registry's deployer (the Bootstrap
    ///         coordinator in production; the deploy/test harness otherwise).
    address public immutable binder;

    /// @notice The bound DAOLogic proxy (the canonical DAO). Zero until bound, then permanent.
    address public daoLogic;

    event DAOLogicBound(address indexed daoLogic);

    error NotBinder();
    error AlreadyBound();
    error NotDeployed();

    constructor() {
        binder = msg.sender;
    }

    /// @notice Bind the DAOLogic proxy. Only the binder, exactly once, to a nonzero DEPLOYED proxy.
    function bindDAOLogic(address _daoLogic) external {
        if (msg.sender != binder) revert NotBinder();
        if (daoLogic != address(0)) revert AlreadyBound();
        if (_daoLogic == address(0) || _daoLogic.code.length == 0) revert NotDeployed();
        daoLogic = _daoLogic;
        emit DAOLogicBound(_daoLogic);
    }

    /// @notice Fail-closed forward to DAOLogic's transient executor state.
    function isActiveExecutor(address candidate) external view returns (bool) {
        address dao = daoLogic;
        if (dao == address(0)) return false; // unbound → unauthorized
        (bool ok, bytes memory ret) = dao.staticcall(
            abi.encodeWithSelector(IDAOLogicExecutor.isActiveExecutor.selector, candidate)
        );
        // revert / short / malformed-length → unauthorized. Decode as uint256 and require exactly 1
        // so a non-canonical boolean encoding can never authorize (and never reverts here).
        if (!ok || ret.length != 32) return false;
        return abi.decode(ret, (uint256)) == 1;
    }
}
