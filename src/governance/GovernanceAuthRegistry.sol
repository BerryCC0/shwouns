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
    /// @notice Whether `candidate` is the currently-authenticated active proposal escrow.
    /// @param candidate The address to test (typically `msg.sender` of a governed contract).
    /// @return True only while `candidate` is the escrow of the proposal mid-finalize; false otherwise.
    function isActiveExecutor(address candidate) external view returns (bool);

    /// @notice The bound DAOLogic proxy (the canonical DAO). Zero until bound, then permanent.
    /// @return The DAOLogic proxy address, or `address(0)` if not yet bound.
    function daoLogic() external view returns (address);
}

/// @dev Minimal view of DAOLogic's canonical executor predicate (kept separate to avoid importing
///      the facade into every governed contract).
interface IDAOLogicExecutor {
    /// @notice DAOLogic's canonical executor predicate (the source of truth this registry forwards to).
    /// @param candidate The address to test.
    /// @return True iff `candidate` is the escrow of the proposal currently under the execution lock.
    function isActiveExecutor(address candidate) external view returns (bool);
}

contract GovernanceAuthRegistry is IGovernanceAuthRegistry {
    /// @notice The only address permitted to bind DAOLogic — the registry's deployer (the Bootstrap
    ///         coordinator in production; the deploy/test harness otherwise).
    address public immutable binder;

    /// @notice The bound DAOLogic proxy (the canonical DAO). Zero until bound, then permanent.
    address public daoLogic;

    /// @notice Emitted once, when the DAOLogic proxy is permanently bound.
    event DAOLogicBound(address indexed daoLogic);

    /// @notice Thrown when a non-binder calls `bindDAOLogic`.
    error NotBinder();
    /// @notice Thrown when `bindDAOLogic` is called after DAOLogic has already been bound.
    error AlreadyBound();
    /// @notice Thrown when the bind target is the zero address or has no deployed code.
    error NotDeployed();

    constructor() {
        binder = msg.sender;
    }

    /// @notice Bind the DAOLogic proxy. Only the binder, exactly once, to a nonzero DEPLOYED proxy.
    /// @param _daoLogic The canonical DAOLogic proxy address to bind permanently.
    function bindDAOLogic(address _daoLogic) external {
        if (msg.sender != binder) revert NotBinder();
        if (daoLogic != address(0)) revert AlreadyBound();
        if (_daoLogic == address(0) || _daoLogic.code.length == 0) revert NotDeployed();
        daoLogic = _daoLogic;
        emit DAOLogicBound(_daoLogic);
    }

    /// @notice Fail-closed forward to DAOLogic's transient executor state.
    /// @param candidate The address to test (typically the `msg.sender` of a governed contract).
    /// @return True only if DAOLogic is bound AND returns a canonical boolean `true` for `candidate`;
    ///         a revert, short return, malformed length, or non-`true` value all resolve to false.
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
