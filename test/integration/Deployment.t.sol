// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Bootstrap} from "../../src/governance/Bootstrap.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ShwounsAuctionHouse} from "../../src/auction/ShwounsAuctionHouse.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {IShwounsArt} from "../../src/interfaces/IShwounsArt.sol";
import {ISVGRenderer} from "../../src/interfaces/ISVGRenderer.sol";
import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";

/// @notice Exercises the persistent Bootstrap deployment coordinator (H-02) and its one-shot
///         finalizeBootstrap handoff (A10), plus the no-permanent-EOA structural enforcement (A10.5).
contract DeploymentTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    Bootstrap b;
    Bootstrap.Config cfg;
    address foundersDAO = makeAddr("foundersDAO");

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        MockWETH weth = new MockWETH();
        MockDescriptor mockDesc = new MockDescriptor();

        cfg = Bootstrap.Config({
            foundersDAO: foundersDAO,
            weth: address(weth),
            auctionDuration: 86400,
            reservePrice: 0.01 ether,
            timeBuffer: 300,
            minBidIncrementPct: 2,
            votingDelay: 1,
            votingPeriod: 7200,
            proposalThresholdBPS: 1,
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400,
            quorumVotesBPS: 1000,
            giMintPrice: 0.01 ether,
            proposalReward: 0.1 ether,
            maxRefundPerVote: 0.003 ether,
            lastMinuteWindowBlocks: 1,
            objectionPeriodBlocks: 3,
            art: IShwounsArt(address(0)),
            renderer: ISVGRenderer(address(0)),
            preDeployedDescriptor: IShwounsDescriptorMinimal(address(mockDesc))
        });

        b = new Bootstrap();
        b.deploy(cfg);
    }

    // ---- deployment + wiring (pre-finalize) ----

    function test_allContracts_deployed() public {
        assertTrue(address(b.token()).code.length > 0, "token");
        assertTrue(address(b.authRegistry()).code.length > 0, "auth registry");
        assertTrue(address(b.vaultRegistry()).code.length > 0, "vault registry");
        assertTrue(address(b.vaultImpl()).code.length > 0, "vault impl");
        assertTrue(address(b.auctionHouse()).code.length > 0, "auction house proxy");
        assertTrue(address(b.dao()).code.length > 0, "dao proxy");
        assertTrue(address(b.proposalEscrowImpl()).code.length > 0, "escrow impl");
        assertTrue(address(b.rewards()).code.length > 0, "rewards");
        assertTrue(address(b.giNFT()).code.length > 0, "gi nft");
        assertTrue(address(b.approvalRegistry()).code.length > 0, "approval registry");
        assertTrue(address(b.daoData()).code.length > 0, "dao data");
    }

    function test_wiring() public {
        assertEq(b.token().minter(), address(b.auctionHouse()), "token minter");
        assertEq(b.vaultRegistry().vaultImplementation(), address(b.vaultImpl()));
        assertTrue(b.vaultRegistry().vaultImplementationLocked());
        assertEq(b.vaultRegistry().daoLogic(), address(b.dao()));
        assertEq(b.auctionHouse().governanceRewards(), address(b.rewards()));
        assertEq(address(b.auctionHouse().vaultRegistry()), address(b.vaultRegistry()));
        assertEq(address(b.dao().governanceRewards()), address(b.rewards()));
        assertEq(address(b.rewards().dao()), address(b.dao()));
        assertEq(address(b.rewards().approvalRegistry()), address(b.approvalRegistry()));
        assertEq(address(b.approvalRegistry().giNFT()), address(b.giNFT()));
        assertEq(b.dao().proposalEscrowImplementation(), address(b.proposalEscrowImpl()));
        // A6: GI proceeds -> GR, ownership independent.
        assertEq(b.giNFT().proceedsRecipient(), address(b.rewards()));
    }

    function test_params() public {
        assertEq(b.dao().votingDelay(), cfg.votingDelay);
        assertEq(b.dao().votingPeriod(), cfg.votingPeriod);
        assertEq(b.rewards().proposalRewardAmount(), cfg.proposalReward);
        assertEq(b.giNFT().mintPrice(), cfg.giMintPrice);
    }

    /// Before handoff: Bootstrap owns everything, the registry is unbound, the auction is paused.
    function test_preFinalize_bootstrapHoldsRoles_auctionPaused_registryUnbound() public {
        assertEq(b.token().owner(), address(b), "token owned by Bootstrap");
        assertEq(b.rewards().owner(), address(b), "rewards owned by Bootstrap");
        assertEq(b.dao().admin(), address(b), "DAO admin is Bootstrap");
        assertEq(b.authRegistry().daoLogic(), address(0), "registry unbound");
        assertTrue(b.auctionHouse().paused(), "auction paused during bootstrap");
        assertFalse(b.finalized());
    }

    // ---- finalizeBootstrap handoff (A10) ----

    function test_finalizeBootstrap_handsOffToGovernance_andRevokesBootstrap() public {
        b.finalizeBootstrap();
        address dao = address(b.dao());

        // All ownership -> DAO.
        assertEq(b.token().owner(), dao, "token -> DAO");
        assertEq(b.rewards().owner(), dao, "rewards -> DAO");
        assertEq(b.approvalRegistry().owner(), dao, "approvalRegistry -> DAO");
        assertEq(b.giNFT().owner(), dao, "giNFT -> DAO");
        assertEq(b.auctionHouse().owner(), dao, "auctionHouse -> DAO");
        assertEq(b.vaultRegistry().owner(), dao, "vaultRegistry -> DAO");

        // DAO admin -> DAO itself; registry bound to DAO.
        assertEq(b.dao().admin(), dao, "admin -> DAO");
        assertEq(b.authRegistry().daoLogic(), dao, "registry bound to DAO");

        // First auction kicked off (deadlock-free genesis), Bootstrap revoked.
        assertFalse(b.auctionHouse().paused(), "auction running after handoff");
        assertTrue(b.finalized());

        // Second finalize reverts.
        vm.expectRevert(Bootstrap.AlreadyFinalized.selector);
        b.finalizeBootstrap();
    }

    // ---- A10.5 no-permanent-EOA structural enforcement (post-handoff) ----

    function test_a105_ownershipCannotMoveToEOA_afterHandoff() public {
        b.finalizeBootstrap();
        ShwounsToken tok = b.token(); // cache before pranking (getter would consume the prank)
        address dao = address(b.dao());
        address eoa = makeAddr("eoa");

        // Acting AS the DAO (the owner), ownership still cannot move to an EOA.
        vm.prank(dao);
        vm.expectRevert(); // OwnerMustBeDAOOrZero
        tok.transferOwnership(eoa);

        // DAO-or-zero destinations are allowed.
        vm.prank(dao);
        tok.transferOwnership(dao); // no-op self-transfer, permitted
        assertEq(tok.owner(), dao);
    }

    function test_a105_pendingAdminCannotBeEOA() public {
        b.finalizeBootstrap();
        ShwounsDAOLogic d = b.dao(); // cache before pranking
        address dao = address(d);
        address eoa = makeAddr("eoa");

        vm.prank(dao);
        vm.expectRevert(); // AdminMustBeDAOOrZero
        d.setPendingAdmin(eoa);

        // DAO/zero are permitted.
        vm.prank(dao);
        d.setPendingAdmin(address(0));
    }

    // ---- end-to-end: the whole handed-off system works (auction -> vault -> proposal -> escrow) ----

    function test_endToEnd_auctionThenGovernanceExecutesViaEscrow() public {
        b.finalizeBootstrap(); // auction #1 now running, all roles with the DAO
        ShwounsToken token = b.token();
        ShwounsAuctionHouse ah = b.auctionHouse();
        ShwounsDAOLogic dao = b.dao();

        // Auction #1 is live; bid and settle so a bidder gets Shwoun #1 + GR earns the proceeds.
        ShwounsAuctionHouse.AuctionV2View memory a = ah.auction();
        assertEq(a.shwounId, 1, "first auction Shwoun is 1");
        address bidder = makeAddr("bidder");
        vm.deal(bidder, 5 ether);
        vm.prank(bidder);
        ah.createBid{value: 1 ether}(1);
        vm.warp(block.timestamp + cfg.auctionDuration + 1);
        ah.settleCurrentAndCreateNewAuction();
        assertEq(token.ownerOf(1), bidder, "Shwoun 1 -> bidder");
        assertEq(address(b.rewards()).balance, 1 ether, "proceeds -> GovernanceRewards");

        // Bidder funds their vault, delegates, and runs a full governance proposal.
        ShwounsVault bidderVault = ShwounsVault(payable(b.vaultRegistry().vaultOf(1)));
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

        dao.queue(pid); // small active set -> frozen in queue
        dao.recordSnapshot(pid, 10);
        dao.collect(pid, 10);

        uint256 grBefore = address(b.rewards()).balance;
        dao.finalize(pid); // executes from the proposal's escrow

        assertEq(targets[0].balance, 1 ether, "proposal executed via escrow");
        assertEq(b.rewards().proposalRewardPool(pid), cfg.proposalReward, "voter reward pool reserved");
        assertEq(address(b.rewards()).balance, grBefore, "GR balance unchanged at allocation");
    }
}
