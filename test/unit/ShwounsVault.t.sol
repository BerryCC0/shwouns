// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import "../../src/vault/utils/Errors.sol"; // imports OwnershipCycle, NotAuthorized, etc.

contract ShwounsVaultTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    MockERC721 nft;
    MockERC20 token;
    ShwounsVaultRegistry registry;
    ShwounsVault vaultImpl;
    address daoLogic = makeAddr("daoLogic");

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    uint256 constant NOUN_ID = 1;

    function setUp() public {
        // 1. Etch the canonical ERC-6551 registry at its known address
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        // 2. Deploy mocks
        nft = new MockERC721();
        token = new MockERC20();

        // 3. Deployment dance per ShwounsVaultRegistry header docs
        registry = new ShwounsVaultRegistry(address(nft), address(0));
        vaultImpl = new ShwounsVault(address(registry));
        registry.setVaultImplementation(address(vaultImpl));
        registry.setDAOLogic(daoLogic);

        // 4. Mint a Noun to Alice
        nft.mint(alice, NOUN_ID);
    }

    // -------------------------------------------------------------------------
    // Vault address resolution + deployment
    // -------------------------------------------------------------------------

    function test_vaultOf_isDeterministic_beforeAndAfterDeploy() public {
        address predicted = registry.vaultOf(NOUN_ID);
        assertTrue(predicted != address(0));
        assertEq(predicted.code.length, 0, "vault not yet deployed");

        address deployed = registry.createVaultFor(NOUN_ID);
        assertEq(deployed, predicted, "deployed != predicted");
        assertGt(deployed.code.length, 0, "vault has code after deploy");
    }

    function test_createVaultFor_isIdempotent() public {
        address first = registry.createVaultFor(NOUN_ID);
        address second = registry.createVaultFor(NOUN_ID);
        assertEq(first, second);
    }

    function _vaultFor(uint256 tokenId) internal returns (ShwounsVault) {
        return ShwounsVault(payable(registry.createVaultFor(tokenId)));
    }

    // -------------------------------------------------------------------------
    // Deposit (ETH + ERC-20)
    // -------------------------------------------------------------------------

    function test_depositETH_viaReceive_funds_and_marksActive() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(bob, 5 ether);

        vm.prank(bob);
        (bool ok, ) = address(vault).call{value: 5 ether}("");
        assertTrue(ok);

        assertEq(address(vault).balance, 5 ether);
        assertEq(registry.activeVaultsLength(), 1);
        assertEq(registry.activeVaultAt(0), NOUN_ID);
    }

    function test_depositETH_viaDeposit_funds_and_marksActive() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(bob, 5 ether);

        vm.prank(bob);
        vault.deposit{value: 5 ether}();

        assertEq(address(vault).balance, 5 ether);
        assertEq(registry.activeVaultsLength(), 1);
    }

    function test_depositERC20_pullsTokens() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        token.mint(bob, 1000e18);

        vm.startPrank(bob);
        token.approve(address(vault), 1000e18);
        vault.depositERC20(address(token), 1000e18);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), 1000e18);
    }

    // -------------------------------------------------------------------------
    // Withdraw (owner + permissioned + non-owner reverts)
    // -------------------------------------------------------------------------

    function test_owner_canWithdrawETH() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        vm.prank(alice); // alice owns the noun
        vault.withdraw(alice, 2 ether);

        assertEq(alice.balance, 2 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_nonOwner_cannotWithdraw() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        vm.prank(bob); // bob does NOT own the noun
        vm.expectRevert();
        vault.withdraw(bob, 1 ether);
    }

    function test_permissioned_canWithdraw() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        // Alice grants Carol withdraw permission via Permissioned
        address[] memory callers = new address[](1);
        bool[] memory perms = new bool[](1);
        callers[0] = carol;
        perms[0] = true;

        vm.prank(alice);
        vault.setPermissions(callers, perms);

        // Carol can now withdraw
        vm.prank(carol);
        vault.withdraw(carol, 1 ether);
        assertEq(carol.balance, 1 ether);
    }

    function test_owner_canWithdrawERC20() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        token.mint(address(vault), 1000e18);

        vm.prank(alice);
        vault.withdrawERC20(address(token), alice, 500e18);

        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.balanceOf(address(vault)), 500e18);
    }

    // -------------------------------------------------------------------------
    // Ownership follows the NFT
    // -------------------------------------------------------------------------

    function test_ownerFollowsNFT_transfer() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        assertEq(vault.owner(), alice);

        // Alice transfers the Noun to Bob
        vm.prank(alice);
        nft.transferFrom(alice, bob, NOUN_ID);

        assertEq(vault.owner(), bob);

        // Alice can no longer withdraw
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(alice, 1 ether);

        // Bob can now withdraw
        vm.prank(bob);
        vault.withdraw(bob, 1 ether);
        assertEq(bob.balance, 1 ether);
    }

    function test_permissionsResetOnTransfer() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        // Alice grants Carol permission
        address[] memory callers = new address[](1);
        bool[] memory perms = new bool[](1);
        callers[0] = carol;
        perms[0] = true;
        vm.prank(alice);
        vault.setPermissions(callers, perms);

        // Transfer to Bob
        vm.prank(alice);
        nft.transferFrom(alice, bob, NOUN_ID);

        // Carol's old permission was keyed to Alice; doesn't carry to Bob
        vm.prank(carol);
        vm.expectRevert();
        vault.withdraw(carol, 1 ether);
    }

    // -------------------------------------------------------------------------
    // pullProRata — governance hook
    // -------------------------------------------------------------------------

    function test_pullProRata_onlyDAOLogic() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        vm.prank(alice); // even the owner can't call this
        vm.expectRevert(ShwounsVault.NotDAOLogic.selector);
        vault.pullProRata(1, address(0), bob, 1 ether);

        vm.prank(bob);
        vm.expectRevert(ShwounsVault.NotDAOLogic.selector);
        vault.pullProRata(1, address(0), bob, 1 ether);
    }

    function test_pullProRata_transfersETH() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        address recipient = makeAddr("propTarget");

        vm.prank(daoLogic);
        vault.pullProRata(42, address(0), recipient, 1.5 ether);

        assertEq(recipient.balance, 1.5 ether);
        assertEq(address(vault).balance, 1.5 ether);
    }

    function test_pullProRata_transfersERC20() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        token.mint(address(vault), 1000e18);

        address recipient = makeAddr("propTarget");

        vm.prank(daoLogic);
        vault.pullProRata(42, address(token), recipient, 400e18);

        assertEq(token.balanceOf(recipient), 400e18);
        assertEq(token.balanceOf(address(vault)), 600e18);
    }

    function test_pullProRata_revertsOnInsufficientETH() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 1 ether);

        vm.prank(daoLogic);
        vm.expectRevert(ShwounsVault.InsufficientBalance.selector);
        vault.pullProRata(42, address(0), bob, 5 ether);
    }

    // -------------------------------------------------------------------------
    // Ownership cycle protection
    // -------------------------------------------------------------------------

    function test_cannotSendBoundNFT_toOwnVault() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);

        vm.prank(alice);
        vm.expectRevert(OwnershipCycle.selector);
        nft.safeTransferFrom(alice, address(vault), NOUN_ID);
    }

    function test_canReceiveOtherNFT() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        uint256 otherTokenId = 999;
        nft.mint(alice, otherTokenId);

        vm.prank(alice);
        nft.safeTransferFrom(alice, address(vault), otherTokenId);

        assertEq(nft.ownerOf(otherTokenId), address(vault));
    }

    // -------------------------------------------------------------------------
    // Active-set maintenance
    // -------------------------------------------------------------------------

    function test_markActive_onlyValidVault() public {
        // Random address can't claim to be the vault for NOUN_ID
        vm.prank(bob);
        vm.expectRevert(ShwounsVaultRegistry.NotAuthorizedVault.selector);
        registry.markActive(NOUN_ID);
    }

    function test_markPossiblyInactive_removesEmptyVault() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(address(vault), 3 ether);

        // First mark active
        vm.prank(bob);
        vault.deposit{value: 0}(); // no-op deposit just to wire the call path
        // ETH was transferred via vm.deal — manually trigger active marking
        vm.deal(bob, 1);
        vm.prank(bob);
        vault.deposit{value: 1}();
        assertEq(registry.activeVaultsLength(), 1);

        // Alice fully drains
        vm.prank(alice);
        vault.withdraw(alice, address(vault).balance);

        assertEq(address(vault).balance, 0);
        assertEq(registry.activeVaultsLength(), 0);
    }

    function test_markPossiblyInactive_doesNotRemoveStillFundedVault() public {
        ShwounsVault vault = _vaultFor(NOUN_ID);
        vm.deal(bob, 3 ether);
        vm.prank(bob);
        vault.deposit{value: 3 ether}();
        assertEq(registry.activeVaultsLength(), 1);

        // Partial withdrawal
        vm.prank(alice);
        vault.withdraw(alice, 1 ether);

        // Vault still has 2 ether, must remain in active set
        assertEq(address(vault).balance, 2 ether);
        assertEq(registry.activeVaultsLength(), 1);
    }

    // -------------------------------------------------------------------------
    // Lockable setters
    // -------------------------------------------------------------------------

    function test_setVaultImplementation_locksAfterFirstCall() public {
        // Already set in setUp; second call must revert
        vm.expectRevert(ShwounsVaultRegistry.AlreadyLocked.selector);
        registry.setVaultImplementation(address(0xdead));
    }

    function test_setDAOLogic_locksAfterFirstCall() public {
        vm.expectRevert(ShwounsVaultRegistry.AlreadyLocked.selector);
        registry.setDAOLogic(address(0xdead));
    }
}
