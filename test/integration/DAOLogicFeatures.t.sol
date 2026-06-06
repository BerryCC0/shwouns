// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {ProposalEscrow} from "../../src/governance/ProposalEscrow.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Shared setup helper for the DAO test suite — full stack deployment, 3 voters, vaults funded.
contract DAOTestBase is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    ShwounsDAOLogic dao;

    address foundersDAO = makeAddr("foundersDAO");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    uint256 aliceNoun;
    uint256 bobNoun;
    uint256 carolNoun;

    ShwounsVault aliceVault;
    ShwounsVault bobVault;
    ShwounsVault carolVault;

    function _deploy(uint256 votingDelay_, uint256 votingPeriod_) internal {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder, address(0));
        registry = new ShwounsVaultRegistry(address(token), address(0));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: votingPeriod_,
            votingDelay: votingDelay_,
            proposalThresholdBPS: 1, // min allowed; threshold = 0 at this small supply
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400
        });
        // Dynamic quorum is seeded at init; the old fixed-quorum BPS arg is gone.
        ShwounsDAOTypes.DynamicQuorumParams memory dq = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: 200, maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this),
            address(this), // vetoer = this contract so tests can veto/transfer
            IShwounsTokenLike(address(token)),
            registry,
            params,
            dq
        );
        ERC1967Proxy daoProxy = new ERC1967Proxy(address(daoImpl), initData);
        dao = ShwounsDAOLogic(payable(address(daoProxy)));

        registry.setDAOLogic(address(dao));

        // Per-proposal escrow implementation (clone source). Collected funds live in each
        // proposal's escrow, not the facade.
        ProposalEscrow escrowImpl = new ProposalEscrow(address(dao), address(0xBEEF));
        dao.setProposalEscrowImplementation(address(escrowImpl));

        // Mint and distribute
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

    function _simpleETHProposal(uint256 amount, address recipient)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, string[] memory sigs, bytes[] memory cd)
    {
        targets = new address[](1);
        values = new uint256[](1);
        sigs = new string[](1);
        cd = new bytes[](1);
        targets[0] = recipient;
        values[0] = amount;
    }
}

// =============================================================================
// Admin tests
// =============================================================================

contract DAOAdminTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200);
    }

    function test_setVotingDelay_byAdmin() public {
        dao.setVotingDelay(7);
        assertEq(dao.votingDelay(), 7);
    }

    function test_setVotingDelay_byNonAdmin_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ShwounsDAOLogic.OnlyAdmin.selector);
        dao.setVotingDelay(7);
    }

    function test_setVotingPeriod_byAdmin() public {
        // setVotingPeriod enforces [MIN_VOTING_PERIOD_BLOCKS, MAX_VOTING_PERIOD_BLOCKS] = [7200, 100800].
        dao.setVotingPeriod(8000);
        assertEq(dao.votingPeriod(), 8000);
    }

    function test_setQuorumVotesBPS_byAdmin() public {
        dao.setQuorumVotesBPS(3000);
        assertEq(dao.quorumVotesBPS(), 3000);
    }

    function test_acceptAdmin_flow() public {
        address newAdmin = makeAddr("newAdmin");
        dao.setPendingAdmin(newAdmin);
        // Random caller cannot accept
        vm.prank(alice);
        vm.expectRevert(ShwounsDAOLogic.OnlyAdmin.selector);
        dao.acceptAdmin();
        // Pending admin can accept
        vm.prank(newAdmin);
        dao.acceptAdmin();
        assertEq(dao.admin(), newAdmin);
    }

    function test_vetoer_transfer() public {
        address newVetoer = makeAddr("newVetoer");
        dao.setPendingVetoer(newVetoer);
        vm.prank(newVetoer);
        dao.acceptVetoer();
        assertEq(dao.vetoer(), newVetoer);
    }

    function test_burnVetoPower_byVetoer() public {
        dao.burnVetoPower();
        assertEq(dao.vetoer(), address(0));
    }

    function test_setLastMinuteWindow_byAdmin() public {
        dao.setLastMinuteWindowInBlocks(3);
        assertEq(dao.lastMinuteWindowInBlocks(), 3);
    }
}

// =============================================================================
// Dynamic quorum tests
// =============================================================================

contract DAODynamicQuorumTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200); // dynamic quorum seeded at init (min 200 bps)
        dao.setDynamicQuorumParams({
            newMinQuorumVotesBPS: 1000,   // 10%
            newMaxQuorumVotesBPS: 4000,   // 40%
            newQuorumCoefficient: 1_000_000 // 1.0
        });
        vm.roll(block.number + 1); // checkpoint is at last block
    }

    function test_dynamicQuorum_isAtMinimum_whenNoAgainstVotes() public {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _simpleETHProposal(1 ether, makeAddr("recip"));
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "test");
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);

        // 3 Shwouns total, minBPS=1000 → ceil(3*1000/10000) = 0 (integer div)
        // forVotes = 1, quorumVotes = 0, so passes
        assertEq(
            uint256(dao.state(pid)),
            uint256(ShwounsDAOTypes.ProposalState.Succeeded)
        );
    }

    function test_dynamicQuorum_raises_withAgainstVotes() public {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _simpleETHProposal(1 ether, makeAddr("recip"));
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "test");
        vm.roll(block.number + 2);

        // bob votes against (1 vote against), alice votes for (1 vote for)
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 0);
        vm.roll(block.number + 7201);

        // Quorum math:
        //   totalSupply = 3
        //   againstVotes = 1, totalSupply = 3
        //   againstBPS = 10000 * 1 / 3 = 3333
        //   adjustmentBPS = 1_000_000 * 3333 / 1e6 = 3333
        //   adjusted = minBPS(1000) + 3333 = 4333, capped at maxBPS(4000) = 4000
        //   quorumVotes = 3 * 4000 / 10000 = 1
        // forVotes = 1, quorumVotes = 1; forVotes < quorumVotes? 1 < 1 = false → passes
        // Also forVotes > againstVotes? 1 > 1 = false → DEFEATED
        assertEq(
            uint256(dao.state(pid)),
            uint256(ShwounsDAOTypes.ProposalState.Defeated)
        );
    }
}

// =============================================================================
// Dynamic quorum safety: retroactive-zero regression + setter bounds (0.3)
// =============================================================================

contract DAOQuorumSafetyTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200); // dynamic quorum seeded at init (checkpoint 0 always created)
    }

    /// initialize seeds the first dynamic-quorum checkpoint (checkpoint 0) at deploy, so dynamic
    /// quorum is live from block 0. (The old "proposal created before the first checkpoint"
    /// scenario is now unreachable — there is always a checkpoint.)
    function test_initSeedsDynamicQuorumCheckpoint() public {
        assertEq(dao.getDynamicQuorumParamsCheckpointCount(), 1, "init seeds one checkpoint");
    }

    function test_setDynamicQuorumParams_revertsMinBelowLowerBound() public {
        vm.expectRevert(ShwounsDAOLogic.InvalidMinQuorumVotesBPS.selector);
        dao.setDynamicQuorumParams(199, 4000, 0);
    }

    function test_setDynamicQuorumParams_revertsMinAboveUpperBound() public {
        vm.expectRevert(ShwounsDAOLogic.InvalidMinQuorumVotesBPS.selector);
        dao.setDynamicQuorumParams(2001, 4000, 0);
    }

    function test_setDynamicQuorumParams_revertsMaxAboveUpperBound() public {
        vm.expectRevert(ShwounsDAOLogic.InvalidMaxQuorumVotesBPS.selector);
        dao.setDynamicQuorumParams(1000, 6001, 0);
    }

    function test_setDynamicQuorumParams_revertsMinGreaterThanMax() public {
        vm.expectRevert(ShwounsDAOLogic.MinQuorumBPSGreaterThanMaxQuorumBPS.selector);
        dao.setDynamicQuorumParams(2000, 1000, 0);
    }

    function test_setDynamicQuorumParams_acceptsValidBounds() public {
        // init already seeded checkpoint 0; this setter adds checkpoint 1 → count == 2.
        dao.setDynamicQuorumParams(200, 6000, 1_000_000);
        assertEq(dao.getDynamicQuorumParamsCheckpointCount(), 2);
    }
}

// =============================================================================
// Stuck-fund recovery test
// =============================================================================

contract DAORefundStuckTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200);
    }

    function test_refundStuckProposal_returnsFundsToCurrentOwners() public {
        // Create a proposal targeting a contract that will revert in finalize
        RevertingTarget bad = new RevertingTarget();
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = address(bad);
        values[0] = 5 ether;
        cd[0] = abi.encodeWithSignature("doRevert()");

        vm.prank(alice);
        uint256 pid = dao.propose(targets, values, sigs, cd, "will revert");

        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);

        dao.queue(pid);
        dao.recordSnapshot(pid, 10);

        uint256[] memory vaultIds = new uint256[](3);
        vaultIds[0] = aliceNoun;
        vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun;
        dao.collect(pid, vaultIds.length);

        // Finalize reverts
        vm.expectRevert();
        dao.finalize(pid);

        assertEq(dao.escrowAddressOf(pid).balance, 5 ether, "escrow holds the collected 5 ETH");

        // Refund — by actual contribution, returns ETH to current owners (paged batch)
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 carolBefore = carol.balance;

        dao.refundStuckProposal(pid, 100);

        // All three contributed their full share (no drain), so actual == snapshot share:
        // alice 5*3/10=1.5, bob 5*5/10=2.5, carol 5*2/10=1.0
        assertEq(alice.balance - aliceBefore, 1.5 ether);
        assertEq(bob.balance - bobBefore, 2.5 ether);
        assertEq(carol.balance - carolBefore, 1.0 ether);
        assertEq(dao.escrowAddressOf(pid).balance, 0, "escrow drained after refund");
    }
}

contract RevertingTarget {
    function doRevert() external payable {
        revert("nope");
    }

    receive() external payable {}
}

// =============================================================================
// Objection period test
// =============================================================================

contract DAOObjectionPeriodTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200);
        // votingPeriod is now 7200, so endBlock = startBlock + 7200. Use a 10-block last-minute
        // window and a 50-block objection extension; the rolls below land the flipping For-vote
        // inside the final 10 blocks of voting, then advance just past endBlock into the objection.
        dao.setLastMinuteWindowInBlocks(10);
        dao.setObjectionPeriodDurationInBlocks(50);
    }

    function test_forVoteInLastMinute_triggersObjectionPeriod() public {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _simpleETHProposal(1 ether, makeAddr("recip"));
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "lastminute");
        vm.roll(block.number + 2); // past delay → Active

        // Early votes: bob against, carol for → 1-1 tie, proposal currently failing
        vm.prank(bob); dao.castVote(pid, 0);
        vm.prank(carol); dao.castVote(pid, 1);

        // Jump to last-minute window (within 10 blocks of endBlock). After propose at block C,
        // startBlock = C+1, endBlock = C+7201. We're at C+2 here; +7198 lands at C+7200.
        vm.roll(block.number + 7198);

        // Alice votes For — this is the FLIP from failing (1-1 tie) to succeeding (2-1)
        vm.prank(alice); dao.castVote(pid, 1);

        // Should have triggered objection period; after endBlock we should see ObjectionPeriod state.
        // Now at C+7200; +5 → C+7205, which is past endBlock (C+7201) and inside the objection
        // window (ends C+7201+50 = C+7251).
        vm.roll(block.number + 5);
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.ObjectionPeriod));
    }

    function test_duringObjection_onlyAgainstVotesAllowed() public {
        // Add a fourth voter (dave) who hasn't voted yet — used to test the
        // OnlyAgainstVotesDuringObjection restriction once objection period is active.
        address dave = makeAddr("dave");
        uint256 daveNoun = _mintTo(dave);
        registry.createVaultFor(daveNoun);
        vm.prank(dave); token.delegate(dave);
        vm.roll(block.number + 1); // checkpoint settles

        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _simpleETHProposal(1 ether, makeAddr("recip"));
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "obj");
        vm.roll(block.number + 2);

        // Pattern: bob against, alice for (1-1 tie failing), then last-minute carol for triggers.
        // After propose at block C, startBlock = C+1, endBlock = C+7201; we're at C+2 here.
        vm.prank(bob); dao.castVote(pid, 0);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.roll(block.number + 7198); // → C+7200, inside the 10-block last-minute window
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 5); // → C+7205, now in objection period (ends C+7251)

        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.ObjectionPeriod));

        // Dave (fresh voter) tries to vote For during objection — should revert
        vm.prank(dave);
        vm.expectRevert(ShwounsDAOProposals.OnlyAgainstVotesDuringObjection.selector);
        dao.castVote(pid, 1);

        // Dave can still vote Against
        vm.prank(dave); dao.castVote(pid, 0);
    }
}

// =============================================================================
// Multi-asset proposal test (ERC-20 transfer detected in calldata)
// =============================================================================

contract DAOMultiAssetTest is DAOTestBase {
    MockERC20 usdc;

    function setUp() public {
        _deploy(1, 7200);
        usdc = new MockERC20();
        dao.setFundableAsset(address(usdc), true); // M-04 allowlist: USDC is a fundable asset

        // Fund vaults with USDC
        usdc.mint(address(aliceVault), 100e18);
        usdc.mint(address(bobVault), 200e18);
        usdc.mint(address(carolVault), 50e18);

        // Have someone deposit to mark vaults active for USDC (active set is based on ETH currently;
        // they're already marked active from setUp's ETH deposits).
    }

    function test_proposalWithERC20Transfer_detectsAsset() public {
        address recipient = makeAddr("usdcRecip");
        // Proposal: send 175 USDC from DAO to recipient
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = address(usdc);
        values[0] = 0;
        cd[0] = abi.encodeWithSignature("transfer(address,uint256)", recipient, 175e18);

        vm.prank(alice);
        uint256 pid = dao.propose(targets, values, sigs, cd, "usdc test");
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);

        dao.queue(pid);

        // Asset should be detected as USDC
        address[] memory assets = dao.assetsForProposal(pid);
        assertEq(assets.length, 1, "only USDC, no ETH (value=0)");
        assertEq(assets[0], address(usdc));

        dao.recordSnapshot(pid, 10);

        uint256[] memory vaultIds = new uint256[](3);
        vaultIds[0] = aliceNoun;
        vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun;
        dao.collect(pid, vaultIds.length);

        // Pro-rata: total = 350, requested = 175, so half pulled from each
        // alice contributes 175 * 100/350 = 50
        // bob contributes 175 * 200/350 = 100
        // carol contributes 175 * 50/350 = 25
        // Total = 175 in the proposal's escrow (per-proposal custody)
        assertEq(usdc.balanceOf(dao.escrowAddressOf(pid)), 175e18);
        assertEq(usdc.balanceOf(address(dao)), 0, "facade custodies no ERC-20");

        dao.finalize(pid);
        assertEq(usdc.balanceOf(recipient), 175e18);
    }

    /// 0.2: the GovernorBravo signature-string encoding (function in `signature`, args-only
    /// `calldata` with NO selector) must be detected by snapshot/collect AND executed by finalize,
    /// identically to the selector-in-calldata form. Without the fix the asset goes undetected
    /// (unfunded) and the raw call is malformed.
    function test_proposalWithERC20Transfer_signatureForm_detectsAndExecutes() public {
        address recipient = makeAddr("usdcRecip2");
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = address(usdc);
        values[0] = 0;
        sigs[0] = "transfer(address,uint256)"; // function as signature
        cd[0] = abi.encode(recipient, 175e18);  // args only — NO selector prefix

        vm.prank(alice);
        uint256 pid = dao.propose(targets, values, sigs, cd, "usdc sig-form");
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);

        dao.queue(pid);

        address[] memory assets = dao.assetsForProposal(pid);
        assertEq(assets.length, 1, "USDC detected via signature form");
        assertEq(assets[0], address(usdc));

        dao.recordSnapshot(pid, 10);
        dao.collect(pid, 10);
        assertEq(usdc.balanceOf(dao.escrowAddressOf(pid)), 175e18, "collected 175 USDC into escrow");

        dao.finalize(pid);
        assertEq(usdc.balanceOf(recipient), 175e18, "signature-form transfer executed");
    }
}

// =============================================================================
// Signed proposals (proposeBySigs) test
// =============================================================================

contract DAOSignedProposalsTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    ShwounsDAOLogic dao;

    address foundersDAO = makeAddr("foundersDAO");

    address sigAlice;
    uint256 sigAlicePk;
    address sigBob;
    uint256 sigBobPk;
    address sigCarol;
    uint256 sigCarolPk;

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder, address(0));
        registry = new ShwounsVaultRegistry(address(token), address(0));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: 7200,
            votingDelay: 1,
            // proposalThresholdBPS is now bounded to [1, 1000]. With total supply == 10,
            // threshold = bps2Uint(1000, 10) = 1. Nouns semantics require votes STRICTLY
            // greater than the threshold, so 2 signers together (2 > 1) clear it; 1 signer
            // alone (1 <= 1) does not. Filler Shwouns (below) bring supply to exactly 10.
            proposalThresholdBPS: 1000,
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400
        });
        ShwounsDAOTypes.DynamicQuorumParams memory dq = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: 200, maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this),
            address(0),
            IShwounsTokenLike(address(token)),
            registry,
            params,
            dq
        );
        ERC1967Proxy daoProxy = new ERC1967Proxy(address(daoImpl), initData);
        dao = ShwounsDAOLogic(payable(address(daoProxy)));
        registry.setDAOLogic(address(dao));

        // Signers with known private keys
        (sigAlice, sigAlicePk) = makeAddrAndKey("sigAlice");
        (sigBob, sigBobPk) = makeAddrAndKey("sigBob");
        (sigCarol, sigCarolPk) = makeAddrAndKey("sigCarol");

        // Mint 1 Shwoun each (after founder Shwoun 0 → auction 1, 2, 3)
        uint256 id1 = token.mint(); token.transferFrom(address(this), sigAlice, id1);
        uint256 id2 = token.mint(); token.transferFrom(address(this), sigBob, id2);
        uint256 id3 = token.mint(); token.transferFrom(address(this), sigCarol, id3);
        vm.prank(sigAlice); token.delegate(sigAlice);
        vm.prank(sigBob); token.delegate(sigBob);
        vm.prank(sigCarol); token.delegate(sigCarol);

        // Bring total supply to exactly 10 so the threshold = bps2Uint(1000, 10) = 1.
        // After the 3 signer mints, supply is 4 (tokens 0..3); 6 more mints reach 10
        // (tokens 4..9, no founder reward until id 10). The filler does NOT sign and is
        // NOT delegated — these Shwouns only inflate totalSupply for the threshold math.
        address filler = makeAddr("filler");
        for (uint256 i = 0; i < 6; i++) {
            uint256 fid = token.mint();
            token.transferFrom(address(this), filler, fid);
        }
        vm.roll(block.number + 1);
    }

    function _signProposal(
        uint256 pk,
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        uint256 expirationTimestamp
    ) internal view returns (bytes memory) {
        bytes32 digest =
            dao.proposalDigest(proposer, targets, values, signatures, calldatas, description, expirationTimestamp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_proposeBySigs_twoSigners_meetsThreshold() public {
        address recipient = makeAddr("recip");
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = recipient;
        values[0] = 1 ether;

        // Both sigAlice and sigBob sign the proposal; proposer = this contract (= msg.sender).
        uint256 expiry = block.timestamp + 1 days;
        bytes memory aliceSig =
            _signProposal(sigAlicePk, address(this), targets, values, sigs, cd, "signed proposal", expiry);
        bytes memory bobSig =
            _signProposal(sigBobPk, address(this), targets, values, sigs, cd, "signed proposal", expiry);

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](2);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: expiry
        });
        proposerSigs[1] = ShwounsDAOTypes.ProposerSignature({
            sig: bobSig, signer: sigBob, expirationTimestamp: expiry
        });

        uint256 pid = dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "signed proposal");
        assertGt(pid, 0);

        // Proposal should record both signers
        address[] memory signers = dao.proposalSigners(pid);
        assertEq(signers.length, 2);
        assertEq(signers[0], sigAlice);
        assertEq(signers[1], sigBob);
    }

    function test_proposeBySigs_singleSigner_belowThreshold_reverts() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        values[0] = 1 ether;

        uint256 expiry = block.timestamp + 1 days;
        bytes memory aliceSig =
            _signProposal(sigAlicePk, address(this), targets, values, sigs, cd, "lone signer", expiry);
        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](1);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: expiry
        });

        // totalSupply = 10 (founder 0 + auction 1-3 + 6 filler). threshold = bps2Uint(1000, 10) = 1.
        // Single signer has 1 vote; 1 <= 1 (Nouns semantics) → must revert.
        vm.expectRevert(ShwounsDAOProposals.SignersBelowThreshold.selector);
        dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "lone signer");
    }

    function test_cancelSig_invalidatesSignature() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        values[0] = 1 ether;

        uint256 expiry = block.timestamp + 1 days;
        bytes memory aliceSig =
            _signProposal(sigAlicePk, address(this), targets, values, sigs, cd, "cancel test", expiry);
        bytes memory bobSig =
            _signProposal(sigBobPk, address(this), targets, values, sigs, cd, "cancel test", expiry);

        // Alice cancels her sig before submission
        vm.prank(sigAlice);
        dao.cancelSig(aliceSig);

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](2);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: expiry
        });
        proposerSigs[1] = ShwounsDAOTypes.ProposerSignature({
            sig: bobSig, signer: sigBob, expirationTimestamp: expiry
        });

        vm.expectRevert(ShwounsDAOProposals.SigCancelled.selector);
        dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "cancel test");
    }

    function test_expiredSig_reverts() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        values[0] = 1 ether;

        // Sign over an already-expired timestamp that MATCHES the struct, so the signature is
        // valid and the expiry check (not the signature check) is what reverts.
        uint256 expiry = block.timestamp - 1;
        bytes memory aliceSig =
            _signProposal(sigAlicePk, address(this), targets, values, sigs, cd, "expired", expiry);

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](1);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: expiry
        });

        vm.expectRevert(ShwounsDAOProposals.SigExpired.selector);
        dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "expired");
    }

    /// 0.1: a relayer cannot extend a signature's expiry. Signing over one expiry and submitting
    /// a later one changes the digest, so the signature no longer verifies (it is NOT just an
    /// expiry-check failure — the binding makes the swapped signature invalid).
    function test_expirySwap_isRejected() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        values[0] = 1 ether;

        uint256 signedExpiry = block.timestamp + 1 hours;
        bytes memory aliceSig =
            _signProposal(sigAlicePk, address(this), targets, values, sigs, cd, "swap", signedExpiry);
        bytes memory bobSig =
            _signProposal(sigBobPk, address(this), targets, values, sigs, cd, "swap", signedExpiry);

        // Attacker submits with a LATER expiry than was signed.
        uint256 swappedExpiry = block.timestamp + 100 days;
        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](2);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({ sig: aliceSig, signer: sigAlice, expirationTimestamp: swappedExpiry });
        proposerSigs[1] = ShwounsDAOTypes.ProposerSignature({ sig: bobSig, signer: sigBob, expirationTimestamp: swappedExpiry });

        vm.expectRevert(ShwounsDAOProposals.SigInvalid.selector);
        dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "swap");
    }

    /// 0.5: any co-signer (not just the proposer) can cancel the proposal.
    function test_anySigner_canCancel() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        values[0] = 1 ether;

        uint256 expiry = block.timestamp + 1 days;
        bytes memory aliceSig = _signProposal(sigAlicePk, address(this), targets, values, sigs, cd, "cosign", expiry);
        bytes memory bobSig = _signProposal(sigBobPk, address(this), targets, values, sigs, cd, "cosign", expiry);

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](2);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({ sig: aliceSig, signer: sigAlice, expirationTimestamp: expiry });
        proposerSigs[1] = ShwounsDAOTypes.ProposerSignature({ sig: bobSig, signer: sigBob, expirationTimestamp: expiry });

        uint256 pid = dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "cosign");

        // sigBob is a signer but NOT the proposer (proposer = this test contract).
        vm.prank(sigBob);
        dao.cancel(pid);
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Canceled), "any signer can cancel");
    }

    /// 0.1: an ERC-1271 smart-contract wallet can co-sign (verified via SignatureChecker).
    function test_erc1271_contractWalletCanCoSign() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet(sigCarol); // validates sigCarol's key
        uint256 w1 = token.mint(); token.transferFrom(address(this), address(wallet), w1);
        uint256 w2 = token.mint(); token.transferFrom(address(this), address(wallet), w2);
        vm.prank(address(wallet)); token.delegate(address(wallet));
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        values[0] = 1 ether;

        uint256 expiry = block.timestamp + 1 days;
        bytes memory walletSig =
            _signProposal(sigCarolPk, address(this), targets, values, sigs, cd, "erc1271", expiry);

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](1);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({ sig: walletSig, signer: address(wallet), expirationTimestamp: expiry });

        uint256 pid = dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "erc1271");
        assertGt(pid, 0, "contract wallet co-signed");
        assertEq(dao.proposalSigners(pid)[0], address(wallet), "wallet recorded as signer");
    }
}

/// @dev Minimal ERC-1271 wallet: validates a signature if its owner's key produced it.
contract MockERC1271Wallet {
    address public owner;
    constructor(address _owner) { owner = _owner; }
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        return ECDSA.recover(hash, signature) == owner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

// =============================================================================
// recordSnapshot paging test
// =============================================================================

contract DAOSnapshotPagingTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200);
    }

    function test_recordSnapshot_inMultipleBatches() public {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _simpleETHProposal(3 ether, makeAddr("recip"));
        vm.prank(alice);
        uint256 pid = dao.propose(t, v, s, c, "paging");
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);
        dao.queue(pid);

        // Snapshot batchSize=1: should take 3 calls to complete
        dao.recordSnapshot(pid, 1);
        (uint256 progress, uint256 target) = dao.snapshotProgress(pid);
        assertEq(progress, 1);
        assertEq(target, 3);
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Queued));

        dao.recordSnapshot(pid, 1);
        (progress, ) = dao.snapshotProgress(pid);
        assertEq(progress, 2);
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Queued));

        dao.recordSnapshot(pid, 1);
        (progress, ) = dao.snapshotProgress(pid);
        assertEq(progress, 3);
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Snapshotted));
    }
}

// =============================================================================
// §C lifecycle recovery (H-01, M-03) — cancel/veto of funded proposals refund contributors
// =============================================================================

contract DAORecoveryTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 7200); // vetoer = this test contract (see DAOTestBase._deploy)
    }

    function _passAndCollect(uint256 amount) internal returns (uint256 pid) {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _simpleETHProposal(amount, makeAddr("r"));
        vm.prank(alice);
        pid = dao.propose(t, v, s, c, "recover");
        vm.roll(block.number + 2);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.prank(bob); dao.castVote(pid, 1);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 7201);
        dao.queue(pid);
        dao.recordSnapshot(pid, 10);
        dao.collect(pid, 10);
    }

    /// H-01: the vetoer can veto a fully-collected proposal (emergency brake stays available), and
    /// the funds are then recoverable to contributors by actual contribution (M-03).
    function test_h01_vetoFundedProposal_refundsContributors() public {
        uint256 pid = _passAndCollect(6 ether);
        assertEq(dao.escrowAddressOf(pid).balance, 6 ether);

        dao.veto(pid); // this contract is the vetoer
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Vetoed));

        uint256 a = alice.balance;
        uint256 b = bob.balance;
        uint256 cb = carol.balance;
        dao.refund(pid, 100); // permissionless
        assertEq(dao.escrowAddressOf(pid).balance, 0, "escrow fully refunded");
        // shares of 6 from total 10: alice 1.8, bob 3.0, carol 1.2
        assertEq(alice.balance - a, 1.8 ether);
        assertEq(bob.balance - b, 3 ether);
        assertEq(carol.balance - cb, 1.2 ether);

        // No double refund.
        vm.expectRevert(ShwounsDAOProposals.AlreadyRefunded.selector);
        dao.refund(pid, 100);
    }

    /// The refund pages across bounded calls; the cursor advances one vault per batch.
    function test_h01_refund_pagesAcrossCalls() public {
        uint256 pid = _passAndCollect(6 ether);
        vm.prank(alice); dao.cancel(pid); // proposer cancels a funded proposal (allowed; H-01)
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Canceled));

        address escrow = dao.escrowAddressOf(pid);
        // Batch of 1 → refunds one vault (alice, index 0): 6*3/10 = 1.8.
        dao.refund(pid, 1);
        assertEq(escrow.balance, 4.2 ether, "after 1 vault");
        dao.refund(pid, 1); // bob: 3.0
        assertEq(escrow.balance, 1.2 ether, "after 2 vaults");
        dao.refund(pid, 1); // carol: 1.2 → complete
        assertEq(escrow.balance, 0, "fully refunded across pages");

        vm.expectRevert(ShwounsDAOProposals.AlreadyRefunded.selector);
        dao.refund(pid, 1);
    }

    /// finalize is unavailable once a refund has begun (review §3).
    function test_h01_finalizeBlockedOnceRefundStarted() public {
        uint256 pid = _passAndCollect(6 ether);
        vm.prank(alice); dao.cancel(pid);
        dao.refund(pid, 1); // start (and here finish — only 3 vaults, but begun regardless)
        // The proposal is Canceled, so finalize reverts on state anyway; the refundStarted guard
        // additionally blocks a Collected proposal mid-refund. Assert finalize is not possible.
        vm.expectRevert();
        dao.finalize(pid);
    }
}
