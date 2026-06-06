// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {LifecycleInvariantsTest} from "./LifecycleInvariants.t.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";

/// @title M-05 — paged queue-time vault-set freeze for sets larger than the in-queue batch (256).
contract ActiveSetPagingTest is LifecycleInvariantsTest {
    /// @dev Mint `count` real Shwouns (so C-03's existence gate is satisfied) and fund each vault
    ///      1 wei so it enters the append-only active set. Minted to this contract (the minter).
    function _inflateActiveSet(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            uint256 id = token.mint(); // this test contract is the minter
            address v = registry.createVaultFor(id);
            vm.deal(address(this), 1 wei);
            (bool ok, ) = v.call{value: 1 wei}("");
            require(ok, "fund");
        }
    }

    /// @dev Inflation raises total supply (so dynamic quorum rises); delegate this contract's
    ///      minted voting power to alice so her proposal still meets quorum.
    function _inflateAndEmpowerAlice(uint256 count) internal {
        _inflateActiveSet(count);
        token.delegate(alice); // this contract delegates its minted Shwouns to alice
        vm.roll(block.number + 1); // checkpoint the delegation before any proposal's startBlock
    }

    function test_m05_pagedFreeze_gatesRecordSnapshot_untilComplete() public {
        _inflateAndEmpowerAlice(260); // base 3 + 260 = 263 active vaults (> FREEZE_BATCH_AT_QUEUE)
        uint256 total = registry.activeVaultsLength();
        assertGt(total, 256, "active set exceeds the in-queue freeze batch");

        uint256 pid = _proposeETH(alice, recipientA, 1 ether);
        _passToSucceeded(pid);
        dao.queue(pid);

        // queue froze only the first 256; the freeze target is the full active-set length at queue.
        (, uint256 target) = dao.snapshotProgress(pid);
        assertEq(target, total, "freeze target = active-set length at queue");

        // recordSnapshot is gated until the freeze completes.
        vm.expectRevert(ShwounsDAOProposals.FreezeNotComplete.selector);
        dao.recordSnapshot(pid, 10);

        // Page the remainder of the freeze across bounded calls; still gated until done.
        dao.freezeVaults(pid, 4); // 256 -> 260, still < 263
        vm.expectRevert(ShwounsDAOProposals.FreezeNotComplete.selector);
        dao.recordSnapshot(pid, 10);

        dao.freezeVaults(pid, 100); // 260 -> 263 (capped at target), freeze complete
        // A further freeze call reverts (nothing left).
        vm.expectRevert(ShwounsDAOProposals.FreezeAlreadyComplete.selector);
        dao.freezeVaults(pid, 1);

        // Now recordSnapshot proceeds and pages the full frozen membership.
        dao.recordSnapshot(pid, 100000);
        (uint256 progress, ) = dao.snapshotProgress(pid);
        assertEq(progress, total, "snapshot pages the entire frozen set");
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Snapshotted));
    }

    function test_m05_vaultActivatedAfterQueue_isExcludedFromFrozenSet() public {
        _inflateAndEmpowerAlice(260);
        uint256 targetAtQueue = registry.activeVaultsLength();

        uint256 pid = _proposeETH(alice, recipientA, 1 ether);
        _passToSucceeded(pid);
        dao.queue(pid);

        // A brand-new funded vault activated AFTER queue lands at an index >= freezeTarget and is
        // never part of this proposal's frozen set (append-only guarantees stable [0, target)).
        _inflateActiveSet(3);
        assertGt(registry.activeVaultsLength(), targetAtQueue, "live set grew");

        dao.freezeVaults(pid, 100000); // finish the freeze
        (, uint256 target) = dao.snapshotProgress(pid);
        assertEq(target, targetAtQueue, "frozen target unchanged by post-queue additions");
    }
}
