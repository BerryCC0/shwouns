// SPDX-License-Identifier: GPL-3.0

/// @title Shwouns DAO dynamic-quorum checkpoint-admin library
///
/// @notice Split out of ShwounsDAOLogic to keep the facade under EIP-170 (audit F1). Holds ONLY the
///         dynamic-quorum CHECKPOINT-ADMIN: the bounds-checked setters that write a new
///         DynamicQuorumParamsCheckpoint, and the min/max absolute-vote views. The hot-path quorum
///         COMPUTE (quorumVotes / _getDynamicQuorumParamsAt) deliberately stays in
///         ShwounsDAOProposals so `state()` keeps an internal JUMP, not a cross-library delegatecall.
///
/// @dev Delegatecalled by the facade on the same `ds` storage (via `using ... for Storage`), so all
///      writes land in the proxy's storage exactly as the inline facade code did. Bounds, errors and
///      events mirror the originals byte-for-byte (event topics match ShwounsDAOEvents).

pragma solidity ^0.8.19;

import { ShwounsDAOTypes } from "./ShwounsDAOInterfaces.sol";

library ShwounsDAOQuorum {
    // Dynamic-quorum BPS bounds (Nouns parity, from NounsDAOAdmin).
    uint16 internal constant MIN_QUORUM_VOTES_BPS_LOWER_BOUND = 200;
    uint16 internal constant MIN_QUORUM_VOTES_BPS_UPPER_BOUND = 2_000;
    uint16 internal constant MAX_QUORUM_VOTES_BPS_UPPER_BOUND = 6_000;

    error InvalidMinQuorumVotesBPS();
    error InvalidMaxQuorumVotesBPS();
    error MinQuorumBPSGreaterThanMaxQuorumBPS();

    // Re-declared so the library can emit them; topics match ShwounsDAOEvents.
    event MinQuorumVotesBPSSet(uint16 oldMinQuorumVotesBPS, uint16 newMinQuorumVotesBPS);
    event MaxQuorumVotesBPSSet(uint16 oldMaxQuorumVotesBPS, uint16 newMaxQuorumVotesBPS);
    event QuorumCoefficientSet(uint32 oldQuorumCoefficient, uint32 newQuorumCoefficient);

    /// @notice Set all three dynamic-quorum params (bounds-checked). The facade's onlyAdmin wrapper
    ///         calls this; `initialize` also calls it directly to seed the first checkpoint, so the
    ///         bounds validation runs at init too.
    function setDynamicQuorumParams(
        ShwounsDAOTypes.Storage storage ds,
        uint16 newMinQuorumVotesBPS,
        uint16 newMaxQuorumVotesBPS,
        uint32 newQuorumCoefficient
    ) public {
        _setDynamicQuorumParams(ds, newMinQuorumVotesBPS, newMaxQuorumVotesBPS, newQuorumCoefficient);
    }

    /// @dev Bounds-checked checkpoint write. Internal so the public setters above share it without an
    ///      extra delegatecall hop.
    function _setDynamicQuorumParams(
        ShwounsDAOTypes.Storage storage ds,
        uint16 newMinQuorumVotesBPS,
        uint16 newMaxQuorumVotesBPS,
        uint32 newQuorumCoefficient
    ) internal {
        if (
            newMinQuorumVotesBPS < MIN_QUORUM_VOTES_BPS_LOWER_BOUND ||
            newMinQuorumVotesBPS > MIN_QUORUM_VOTES_BPS_UPPER_BOUND
        ) revert InvalidMinQuorumVotesBPS();
        if (newMaxQuorumVotesBPS > MAX_QUORUM_VOTES_BPS_UPPER_BOUND) revert InvalidMaxQuorumVotesBPS();
        if (newMinQuorumVotesBPS > newMaxQuorumVotesBPS) revert MinQuorumBPSGreaterThanMaxQuorumBPS();

        ShwounsDAOTypes.DynamicQuorumParams memory old = latestDynamicQuorumParams(ds);
        _writeQuorumParamsCheckpoint(
            ds,
            ShwounsDAOTypes.DynamicQuorumParams({
                minQuorumVotesBPS: newMinQuorumVotesBPS,
                maxQuorumVotesBPS: newMaxQuorumVotesBPS,
                quorumCoefficient: newQuorumCoefficient
            })
        );
        emit MinQuorumVotesBPSSet(old.minQuorumVotesBPS, newMinQuorumVotesBPS);
        emit MaxQuorumVotesBPSSet(old.maxQuorumVotesBPS, newMaxQuorumVotesBPS);
        emit QuorumCoefficientSet(old.quorumCoefficient, newQuorumCoefficient);
    }

    // -- Individual dynamic-quorum setters (V4 parity; each writes a new checkpoint via the
    //    bounds-checked combined setter, leaving the other two params unchanged) --

    function setMinQuorumVotesBPS(ShwounsDAOTypes.Storage storage ds, uint16 newMinQuorumVotesBPS) external {
        ShwounsDAOTypes.DynamicQuorumParams memory p = latestDynamicQuorumParams(ds);
        _setDynamicQuorumParams(ds, newMinQuorumVotesBPS, p.maxQuorumVotesBPS, p.quorumCoefficient);
    }

    function setMaxQuorumVotesBPS(ShwounsDAOTypes.Storage storage ds, uint16 newMaxQuorumVotesBPS) external {
        ShwounsDAOTypes.DynamicQuorumParams memory p = latestDynamicQuorumParams(ds);
        _setDynamicQuorumParams(ds, p.minQuorumVotesBPS, newMaxQuorumVotesBPS, p.quorumCoefficient);
    }

    function setQuorumCoefficient(ShwounsDAOTypes.Storage storage ds, uint32 newQuorumCoefficient) external {
        ShwounsDAOTypes.DynamicQuorumParams memory p = latestDynamicQuorumParams(ds);
        _setDynamicQuorumParams(ds, p.minQuorumVotesBPS, p.maxQuorumVotesBPS, newQuorumCoefficient);
    }

    /// @notice Current minimum quorum in absolute votes (minQuorumVotesBPS of total supply).
    function minQuorumVotes(ShwounsDAOTypes.Storage storage ds) external view returns (uint256) {
        return (ds.shwouns.totalSupply() * latestDynamicQuorumParams(ds).minQuorumVotesBPS) / 10000;
    }

    /// @notice Current maximum quorum in absolute votes (maxQuorumVotesBPS of total supply).
    function maxQuorumVotes(ShwounsDAOTypes.Storage storage ds) external view returns (uint256) {
        return (ds.shwouns.totalSupply() * latestDynamicQuorumParams(ds).maxQuorumVotesBPS) / 10000;
    }

    function latestDynamicQuorumParams(ShwounsDAOTypes.Storage storage ds)
        internal
        view
        returns (ShwounsDAOTypes.DynamicQuorumParams memory)
    {
        uint256 len = ds.quorumParamsCheckpoints.length;
        if (len == 0) return ShwounsDAOTypes.DynamicQuorumParams(0, 0, 0);
        return ds.quorumParamsCheckpoints[len - 1].params;
    }

    function _writeQuorumParamsCheckpoint(
        ShwounsDAOTypes.Storage storage ds,
        ShwounsDAOTypes.DynamicQuorumParams memory params
    ) internal {
        uint256 len = ds.quorumParamsCheckpoints.length;
        if (len > 0 && ds.quorumParamsCheckpoints[len - 1].fromBlock == block.number) {
            ds.quorumParamsCheckpoints[len - 1].params = params;
        } else {
            ds.quorumParamsCheckpoints.push(
                ShwounsDAOTypes.DynamicQuorumParamsCheckpoint({
                    fromBlock: uint32(block.number),
                    params: params
                })
            );
        }
    }
}
