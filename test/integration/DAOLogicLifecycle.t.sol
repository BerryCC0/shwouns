// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ProposalEscrow} from "../../src/governance/ProposalEscrow.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";

contract DAOLogicLifecycleTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    ShwounsDAOLogic dao;

    address foundersDAO = makeAddr("foundersDAO");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address proposalRecipient = makeAddr("propTarget");

    uint256 aliceNoun;
    uint256 bobNoun;
    uint256 carolNoun;

    ShwounsVault aliceVault;
    ShwounsVault bobVault;
    ShwounsVault carolVault;

    function setUp() public {
        // Etch canonical ERC-6551 registry
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        // Deploy tokens + registry + vault impl
        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        // Use this contract as minter so we can mint directly in tests
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder);
        registry = new ShwounsVaultRegistry(address(token));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        // Deploy DAOLogic via UUPS proxy
        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: 7200, // blocks (min allowed)
            votingDelay: 1,
            proposalThresholdBPS: 1, // min allowed; threshold = 0 at this small supply
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400
        });
        ShwounsDAOTypes.DynamicQuorumParams memory dq = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: 200, maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this),         // admin
            address(0),            // vetoer (none)
            IShwounsTokenLike(address(token)),
            registry,
            params,
            dq                     // dynamic-quorum seed
        );
        ERC1967Proxy daoProxy = new ERC1967Proxy(address(daoImpl), initData);
        dao = ShwounsDAOLogic(payable(address(daoProxy)));

        // Wire DAOLogic into registry (so vault.pullProRata is gated correctly)
        registry.setDAOLogic(address(dao));

        // Per-proposal escrow implementation (clone source). Collected funds live in the proposal's
        // escrow, not the facade.
        ProposalEscrow escrowImpl = new ProposalEscrow(address(dao), address(0xBEEF));
        dao.setProposalEscrowImplementation(address(escrowImpl));

        // Mint 3 auction Shwouns directly (this contract is the minter).
        // Each mint() may also produce a founder Shwoun at multiples of 10.
        // After 3 mint() calls starting from 0: founder 0, auction 1, auction 2, auction 3.
        aliceNoun = _mintTo(alice);  // mints founder 0 + auction 1; transfers auction 1 to alice
        bobNoun = _mintTo(bob);      // mints auction 2; transfers to bob
        carolNoun = _mintTo(carol);  // mints auction 3; transfers to carol

        // Deploy vaults for these Shwouns
        registry.createVaultFor(aliceNoun);
        registry.createVaultFor(bobNoun);
        registry.createVaultFor(carolNoun);

        aliceVault = ShwounsVault(payable(registry.vaultOf(aliceNoun)));
        bobVault = ShwounsVault(payable(registry.vaultOf(bobNoun)));
        carolVault = ShwounsVault(payable(registry.vaultOf(carolNoun)));

        // Each voter self-delegates so getPriorVotes returns 1 for them
        vm.prank(alice); token.delegate(alice);
        vm.prank(bob); token.delegate(bob);
        vm.prank(carol); token.delegate(carol);

        // Voters fund their vaults
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        vm.prank(alice); aliceVault.deposit{value: 3 ether}();
        vm.prank(bob); bobVault.deposit{value: 5 ether}();
        vm.prank(carol); carolVault.deposit{value: 2 ether}();

        // Move forward one block so checkpoint storage is settled
        vm.roll(block.number + 1);
    }

    function _mintTo(address recipient) internal returns (uint256) {
        uint256 nounId = token.mint();
        token.transferFrom(address(this), recipient, nounId);
        return nounId;
    }

    // -------------------------------------------------------------------------
    // The full lifecycle test
    // -------------------------------------------------------------------------

    function test_fullLifecycle_singleAssetProposal() public {
        // 1. Propose: send 6 ETH from collected vault funds to proposalRecipient
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = proposalRecipient;
        values[0] = 6 ether;
        sigs[0] = "";
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = dao.propose(targets, values, sigs, calldatas, "test proposal: send 6 ETH");

        // 2. On the creation block the proposal is Updatable (the pre-voting edit window is
        //    [creationBlock, creationBlock + proposalUpdatablePeriodInBlocks]; with the period
        //    set to 0 that window is just the creation block itself). It becomes Pending on the
        //    next block and Active once votingDelay elapses.
        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Updatable),
            "Updatable on creation block"
        );

        vm.roll(block.number + 2); // past updatable window + votingDelay

        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Active),
            "Active"
        );

        // 3. All three vote For
        vm.prank(alice); dao.castVote(proposalId, 1);
        vm.prank(bob); dao.castVote(proposalId, 1);
        vm.prank(carol); dao.castVote(proposalId, 1);

        // 4. Past voting period
        vm.roll(block.number + 7201);

        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Succeeded),
            "Succeeded"
        );

        // 5. Queue — locks snapshot target + extracts assets
        dao.queue(proposalId);
        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Queued),
            "Queued"
        );

        (uint256 progress, uint256 target) = dao.snapshotProgress(proposalId);
        assertEq(progress, 0);
        assertEq(target, 3, "3 active vaults expected");

        address[] memory assets = dao.assetsForProposal(proposalId);
        assertEq(assets.length, 1);
        assertEq(assets[0], address(0), "ETH is the only asset");

        // 6. Snapshot all 3 vaults
        dao.recordSnapshot(proposalId, 10);
        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Snapshotted),
            "Snapshotted"
        );
        (progress, target) = dao.snapshotProgress(proposalId);
        assertEq(progress, 3);

        // 7. Collect — pulls pro-rata shares to DAOLogic
        uint256[] memory vaultIds = new uint256[](3);
        vaultIds[0] = aliceNoun;
        vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun;

        address escrow = dao.escrowAddressOf(proposalId);
        uint256 escrowBefore = escrow.balance;
        dao.collect(proposalId, vaultIds.length);

        // Total drawn into the proposal's escrow should be 6 ETH (the requested amount)
        uint256 drawn = escrow.balance - escrowBefore;
        assertEq(drawn, 6 ether, "escrow collected 6 ETH");
        assertEq(address(dao).balance, 0, "facade never custodies collected funds");

        // Pro-rata: alice 1.8, bob 3.0, carol 1.2 (total 6 from 10)
        assertEq(address(aliceVault).balance, 3 ether - 1.8 ether);
        assertEq(address(bobVault).balance, 5 ether - 3 ether);
        assertEq(address(carolVault).balance, 2 ether - 1.2 ether);

        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Collected),
            "Collected"
        );

        // 8. Finalize — DAOLogic forwards 6 ETH to proposalRecipient
        assertEq(proposalRecipient.balance, 0);
        dao.finalize(proposalId);

        assertEq(proposalRecipient.balance, 6 ether, "recipient received 6 ETH");
        assertEq(escrow.balance, 0, "escrow drained after finalize");
        assertEq(address(dao).balance, 0, "facade balance still 0");

        assertEq(
            uint256(dao.state(proposalId)),
            uint256(ShwounsDAOTypes.ProposalState.Executed),
            "Executed"
        );
    }

    // -------------------------------------------------------------------------
    // Shortfall: alice withdraws between snapshot and collect
    // -------------------------------------------------------------------------

    function test_shortfall_aliceDrainsBeforeCollect() public {
        // Standard proposal: 6 ETH to recipient
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = proposalRecipient;
        values[0] = 6 ether;

        vm.prank(alice);
        uint256 proposalId = dao.propose(targets, values, sigs, calldatas, "test");

        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(proposalId, 1);
        vm.prank(bob); dao.castVote(proposalId, 1);
        vm.roll(block.number + 7201);

        dao.queue(proposalId);
        dao.recordSnapshot(proposalId, 10);

        // Alice withdraws her 3 ETH after snapshot but before collect
        vm.prank(alice);
        aliceVault.withdraw(alice, 3 ether);
        assertEq(address(aliceVault).balance, 0);

        // Collect
        uint256[] memory vaultIds = new uint256[](3);
        vaultIds[0] = aliceNoun;
        vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun;
        dao.collect(proposalId, vaultIds.length);

        // Alice's vault contributed 0 (drained). Bob + Carol contributed their full pro-rata share.
        // Bob's share: 6 * 5/10 = 3 ETH
        // Carol's share: 6 * 2/10 = 1.2 ETH
        // Total collected: 4.2 ETH (shortfall of 1.8 ETH)
        assertEq(dao.escrowAddressOf(proposalId).balance, 4.2 ether, "escrow has bob+carol shares only");
    }
}
