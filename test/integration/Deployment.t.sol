// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {ShwounsDAOTypes} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsAuctionHouse} from "../../src/auction/ShwounsAuctionHouse.sol";
import {IShwounsArt} from "../../src/interfaces/IShwounsArt.sol";
import {ISVGRenderer} from "../../src/interfaces/ISVGRenderer.sol";
import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";

/// @notice Exercises the full Deploy.s.sol script against a local anvil-like environment.
///         Verifies all 13 contracts are deployed, wiring is correct, ownership is in the
///         intended state, and a full propose→vote→queue→snapshot→collect→finalize flow
///         works against the deployed system.
contract DeploymentTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    Deploy deployer;
    Deploy.Deployment d;
    Deploy.Config cfg;

    address operator = makeAddr("operator"); // the deployer EOA
    address foundersDAO = makeAddr("foundersDAO");

    function setUp() public {
        // Etch canonical ERC-6551 registry
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        // Deploy a WETH mock and a Descriptor-compatible mock (real Descriptor needs
        // Art+Renderer; we use MockDescriptor here so the test doesn't need to deploy art).
        MockWETH weth = new MockWETH();
        MockDescriptor mockDesc = new MockDescriptor();

        cfg = Deploy.Config({
            foundersDAO: foundersDAO,
            weth: address(weth),
            auctionDuration: 86400,
            reservePrice: 0.01 ether,
            timeBuffer: 300,
            minBidIncrementPct: 2,
            votingDelay: 1,         // 1 block for fast test cycles
            votingPeriod: 7200,     // min allowed voting period
            proposalThresholdBPS: 1,
            proposalUpdatablePeriodInBlocks: 0,
            proposalQueuePeriodInBlocks: 50400,
            quorumVotesBPS: 1000,   // 10%
            giMintPrice: 0.01 ether,
            proposalReward: 0.1 ether,
            maxRefundPerVote: 0.003 ether,
            lastMinuteWindowBlocks: 1,
            objectionPeriodBlocks: 3,
            art: IShwounsArt(address(0)),
            renderer: ISVGRenderer(address(0)),
            preDeployedDescriptor: IShwounsDescriptorMinimal(address(mockDesc)),
            adminTarget: operator
        });

        deployer = new Deploy();

        // _deploy uses Deploy contract as temporary admin; cfg.adminTarget is set as
        // pending admin. operator must call acceptAdmin to finalize.
        d = deployer._deploy(cfg);
        vm.prank(operator);
        d.dao.acceptAdmin();
        // Note: Ownable contracts (token, descriptor, auctionHouse, rewards, approvalRegistry)
        // are still owned by the Deploy contract at this point. Tests that need ownership
        // either call transferOwnershipToDAO via the Deploy contract OR vm.prank as Deploy.
    }

    // -------------------------------------------------------------------------
    // Verify all contracts exist
    // -------------------------------------------------------------------------

    function test_allContracts_deployed() public {
        assertTrue(address(d.token).code.length > 0, "token");
        assertTrue(address(d.seeder).code.length > 0, "seeder");
        // d.descriptor is address(0) when preDeployedDescriptor was used (test setup).
        // Verify the token was wired to SOMETHING (descriptor or pre-deployed mock).
        assertTrue(address(d.token.descriptor()).code.length > 0, "descriptor (or mock)");
        assertTrue(address(d.vaultRegistry).code.length > 0, "vault registry");
        assertTrue(address(d.vaultImpl).code.length > 0, "vault impl");
        assertTrue(address(d.auctionHouse).code.length > 0, "auction house proxy");
        assertTrue(address(d.auctionHouseImpl).code.length > 0, "auction house impl");
        assertTrue(address(d.dao).code.length > 0, "dao proxy");
        assertTrue(address(d.daoImpl).code.length > 0, "dao impl");
        assertTrue(address(d.rewards).code.length > 0, "rewards");
        assertTrue(address(d.giNFT).code.length > 0, "gi nft");
        assertTrue(address(d.approvalRegistry).code.length > 0, "approval registry");
        assertTrue(address(d.daoData).code.length > 0, "dao data");
    }

    // -------------------------------------------------------------------------
    // Verify wiring
    // -------------------------------------------------------------------------

    function test_wiring_tokenMinter_isAuctionHouse() public {
        assertEq(d.token.minter(), address(d.auctionHouse));
    }

    function test_wiring_vaultRegistry_referencesToken() public {
        assertEq(d.vaultRegistry.shwounsToken(), address(d.token));
    }

    function test_wiring_vaultRegistry_hasVaultImpl_locked() public {
        assertEq(d.vaultRegistry.vaultImplementation(), address(d.vaultImpl));
        assertTrue(d.vaultRegistry.vaultImplementationLocked());
    }

    function test_wiring_vaultRegistry_daoLogic_locked() public {
        assertEq(d.vaultRegistry.daoLogic(), address(d.dao));
        assertTrue(d.vaultRegistry.daoLogicLocked());
    }

    function test_wiring_auctionHouse_governanceRewards_andRegistry() public {
        assertEq(d.auctionHouse.governanceRewards(), address(d.rewards));
        assertTrue(d.auctionHouse.governanceRewardsLocked());
        assertEq(address(d.auctionHouse.vaultRegistry()), address(d.vaultRegistry));
        assertTrue(d.auctionHouse.vaultRegistryLocked());
    }

    function test_wiring_dao_governanceRewards_locked() public {
        assertEq(address(d.dao.governanceRewards()), address(d.rewards));
        assertTrue(d.dao.governanceRewardsLocked());
    }

    function test_wiring_rewards_daoLogic_locked() public {
        assertEq(address(d.rewards.dao()), address(d.dao));
        assertTrue(d.rewards.daoLocked());
    }

    function test_wiring_rewards_approvalRegistry_locked() public {
        assertEq(address(d.rewards.approvalRegistry()), address(d.approvalRegistry));
        assertTrue(d.rewards.approvalRegistryLocked());
    }

    function test_wiring_approvalRegistry_referencesGiNFT() public {
        assertEq(address(d.approvalRegistry.giNFT()), address(d.giNFT));
    }

    function test_wiring_giNFT_ownerIsRewards() public {
        assertEq(d.giNFT.owner(), address(d.rewards));
    }

    // -------------------------------------------------------------------------
    // Verify parameters set correctly
    // -------------------------------------------------------------------------

    function test_params_dao() public {
        assertEq(d.dao.votingDelay(), cfg.votingDelay);
        assertEq(d.dao.votingPeriod(), cfg.votingPeriod);
        assertEq(d.dao.quorumVotesBPS(), cfg.quorumVotesBPS);
        assertEq(d.dao.lastMinuteWindowInBlocks(), cfg.lastMinuteWindowBlocks);
        assertEq(d.dao.objectionPeriodDurationInBlocks(), cfg.objectionPeriodBlocks);
    }

    function test_params_rewards() public {
        assertEq(d.rewards.proposalRewardAmount(), cfg.proposalReward);
        assertEq(d.rewards.maxRefundPerVote(), cfg.maxRefundPerVote);
    }

    function test_params_giNFT() public {
        assertEq(d.giNFT.mintPrice(), cfg.giMintPrice);
    }

    // -------------------------------------------------------------------------
    // Ownership transfers
    // -------------------------------------------------------------------------

    function test_ownership_transferOwnershipToDAO_movesAllOwnership() public {
        // Before transfer, owner is the Deploy contract (which created all the Ownables)
        assertEq(d.token.owner(), address(deployer));
        assertEq(d.rewards.owner(), address(deployer));

        deployer.transferOwnershipToDAO(d);

        // After transfer, ownership is the DAO
        assertEq(d.token.owner(), address(d.dao));
        assertEq(d.rewards.owner(), address(d.dao));
        assertEq(d.approvalRegistry.owner(), address(d.dao));
        assertEq(d.auctionHouse.owner(), address(d.dao));
        // d.descriptor is address(0) in this test (we used preDeployedDescriptor for art);
        // transferOwnershipToDAO skips it in that case. Skip the assertion too.
    }

    // -------------------------------------------------------------------------
    // Smoke test: full end-to-end flow
    // -------------------------------------------------------------------------

    function test_endToEnd_auctionAndProposal() public {
        // Kick off the auction. AuctionHouse is owned by Deploy contract at this point.
        deployer.startFirstAuction(d);

        ShwounsAuctionHouse.AuctionV2View memory a = d.auctionHouse.auction();
        assertEq(a.shwounId, 1, "first auction Shwoun is 1");

        // Bid and settle
        address bidder = makeAddr("bidder");
        vm.deal(bidder, 5 ether);
        vm.prank(bidder);
        d.auctionHouse.createBid{value: 1 ether}(1);

        vm.warp(block.timestamp + 86401);
        d.auctionHouse.settleCurrentAndCreateNewAuction();
        assertEq(d.token.ownerOf(1), bidder, "Shwoun 1 to bidder");
        assertEq(address(d.rewards).balance, 1 ether, "1 ETH to GovernanceRewards");

        // Bidder funds their vault and votes on a proposal
        ShwounsVault bidderVault = ShwounsVault(payable(d.vaultRegistry.vaultOf(1)));
        vm.prank(bidder); bidderVault.deposit{value: 2 ether}();
        vm.prank(bidder); d.token.delegate(bidder);
        vm.roll(block.number + 1);

        // Bidder proposes (proposalThresholdBPS = 0 so anyone can propose)
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("propTarget");
        values[0] = 1 ether;
        vm.prank(bidder);
        uint256 pid = d.dao.propose(targets, values, sigs, cd, "e2e smoke");

        vm.roll(block.number + cfg.votingDelay + 1);
        vm.prank(bidder); d.dao.castVote(pid, 1);
        vm.roll(block.number + cfg.votingPeriod + 1);

        assertEq(uint256(d.dao.state(pid)), uint256(ShwounsDAOTypes.ProposalState.Succeeded));

        d.dao.queue(pid);
        d.dao.recordSnapshot(pid, 10);
        uint256[] memory vaultIds = new uint256[](1);
        vaultIds[0] = 1;
        d.dao.collect(pid, vaultIds.length);

        uint256 grBefore = address(d.rewards).balance;
        d.dao.finalize(pid);

        // Target received the 1 ETH
        assertEq(targets[0].balance, 1 ether);
        // GR earmarked the reward pool (allocation is bookkeeping; ETH stays in GR
        // until voters claim)
        assertEq(d.rewards.proposalRewardPool(pid), cfg.proposalReward);
        assertEq(address(d.rewards).balance, grBefore, "GR balance unchanged at allocation");
    }
}

