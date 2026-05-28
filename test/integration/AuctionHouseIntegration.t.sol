// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsAuctionHouse} from "../../src/auction/ShwounsAuctionHouse.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {GovernanceRewards} from "../../src/rewards/GovernanceRewards.sol";
import {IShwounsSeeder} from "../../src/interfaces/IShwounsSeeder.sol";
import {IShwounsDescriptorMinimal} from "../../src/interfaces/IShwounsDescriptorMinimal.sol";
import {IShwounsToken} from "../../src/interfaces/IShwounsToken.sol";
import {IChainalysisSanctionsList} from "../../src/interfaces/IChainalysisSanctionsList.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";
import {MockWETH} from "../mocks/MockWETH.sol";

contract AuctionHouseIntegrationTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    uint256 constant AUCTION_DURATION = 24 hours;
    uint192 constant RESERVE_PRICE = 0.01 ether;
    uint56 constant TIME_BUFFER = 5 minutes;
    uint8 constant MIN_BID_INCREMENT_PCT = 2;

    ShwounsToken token;
    ShwounsAuctionHouse auctionHouse; // (proxy address)
    ShwounsAuctionHouse auctionHouseImpl;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    GovernanceRewards rewards;
    MockWETH weth;
    MockDescriptor descriptor;
    ShwounsSeeder seeder;

    address foundersDAO = makeAddr("foundersDAO");
    address daoLogic = makeAddr("daoLogic");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // 1. Etch the canonical ERC-6551 registry
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        // 2. Supporting contracts
        weth = new MockWETH();
        descriptor = new MockDescriptor();
        seeder = new ShwounsSeeder();
        rewards = new GovernanceRewards();

        // 3. ShwounsToken (auctionHouse address is set later via setMinter)
        token = new ShwounsToken(foundersDAO, address(this), descriptor, seeder);

        // 4. VaultRegistry + Vault impl
        registry = new ShwounsVaultRegistry(address(token));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));
        registry.setDAOLogic(daoLogic);

        // 5. AuctionHouse — UUPS proxy
        auctionHouseImpl = new ShwounsAuctionHouse(
            IShwounsToken(address(token)),
            address(weth),
            AUCTION_DURATION
        );
        bytes memory initData = abi.encodeWithSelector(
            ShwounsAuctionHouse.initialize.selector,
            RESERVE_PRICE,
            TIME_BUFFER,
            MIN_BID_INCREMENT_PCT,
            IChainalysisSanctionsList(address(0))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(auctionHouseImpl), initData);
        auctionHouse = ShwounsAuctionHouse(address(proxy));

        // 6. Wire everything
        auctionHouse.setGovernanceRewards(address(rewards));
        auctionHouse.setVaultRegistry(registry);
        token.setMinter(address(auctionHouse));

        // 7. Unpause to kick off the first auction
        auctionHouse.unpause();
    }

    // -------------------------------------------------------------------------
    // Deployment + initial state
    // -------------------------------------------------------------------------

    function test_setUp_kicksOffFirstAuction() public {
        ShwounsAuctionHouse.AuctionV2View memory a = auctionHouse.auction();
        // First mint produces founder Shwoun 0 + auction Shwoun 1
        assertEq(a.shwounId, 1);
        assertEq(token.ownerOf(0), foundersDAO, "founder Shwoun 0 goes to founders");
        assertEq(token.ownerOf(1), address(auctionHouse), "auction Shwoun 1 held by auctionHouse");
    }

    function test_setUp_createsVaultsForFirstMint() public {
        // Both Shwoun 0 (founder) and Shwoun 1 (auction) should have vaults deployed
        address vault0 = registry.vaultOf(0);
        address vault1 = registry.vaultOf(1);
        assertGt(vault0.code.length, 0, "founder vault deployed");
        assertGt(vault1.code.length, 0, "auction vault deployed");

        // Vault 0's owner is foundersDAO
        ShwounsVault v0 = ShwounsVault(payable(vault0));
        assertEq(v0.owner(), foundersDAO);
    }

    // -------------------------------------------------------------------------
    // Auction lifecycle — winning bid
    // -------------------------------------------------------------------------

    function test_winningBid_routesETHToRewards_andShwounToBidder() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        auctionHouse.createBid{value: 1 ether}(1);

        // Fast-forward past auction end
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        uint256 rewardsBefore = address(rewards).balance;

        // Settle + create next auction
        auctionHouse.settleCurrentAndCreateNewAuction();

        assertEq(token.ownerOf(1), alice, "winning bidder receives the Shwoun");
        assertEq(address(rewards).balance - rewardsBefore, 1 ether, "proceeds went to GovernanceRewards");
    }

    // -------------------------------------------------------------------------
    // Auction lifecycle — no bid
    // -------------------------------------------------------------------------

    function test_noBid_shwounGoesToRewards_andItsVaultIsOwned_byRewards() public {
        vm.warp(block.timestamp + AUCTION_DURATION + 1);

        auctionHouse.settleCurrentAndCreateNewAuction();

        // Shwoun 1 (no bidder) → GovernanceRewards
        assertEq(token.ownerOf(1), address(rewards), "no-bid Shwoun routes to rewards");

        // Vault for Shwoun 1 is owned by GovernanceRewards
        ShwounsVault v1 = ShwounsVault(payable(registry.vaultOf(1)));
        assertEq(v1.owner(), address(rewards));

        // Anyone can deposit to Shwoun 1's vault even though rewards owns it
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        (bool ok, ) = address(v1).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(v1).balance, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Founder Shwoun vault creation
    // -------------------------------------------------------------------------

    function test_founderShwoun_atTenthAuction_getsVault() public {
        // First auction: setup minted Shwouns 0 (founder) and 1 (auction).
        // Run 9 more auctions to reach the next founder mint at Shwoun 10.
        for (uint256 i = 0; i < 9; i++) {
            vm.warp(block.timestamp + AUCTION_DURATION + 1);
            auctionHouse.settleCurrentAndCreateNewAuction();
        }
        // After 9 more auctions, Shwoun 10 (founder) and Shwoun 11 (auction) should be minted.
        assertEq(token.ownerOf(10), foundersDAO);

        ShwounsAuctionHouse.AuctionV2View memory a = auctionHouse.auction();
        assertEq(a.shwounId, 11);
        assertEq(token.ownerOf(11), address(auctionHouse));

        // Both have vaults deployed
        assertGt(registry.vaultOf(10).code.length, 0, "founder vault 10 deployed");
        assertGt(registry.vaultOf(11).code.length, 0, "auction vault 11 deployed");
    }

    // -------------------------------------------------------------------------
    // UUPS upgrade
    // -------------------------------------------------------------------------

    function test_uupsUpgrade_byOwner_works() public {
        // Deploy a new impl with the same constructor args
        ShwounsAuctionHouse newImpl = new ShwounsAuctionHouse(
            IShwounsToken(address(token)),
            address(weth),
            AUCTION_DURATION
        );

        // Upgrade
        auctionHouse.upgradeTo(address(newImpl));

        // State should be preserved — auctionStorage.shwounId is still 1
        ShwounsAuctionHouse.AuctionV2View memory a = auctionHouse.auction();
        assertEq(a.shwounId, 1);
    }

    function test_uupsUpgrade_byNonOwner_reverts() public {
        ShwounsAuctionHouse newImpl = new ShwounsAuctionHouse(
            IShwounsToken(address(token)),
            address(weth),
            AUCTION_DURATION
        );

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        auctionHouse.upgradeTo(address(newImpl));
    }

    // -------------------------------------------------------------------------
    // Setter locks
    // -------------------------------------------------------------------------

    function test_setGovernanceRewards_locksAfterFirstSet() public {
        vm.expectRevert(ShwounsAuctionHouse.AlreadyLocked.selector);
        auctionHouse.setGovernanceRewards(address(0xdead));
    }

    function test_setVaultRegistry_locksAfterFirstSet() public {
        vm.expectRevert(ShwounsAuctionHouse.AlreadyLocked.selector);
        auctionHouse.setVaultRegistry(registry);
    }

    // -------------------------------------------------------------------------
    // Sanity: total auction → proceeds accumulate in GovernanceRewards
    // -------------------------------------------------------------------------

    function test_multipleAuctions_proceedsAccumulate() public {
        uint256 totalBids = 0;

        // Bid + settle 5 auctions
        for (uint256 i = 0; i < 5; i++) {
            uint256 bidAmount = (i + 1) * 0.1 ether;
            address bidder = address(uint160(0x1000 + i));
            vm.deal(bidder, bidAmount);
            vm.prank(bidder);
            ShwounsAuctionHouse.AuctionV2View memory a = auctionHouse.auction();
            auctionHouse.createBid{value: bidAmount}(a.shwounId);
            totalBids += bidAmount;

            vm.warp(block.timestamp + AUCTION_DURATION + 1);
            auctionHouse.settleCurrentAndCreateNewAuction();
        }

        assertEq(address(rewards).balance, totalBids);
        assertEq(rewards.lifetimeETHReceived(), totalBids);
    }
}
