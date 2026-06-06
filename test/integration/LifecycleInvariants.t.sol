// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ProposalEscrow, IProposalEscrow} from "../../src/governance/ProposalEscrow.sol";
import {GovernanceAuthRegistry} from "../../src/governance/GovernanceAuthRegistry.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";

/// @dev Minimal governance-action target used to prove a zero-funding (pure governance) proposal
///      can reach Collected and execute (C3).
contract Flag {
    uint256 public value;
    function setValue(uint256 v) external { value = v; }
}

/// @title Phase 0.0 lifecycle invariants — proves the four core-mechanic fixes (C1–C4).
/// @notice The pre-existing suites only exercised the happy path; these target the bugs the
///         security review found. Setup mirrors DAOLogicLifecycle.t.sol.
contract LifecycleInvariantsTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    ShwounsDAOLogic dao;
    GovernanceAuthRegistry authRegistry;

    address foundersDAO = makeAddr("foundersDAO");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address recipientA = makeAddr("recipientA");
    address recipientB = makeAddr("recipientB");

    uint256 aliceNoun;
    uint256 bobNoun;
    uint256 carolNoun;

    ShwounsVault aliceVault;
    ShwounsVault bobVault;
    ShwounsVault carolVault;

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        // Auth registry deployed first (this test contract is its binder); bound to the DAO below.
        authRegistry = new GovernanceAuthRegistry();

        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder, address(authRegistry));
        registry = new ShwounsVaultRegistry(address(token), address(authRegistry));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: 7200,
            votingDelay: 1,
            proposalThresholdBPS: 1,
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400
        });
        ShwounsDAOTypes.DynamicQuorumParams memory dq = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: 200, maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this), address(0), IShwounsTokenLike(address(token)), registry, params, dq
        );
        dao = ShwounsDAOLogic(payable(address(new ERC1967Proxy(address(daoImpl), initData))));
        registry.setDAOLogic(address(dao));
        authRegistry.bindDAOLogic(address(dao)); // governed contracts now accept the active escrow

        // Per-proposal escrow implementation (EIP-1167 clone source). daoLogic = the DAO proxy; the
        // residual sink is a placeholder (rescue isn't exercised by these suites).
        ProposalEscrow escrowImpl = new ProposalEscrow(address(dao), address(0xBEEF));
        dao.setProposalEscrowImplementation(address(escrowImpl));

        aliceNoun = _mintTo(alice);
        bobNoun = _mintTo(bob);
        carolNoun = _mintTo(carol);

        registry.createVaultFor(aliceNoun);
        registry.createVaultFor(bobNoun);
        registry.createVaultFor(carolNoun);
        aliceVault = ShwounsVault(payable(registry.vaultOf(aliceNoun)));
        bobVault = ShwounsVault(payable(registry.vaultOf(bobNoun)));
        carolVault = ShwounsVault(payable(registry.vaultOf(carolNoun)));

        vm.prank(alice); token.delegate(alice);
        vm.prank(bob); token.delegate(bob);
        vm.prank(carol); token.delegate(carol);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        vm.prank(alice); aliceVault.deposit{value: 3 ether}();
        vm.prank(bob); bobVault.deposit{value: 5 ether}();
        vm.prank(carol); carolVault.deposit{value: 2 ether}();

        vm.roll(block.number + 1);
    }

    function _mintTo(address recipient) internal returns (uint256) {
        uint256 nounId = token.mint();
        token.transferFrom(address(this), recipient, nounId);
        return nounId;
    }

    // ---- helpers -----------------------------------------------------------

    function _proposeETH(address proposer, address recipient, uint256 amount)
        internal
        returns (uint256 pid)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = recipient;
        values[0] = amount;
        vm.prank(proposer);
        pid = dao.propose(targets, values, sigs, calldatas, "send ETH");
    }

    /// @dev Vote the proposal through to Succeeded. Assumes it was just proposed.
    function _passToSucceeded(uint256 pid) internal {
        vm.roll(block.number + 2); // past votingDelay
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201); // past votingPeriod
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Succeeded), "Succeeded");
    }

    function _state(uint256 pid) internal view returns (ShwounsDAOTypes.ProposalState) {
        return dao.state(pid);
    }

    /// @dev Collected funds now live in the proposal's own escrow (per-proposal custody), not the
    ///      shared facade. Assertions about "how much the proposal holds" read the escrow balance.
    function _escrowBal(uint256 pid) internal view returns (uint256) {
        return dao.escrowAddressOf(pid).balance;
    }

    // =========================================================================
    // C1 — vault-set frozen at queue; iteration is robust to active-set mutation
    // =========================================================================

    /// A vault draining itself between queue() and recordSnapshot() removes itself from the
    /// registry's live active-set (swap-and-pop). Under the old index-into-live-set iteration
    /// this skipped/duplicated entries and could revert (brick). With the frozen set it must
    /// page cleanly over the queue-time membership.
    function test_c1_frozenSet_survivesActiveSetShrink_noBrick() public {
        uint256 pid = _proposeETH(alice, recipientA, 6 ether);
        _passToSucceeded(pid);
        dao.queue(pid);

        // Alice drains her vault AFTER queue → registry active-set shrinks 3 → 2 (swap-and-pop).
        vm.prank(alice);
        aliceVault.withdraw(alice, 3 ether);
        assertEq(registry.activeVaultsLength(), 2, "registry active-set shrank");

        // Must NOT revert and must complete the full frozen target (3), even though the live
        // set is now length 2 (old code: activeVaultAt(2) would revert).
        dao.recordSnapshot(pid, 10);
        (uint256 progress, uint256 target) = dao.snapshotProgress(pid);
        assertEq(progress, 3, "paged all 3 frozen vaults");
        assertEq(target, 3, "frozen target locked at queue");
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Snapshotted), "Snapshotted");

        // Alice's drained vault contributed nothing; only bob+carol are in the snapshotted set.
        (, uint256 collectTarget) = dao.collectProgress(pid);
        assertEq(collectTarget, 2, "two vaults held a balance at snapshot");
    }

    /// A vault that becomes active AFTER queue is not part of the frozen set and is never pulled.
    function test_c1_frozenSet_excludesVaultActivatedAfterQueue() public {
        uint256 pid = _proposeETH(alice, recipientA, 4 ether);
        _passToSucceeded(pid);
        dao.queue(pid); // freezes {alice, bob, carol}

        // A brand-new Shwoun funds its vault after queue.
        address dave = makeAddr("dave");
        uint256 daveNoun = _mintTo(dave);
        registry.createVaultFor(daveNoun);
        ShwounsVault daveVault = ShwounsVault(payable(registry.vaultOf(daveNoun)));
        vm.deal(dave, 200 ether);
        vm.prank(dave); daveVault.deposit{value: 100 ether}();

        dao.recordSnapshot(pid, 10);
        (uint256 progress, uint256 target) = dao.snapshotProgress(pid);
        assertEq(progress, 3, "only the 3 frozen vaults were paged");
        assertEq(target, 3, "dave excluded from frozen target");

        // Dave's vault is untouched by collect.
        dao.collect(pid, 10);
        assertEq(address(daveVault).balance, 100 ether, "post-queue vault never pulled");
    }

    // =========================================================================
    // C2 — collect pages strictly over the snapshotted list; no fake completion
    // =========================================================================

    /// Reaching Collected requires actually pulling from every snapshotted vault. Paging by
    /// internal index (no caller-supplied IDs) makes the old "feed junk IDs to force Collected
    /// and DoS real collection" griefing impossible by construction.
    function test_c2_collect_reachesCollectedOnlyAfterAllRealVaultsPulled() public {
        uint256 pid = _proposeETH(alice, recipientA, 6 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 10);

        (, uint256 collectTarget) = dao.collectProgress(pid);
        assertEq(collectTarget, 3, "three snapshotted vaults");

        // Collect only the first vault — must still be Snapshotted, not Collected.
        dao.collect(pid, 1);
        (uint256 progress, ) = dao.collectProgress(pid);
        assertEq(progress, 1);
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Snapshotted), "still Snapshotted");

        // Finishing the remaining real vaults flips to Collected and the proposal's escrow holds
        // the funds (per-proposal custody, not the shared facade).
        dao.collect(pid, 10);
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Collected), "Collected");
        assertEq(_escrowBal(pid), 6 ether, "escrow holds exactly the requested amount");
        assertEq(address(dao).balance, 0, "facade never custodies collected funds");
    }

    // =========================================================================
    // C3 — zero-funding (pure governance) proposals reach Collected and finalize
    // =========================================================================

    function test_c3_pureGovernanceProposal_finalizesWithoutFunds() public {
        Flag flag = new Flag();
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(flag);
        values[0] = 0; // no funding
        calldatas[0] = abi.encodeWithSelector(Flag.setValue.selector, 42);

        vm.prank(alice);
        uint256 pid = dao.propose(targets, values, sigs, calldatas, "pure governance");
        _passToSucceeded(pid);

        // No assets requested → snapshot phase is skipped → immediately Collected after queue.
        dao.queue(pid);
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Collected), "Collected w/o funds");

        dao.finalize(pid);
        assertEq(flag.value(), 42, "governance action executed");
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Executed), "Executed");
    }

    // =========================================================================
    // C4 — funds isolated per proposal; shortfall blocks finalize; top-up rescues
    // =========================================================================

    /// Two live proposals. A collects its full 6 ETH; B can only collect a partial amount.
    /// Even though the DAO contract holds MORE than enough ETH in aggregate (A's 6 + B's
    /// partial), B cannot finalize against another proposal's funds — its own ledger gates it.
    function test_c4_fundsIsolated_shortfallBlocks_topUpRescues() public {
        uint256 pidA = _proposeETH(alice, recipientA, 6 ether);
        uint256 pidB = _proposeETH(bob, recipientB, 6 ether);

        // Vote both proposals through together (same voting window).
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pidA, 1);
        vm.prank(bob); dao.castVote(pidA, 1);
        vm.prank(carol); dao.castVote(pidA, 1);
        vm.prank(alice); dao.castVote(pidB, 1);
        vm.prank(bob); dao.castVote(pidB, 1);
        vm.prank(carol); dao.castVote(pidB, 1);
        vm.roll(block.number + 7201);
        assertEq(uint256(_state(pidA)), uint256(ShwounsDAOTypes.ProposalState.Succeeded));
        assertEq(uint256(_state(pidB)), uint256(ShwounsDAOTypes.ProposalState.Succeeded));

        // A: full collection (vaults hold 10 ETH total, A requests 6).
        dao.queue(pidA);
        dao.recordSnapshot(pidA, 10);
        dao.collect(pidA, 10);
        assertEq(_escrowBal(pidA), 6 ether, "A's escrow holds 6");

        // B: vaults now hold 4 ETH (10 - 6 pulled by A's collect). B requests 6 → shortfall.
        dao.queue(pidB);
        dao.recordSnapshot(pidB, 10);
        dao.collect(pidB, 10);
        assertEq(_escrowBal(pidB), 4 ether, "B's escrow holds only 4 (shortfall)");
        assertEq(address(dao).balance, 0, "facade custodies nothing");

        // ISOLATION: B cannot finalize. Its own escrow holds only 4 — and A's 6 sit in a DIFFERENT
        // escrow B can't reach. Both the ledger gate and the escrow-balance solvency check block it.
        vm.expectRevert(ShwounsDAOProposals.InsufficientCollected.selector);
        dao.finalize(pidB);

        // A is unaffected and finalizes against its own 6.
        dao.finalize(pidA);
        assertEq(recipientA.balance, 6 ether, "A executed");
        assertEq(_escrowBal(pidA), 0, "A's escrow drained");
        assertEq(_escrowBal(pidB), 4 ether, "B's escrow untouched by A");

        // Top up B's 2 ETH shortfall, then B finalizes.
        dao.topUp{value: 2 ether}(pidB, address(0), 2 ether);
        dao.finalize(pidB);
        assertEq(recipientB.balance, 6 ether, "B executed after top-up");
        assertEq(_escrowBal(pidB), 0, "B's escrow drained");
    }

    /// refundStuckProposal returns ONLY what was actually collected (pro-rata by snapshot share),
    /// never the snapshot-derived requested amount (which would exceed the DAO's holdings).
    function test_c4_refundStuckProposal_returnsOnlyCollected() public {
        uint256 pid = _proposeETH(alice, recipientA, 6 ether);
        _passToSucceeded(pid);
        dao.queue(pid);
        dao.recordSnapshot(pid, 10); // snapshots all three: total 10 ETH

        // Alice drains after snapshot → her share can't be collected (genuine shortfall).
        vm.prank(alice);
        aliceVault.withdraw(alice, 3 ether);

        dao.collect(pid, 10);
        // Collected = bob 3 + carol 1.2 = 4.2 (alice 0). NOT the requested 6.
        uint256 collected = _escrowBal(pid);
        assertEq(collected, 4.2 ether, "escrow holds only bob+carol shares");

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 carolBefore = carol.balance;

        address[] memory assets = new address[](1);
        assets[0] = address(0);
        dao.refundStuckProposal(pid, assets);

        // The escrow can only refund what it holds: total refunded == collected (4.2), distributed
        // pro-rata by snapshot share (alice 3/10, bob 5/10, carol 2/10 of 4.2).
        assertEq(_escrowBal(pid), 0, "escrow emptied, never over-refunded");
        assertEq(alice.balance - aliceBefore, 4.2 ether * 3 / 10, "alice owner share of collected");
        assertEq(bob.balance - bobBefore, 4.2 ether * 5 / 10, "bob owner share of collected");
        assertEq(carol.balance - carolBefore, 4.2 ether * 2 / 10, "carol owner share of collected");
    }
}
