// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {BootstrapFixture} from "./BootstrapFixture.sol";
import {Bootstrap} from "../../src/governance/Bootstrap.sol";
import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ShwounsAuctionHouse} from "../../src/auction/ShwounsAuctionHouse.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {GovernanceRewards} from "../../src/rewards/GovernanceRewards.sol";
import {GovernanceIncentivesNFT} from "../../src/rewards/GovernanceIncentivesNFT.sol";
import {ApprovalRegistry} from "../../src/rewards/ApprovalRegistry.sol";
import {GovernanceAuthRegistry} from "../../src/governance/GovernanceAuthRegistry.sol";

/// @notice Exercises the GENERIC operator-gated Bootstrap (audit F1/F2/F3): the full system is
///         deployed via ShwounsDeployer (CREATE2 through Bootstrap, library link-patching), art is
///         loaded through Bootstrap.execute (F3), the operator gate blocks front-running (F2), and a
///         single finalizeBootstrap atomically hands every role to the DAO (A10).
contract DeploymentTest is BootstrapFixture {
    function setUp() public {
        _deploySystem();
    }

    // typed accessors over the manifest addresses
    function _token() internal view returns (ShwounsToken) { return ShwounsToken(m.token); }
    function _dao() internal view returns (ShwounsDAOLogic) { return ShwounsDAOLogic(payable(m.dao)); }
    function _ah() internal view returns (ShwounsAuctionHouse) { return ShwounsAuctionHouse(payable(m.auctionHouse)); }
    function _vr() internal view returns (ShwounsVaultRegistry) { return ShwounsVaultRegistry(m.vaultRegistry); }
    function _rewards() internal view returns (GovernanceRewards) { return GovernanceRewards(payable(m.rewards)); }
    function _gi() internal view returns (GovernanceIncentivesNFT) { return GovernanceIncentivesNFT(m.giNFT); }

    // ---- deployment + wiring (pre-finalize) ----

    function test_allContracts_deployed() public {
        assertTrue(m.token.code.length > 0, "token");
        assertTrue(m.authRegistry.code.length > 0, "auth registry");
        assertTrue(m.vaultRegistry.code.length > 0, "vault registry");
        assertTrue(m.vaultImpl.code.length > 0, "vault impl");
        assertTrue(m.auctionHouse.code.length > 0, "auction house proxy");
        assertTrue(m.dao.code.length > 0, "dao proxy");
        assertTrue(m.proposalEscrowImpl.code.length > 0, "escrow impl");
        assertTrue(m.rewards.code.length > 0, "rewards");
        assertTrue(m.giNFT.code.length > 0, "gi nft");
        assertTrue(m.approvalRegistry.code.length > 0, "approval registry");
        assertTrue(m.descriptor.code.length > 0, "descriptor");
        assertTrue(m.art.code.length > 0, "art");
    }

    function test_wiring() public {
        assertEq(_token().minter(), m.auctionHouse, "token minter");
        assertEq(_vr().vaultImplementation(), m.vaultImpl);
        assertTrue(_vr().vaultImplementationLocked());
        assertEq(_vr().daoLogic(), m.dao);
        assertEq(_ah().governanceRewards(), m.rewards);
        assertEq(address(_ah().vaultRegistry()), m.vaultRegistry);
        assertEq(address(_dao().governanceRewards()), m.rewards);
        assertEq(address(_rewards().dao()), m.dao);
        assertEq(address(_rewards().approvalRegistry()), m.approvalRegistry);
        assertEq(address(ApprovalRegistry(m.approvalRegistry).giNFT()), m.giNFT);
        assertEq(_dao().proposalEscrowImplementation(), m.proposalEscrowImpl);
        assertEq(_gi().proceedsRecipient(), m.rewards); // A6: GI proceeds -> GR
    }

    function test_immutableWiring() public {
        assertEq(GovernanceAuthRegistry(m.authRegistry).binder(), address(b), "binder = Bootstrap");
        assertEq(address(_token().governanceAuth()), m.authRegistry, "token auth");
        assertEq(address(_ah().shwouns()), m.token, "ah.shwouns");
        assertEq(_vr().shwounsToken(), m.token, "vr.shwounsToken");
        assertEq(address(_dao().shwouns()), m.token, "dao.shwouns");
        assertEq(address(_dao().vaultRegistry()), m.vaultRegistry, "dao.vaultRegistry");
    }

    function test_params() public {
        assertEq(_dao().votingDelay(), cfg.votingDelay);
        assertEq(_dao().votingPeriod(), cfg.votingPeriod);
        assertEq(_rewards().proposalRewardAmount(), cfg.proposalReward);
        assertEq(_gi().mintPrice(), cfg.giMintPrice);
    }

    /// Before handoff: Bootstrap owns everything, the registry is unbound, the auction is paused.
    function test_preFinalize_bootstrapHoldsRoles_auctionPaused_registryUnbound() public {
        assertEq(_token().owner(), address(b), "token owned by Bootstrap");
        assertEq(_rewards().owner(), address(b), "rewards owned by Bootstrap");
        assertEq(_dao().admin(), address(b), "DAO admin is Bootstrap");
        assertEq(GovernanceAuthRegistry(m.authRegistry).daoLogic(), address(0), "registry unbound");
        assertTrue(_ah().paused(), "auction paused during bootstrap");
        assertFalse(b.finalized());
    }

    // ---- F2: operator gate / front-run protection ----

    function test_f2_nonOperator_cannotDeploy() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(Bootstrap.NotOperator.selector);
        b.deploy(hex"00", bytes32(0));
    }

    function test_f2_nonOperator_cannotExecute() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(Bootstrap.NotOperator.selector);
        b.execute(m.descriptor, abi.encodeWithSignature("lockParts()"));
    }

    function test_f2_nonOperator_cannotFinalize() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(Bootstrap.NotOperator.selector);
        b.finalizeBootstrap();
    }

    function test_f2_execute_onlyRegisteredTargets() public {
        address foreign = makeAddr("foreign");
        vm.expectRevert(abi.encodeWithSelector(Bootstrap.NotRegistered.selector, foreign));
        b.execute(foreign, hex"");
    }

    function test_f2_deployExecute_barredAfterFinalize() public {
        _loadMinimalArtAndLock();
        b.finalizeBootstrap();
        vm.expectRevert(Bootstrap.AlreadyFinalized.selector);
        b.deploy(hex"00", bytes32(uint256(1)));
        vm.expectRevert(Bootstrap.AlreadyFinalized.selector);
        b.execute(m.descriptor, hex"");
    }

    // ---- finalize prechecks ----

    /// finalize reverts if art isn't locked (a precheck), so it can't hand off an unfinished system.
    function test_finalize_revertsIfPartsNotLocked() public {
        vm.expectRevert(bytes("lock: descriptor.parts"));
        b.finalizeBootstrap();
    }

    // ---- finalizeBootstrap handoff (A10) ----

    function test_finalizeBootstrap_handsOffToGovernance_andRevokesBootstrap() public {
        _loadMinimalArtAndLock();
        b.finalizeBootstrap();
        address dao = m.dao;

        assertEq(_token().owner(), dao, "token -> DAO");
        assertEq(_rewards().owner(), dao, "rewards -> DAO");
        assertEq(ApprovalRegistry(m.approvalRegistry).owner(), dao, "approvalRegistry -> DAO");
        assertEq(_gi().owner(), dao, "giNFT -> DAO");
        assertEq(_ah().owner(), dao, "auctionHouse -> DAO");
        assertEq(_vr().owner(), dao, "vaultRegistry -> DAO");

        assertEq(_dao().admin(), dao, "admin -> DAO");
        assertEq(GovernanceAuthRegistry(m.authRegistry).daoLogic(), dao, "registry bound to DAO");

        assertFalse(_ah().paused(), "auction running after handoff");
        assertTrue(b.finalized());

        vm.expectRevert(Bootstrap.AlreadyFinalized.selector);
        b.finalizeBootstrap();
    }

    // ---- A10.5 no-permanent-EOA structural enforcement (post-handoff) ----

    function test_a105_ownershipCannotMoveToEOA_afterHandoff() public {
        _loadMinimalArtAndLock();
        b.finalizeBootstrap();
        ShwounsToken tok = _token();
        address dao = m.dao;
        address eoa = makeAddr("eoa");

        vm.prank(dao);
        vm.expectRevert(); // OwnerMustBeDAOOrZero
        tok.transferOwnership(eoa);

        vm.prank(dao);
        tok.transferOwnership(dao); // DAO self-transfer permitted
        assertEq(tok.owner(), dao);
    }

    function test_a105_pendingAdminCannotBeEOA() public {
        _loadMinimalArtAndLock();
        b.finalizeBootstrap();
        ShwounsDAOLogic d = _dao();
        address dao = m.dao;

        vm.prank(dao);
        vm.expectRevert(); // AdminMustBeDAOOrZero
        d.setPendingAdmin(makeAddr("eoa"));

        vm.prank(dao);
        d.setPendingAdmin(address(0));
    }

    // ---- end-to-end: the whole handed-off system works (auction -> vault -> proposal -> escrow) ----

    function test_endToEnd_auctionThenGovernanceExecutesViaEscrow() public {
        _loadMinimalArtAndLock();
        b.finalizeBootstrap(); // auction #1 running, all roles with the DAO
        ShwounsToken token = _token();
        ShwounsAuctionHouse ah = _ah();
        ShwounsDAOLogic dao = _dao();

        ShwounsAuctionHouse.AuctionV2View memory a = ah.auction();
        assertEq(a.shwounId, 1, "first auction Shwoun is 1");
        address bidder = makeAddr("bidder");
        vm.deal(bidder, 5 ether);
        vm.prank(bidder);
        ah.createBid{value: 1 ether}(1);
        vm.warp(a.endTime + 1);
        ah.settleCurrentAndCreateNewAuction();
        assertEq(token.ownerOf(1), bidder, "Shwoun 1 -> bidder");
        assertEq(m.rewards.balance, 1 ether, "proceeds -> GovernanceRewards");

        ShwounsVault bidderVault = ShwounsVault(payable(_vr().vaultOf(1)));
        vm.prank(bidder); bidderVault.deposit{value: 2 ether}();
        vm.prank(bidder); token.delegate(bidder);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("propTarget");
        values[0] = 1 ether;
        vm.prank(bidder);
        uint256 pid = dao.propose(targets, values, sigs, cd, "e2e");

        vm.roll(block.number + cfg.votingDelay + 1);
        vm.prank(bidder); dao.castVote(pid, 1);
        vm.roll(block.number + cfg.votingPeriod + 1);
        assertEq(uint256(dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Succeeded));

        dao.queue(pid);
        dao.recordSnapshot(pid, 10);
        dao.collect(pid, 10);

        uint256 grBefore = m.rewards.balance;
        dao.finalize(pid);

        assertEq(targets[0].balance, 1 ether, "proposal executed via escrow");
        assertEq(_rewards().proposalRewardPool(pid), cfg.proposalReward, "voter reward pool reserved");
        assertEq(m.rewards.balance, grBefore, "GR balance unchanged at allocation");
    }
}
