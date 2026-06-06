// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ShwounsToken} from "../../src/token/ShwounsToken.sol";
import {ShwounsSeeder} from "../../src/token/ShwounsSeeder.sol";
import {ShwounsVault} from "../../src/vault/ShwounsVault.sol";
import {ShwounsVaultRegistry} from "../../src/vault/ShwounsVaultRegistry.sol";
import {ShwounsDAOLogic} from "../../src/governance/ShwounsDAOLogic.sol";
import {ShwounsDAOProposals} from "../../src/governance/ShwounsDAOProposals.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";

/// @title Vote-by-signature (EIP-712 Ballot) tests — Workstream D.
contract VoteBySigTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsDAOLogic dao;

    address foundersDAO = makeAddr("foundersDAO");
    address voter;
    uint256 voterPk;
    address other;

    function setUp() public {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);

        ShwounsSeeder seeder = new ShwounsSeeder();
        MockDescriptor desc = new MockDescriptor();
        token = new ShwounsToken(foundersDAO, address(this), desc, seeder, address(0));
        registry = new ShwounsVaultRegistry(address(token), address(0));
        ShwounsVault vaultImpl = new ShwounsVault(address(registry));
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

        (voter, voterPk) = makeAddrAndKey("voter");
        other = makeAddr("other");
        uint256 id1 = token.mint(); token.transferFrom(address(this), voter, id1); // founder 0 + auction 1
        uint256 id2 = token.mint(); token.transferFrom(address(this), other, id2); // auction 2
        vm.prank(voter); token.delegate(voter);
        vm.prank(other); token.delegate(other);
        vm.roll(block.number + 1);
    }

    function _ballotDigest(uint256 proposalId, uint8 support) internal view returns (bytes32) {
        bytes32 domainSep =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("ShwounsDAO"), block.chainid, address(dao)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }

    function _proposeAndActivate() internal returns (uint256 pid) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory sigs = new string[](1);
        bytes[] memory cd = new bytes[](1);
        targets[0] = makeAddr("recip");
        vm.prank(voter);
        pid = dao.propose(targets, values, sigs, cd, "vote-by-sig");
        vm.roll(block.number + 2); // past votingDelay → Active
    }

    function test_castVoteBySig_registersForVote() public {
        uint256 pid = _proposeAndActivate();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPk, _ballotDigest(pid, 1));
        dao.castVoteBySig(pid, 1, v, r, s);

        ShwounsDAOTypes.Receipt memory receipt = dao.getReceipt(pid, voter);
        assertTrue(receipt.hasVoted, "voter recorded");
        assertEq(receipt.support, 1, "support For");
        assertEq(receipt.votes, 1, "1 vote");
    }

    function test_castVoteBySig_against_recordsAgainst() public {
        uint256 pid = _proposeAndActivate();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPk, _ballotDigest(pid, 0));
        dao.castVoteBySig(pid, 0, v, r, s);
        assertEq(dao.getReceipt(pid, voter).support, 0, "support Against honored");
    }

    function test_castVoteBySig_doubleVote_reverts() public {
        uint256 pid = _proposeAndActivate();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voterPk, _ballotDigest(pid, 1));
        dao.castVoteBySig(pid, 1, v, r, s);
        vm.expectRevert(ShwounsDAOProposals.CannotVoteTwice.selector);
        dao.castVoteBySig(pid, 1, v, r, s);
    }
}
