// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";

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

    function _deploy(uint256 votingDelay_, uint256 votingPeriod_, uint256 quorumBPS_) internal {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder);
        registry = new ShwounsVaultRegistry(address(token));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: votingPeriod_,
            votingDelay: votingDelay_,
            proposalThresholdBPS: 0
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this),
            address(this), // vetoer = this contract so tests can veto/transfer
            IShwounsTokenLike(address(token)),
            registry,
            params,
            quorumBPS_
        );
        ERC1967Proxy daoProxy = new ERC1967Proxy(address(daoImpl), initData);
        dao = ShwounsDAOLogic(payable(address(daoProxy)));

        registry.setDAOLogic(address(dao));

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
        _deploy(1, 5, 1000);
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
        dao.setVotingPeriod(100);
        assertEq(dao.votingPeriod(), 100);
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
        _deploy(1, 5, 0); // base quorum 0 — rely on dynamic
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
        vm.roll(block.number + 6);

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
        vm.roll(block.number + 6);

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
// Stuck-fund recovery test
// =============================================================================

contract DAORefundStuckTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 5, 1000);
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
        vm.roll(block.number + 6);

        dao.queue(pid);
        dao.recordSnapshot(pid, 10);

        uint256[] memory vaultIds = new uint256[](3);
        vaultIds[0] = aliceNoun;
        vaultIds[1] = bobNoun;
        vaultIds[2] = carolNoun;
        dao.collect(pid, vaultIds);

        // Finalize reverts
        vm.expectRevert();
        dao.finalize(pid);

        assertEq(address(dao).balance, 5 ether, "DAO holds the collected 5 ETH");

        // Refund — proportional to the snapshot, returns ETH to current owners
        address[] memory assets = new address[](1);
        assets[0] = address(0);
        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;
        uint256 carolBefore = carol.balance;

        dao.refundStuckProposal(pid, assets);

        // Pro-rata: alice 5*3/10=1.5, bob 5*5/10=2.5, carol 5*2/10=1.0
        assertEq(alice.balance - aliceBefore, 1.5 ether);
        assertEq(bob.balance - bobBefore, 2.5 ether);
        assertEq(carol.balance - carolBefore, 1.0 ether);
        assertEq(address(dao).balance, 0);
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
        _deploy(1, 10, 1000);
        // 3-block last-minute window, 5-block extension
        dao.setLastMinuteWindowInBlocks(3);
        dao.setObjectionPeriodDurationInBlocks(5);
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

        // Jump to last-minute window (within 3 blocks of endBlock)
        vm.roll(block.number + 8);

        // Alice votes For — this is the FLIP from failing (1-1 tie) to succeeding (2-1)
        vm.prank(alice); dao.castVote(pid, 1);

        // Should have triggered objection period; after endBlock we should see ObjectionPeriod state
        vm.roll(block.number + 3); // past original endBlock
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

        // Pattern: bob against, alice for (1-1 tie failing), then last-minute carol for triggers
        vm.prank(bob); dao.castVote(pid, 0);
        vm.prank(alice); dao.castVote(pid, 1);
        vm.roll(block.number + 8);
        vm.prank(carol); dao.castVote(pid, 1);
        vm.roll(block.number + 3); // now in objection period

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
        _deploy(1, 5, 1000);
        usdc = new MockERC20();

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
        vm.roll(block.number + 6);

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
        dao.collect(pid, vaultIds);

        // Pro-rata: total = 350, requested = 175, so half pulled from each
        // alice contributes 175 * 100/350 = 50
        // bob contributes 175 * 200/350 = 100
        // carol contributes 175 * 50/350 = 25
        // Total = 175 in DAOLogic
        assertEq(usdc.balanceOf(address(dao)), 175e18);

        dao.finalize(pid);
        assertEq(usdc.balanceOf(recipient), 175e18);
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
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder);
        registry = new ShwounsVaultRegistry(address(token));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));

        ShwounsDAOLogic daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory params = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: 5,
            votingDelay: 1,
            // Threshold: 6000 BPS = 60% of supply. With 3 supply, threshold = 1.8 → integer 1.
            // So 2 signers together (2 votes) clear it; 1 signer alone (1 vote) doesn't.
            proposalThresholdBPS: 6000
        });
        bytes memory initData = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this),
            address(0),
            IShwounsTokenLike(address(token)),
            registry,
            params,
            1000
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
        vm.roll(block.number + 1);
    }

    function _signProposal(
        uint256 pk,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) internal view returns (bytes memory) {
        bytes32 digest = dao.proposalDigest(targets, values, signatures, calldatas, description);
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

        // Both sigAlice and sigBob sign the proposal
        bytes memory aliceSig = _signProposal(sigAlicePk, targets, values, sigs, cd, "signed proposal");
        bytes memory bobSig = _signProposal(sigBobPk, targets, values, sigs, cd, "signed proposal");

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](2);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: block.timestamp + 1 days
        });
        proposerSigs[1] = ShwounsDAOTypes.ProposerSignature({
            sig: bobSig, signer: sigBob, expirationTimestamp: block.timestamp + 1 days
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

        bytes memory aliceSig = _signProposal(sigAlicePk, targets, values, sigs, cd, "lone signer");
        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](1);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: block.timestamp + 1 days
        });

        // totalSupply = 4 (founder 0 + auction 1-3). threshold = 4 * 6000 / 10000 = 2.
        // Single signer has 1 vote, 1 < 2 → must revert.
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

        bytes memory aliceSig = _signProposal(sigAlicePk, targets, values, sigs, cd, "cancel test");
        bytes memory bobSig = _signProposal(sigBobPk, targets, values, sigs, cd, "cancel test");

        // Alice cancels her sig before submission
        vm.prank(sigAlice);
        dao.cancelSig(aliceSig);

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](2);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: block.timestamp + 1 days
        });
        proposerSigs[1] = ShwounsDAOTypes.ProposerSignature({
            sig: bobSig, signer: sigBob, expirationTimestamp: block.timestamp + 1 days
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

        bytes memory aliceSig = _signProposal(sigAlicePk, targets, values, sigs, cd, "expired");

        ShwounsDAOTypes.ProposerSignature[] memory proposerSigs = new ShwounsDAOTypes.ProposerSignature[](1);
        proposerSigs[0] = ShwounsDAOTypes.ProposerSignature({
            sig: aliceSig, signer: sigAlice, expirationTimestamp: block.timestamp - 1
        });

        vm.expectRevert(ShwounsDAOProposals.SigExpired.selector);
        dao.proposeBySigs(proposerSigs, targets, values, sigs, cd, "expired");
    }
}

// =============================================================================
// recordSnapshot paging test
// =============================================================================

contract DAOSnapshotPagingTest is DAOTestBase {
    function setUp() public {
        _deploy(1, 5, 1000);
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
        vm.roll(block.number + 6);
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
