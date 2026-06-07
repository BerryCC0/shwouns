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
import {ShwounsDAOSignatures} from "../../src/governance/ShwounsDAOSignatures.sol";
import {ShwounsDAOTypes, IShwounsTokenLike} from "../../src/governance/ShwounsDAOInterfaces.sol";
import {ProposalEscrow} from "../../src/governance/ProposalEscrow.sol";

import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockDescriptor} from "../mocks/MockDescriptor.sol";

/// @title Proposal editing (Updatable window) + Expired — Workstream E.
contract ProposalEditingTest is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;
    uint256 constant UPDATABLE = 10; // updatable window length (blocks)
    uint256 constant VOTING_PERIOD = 7200;
    uint256 constant QUEUE_PERIOD = 50400;

    ShwounsToken token;
    ShwounsVaultRegistry registry;
    ShwounsDAOLogic dao;

    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 constant UPDATE_PROPOSAL_TYPEHASH = keccak256(
        "UpdateProposal(uint256 proposalId,address proposer,address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description,uint256 expiry)"
    );

    address foundersDAO = makeAddr("foundersDAO");
    address proposer;
    address other = makeAddr("other");
    address sigA; uint256 sigAPk;
    address sigB; uint256 sigBPk;

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
            votingPeriod: VOTING_PERIOD,
            votingDelay: 1,
            proposalThresholdBPS: 1, // rounds to 0 at this supply → 1-vote proposer can propose
            proposalUpdatablePeriodInBlocks: UPDATABLE,
            proposalQueuePeriodInBlocks: QUEUE_PERIOD
        });
        ShwounsDAOTypes.DynamicQuorumParams memory dq = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: 200, maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        dao = ShwounsDAOLogic(payable(address(new ERC1967Proxy(address(daoImpl),
            abi.encodeWithSelector(ShwounsDAOLogic.initialize.selector,
                address(this), address(0), IShwounsTokenLike(address(token)), registry, params, dq)))));
        registry.setDAOLogic(address(dao));

        // Per-proposal escrow implementation (clone source).
        ProposalEscrow escrowImpl = new ProposalEscrow(address(dao), address(0xBEEF));
        dao.setProposalEscrowImplementation(address(escrowImpl));

        proposer = makeAddr("proposer");
        (sigA, sigAPk) = makeAddrAndKey("sigA");
        (sigB, sigBPk) = makeAddrAndKey("sigB");
        uint256 id1 = token.mint(); token.transferFrom(address(this), proposer, id1); // founder 0 + auction 1
        uint256 id2 = token.mint(); token.transferFrom(address(this), other, id2);
        uint256 id3 = token.mint(); token.transferFrom(address(this), sigA, id3);
        uint256 id4 = token.mint(); token.transferFrom(address(this), sigB, id4);
        vm.prank(proposer); token.delegate(proposer);
        vm.prank(other); token.delegate(other);
        vm.prank(sigA); token.delegate(sigA);
        vm.prank(sigB); token.delegate(sigB);
        vm.roll(block.number + 1);
    }

    // --- EIP-712 digest helpers (mirror the library) ---
    function _domainSep() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("ShwounsDAO"), block.chainid, address(dao)));
    }
    function _encodeData(address proposer_, address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c, string memory d)
        internal pure returns (bytes memory)
    {
        bytes32[] memory sh = new bytes32[](s.length);
        for (uint256 i; i < s.length; i++) sh[i] = keccak256(bytes(s[i]));
        bytes32[] memory ch = new bytes32[](c.length);
        for (uint256 i; i < c.length; i++) ch[i] = keccak256(c[i]);
        return abi.encode(proposer_, keccak256(abi.encodePacked(t)), keccak256(abi.encodePacked(v)),
            keccak256(abi.encodePacked(sh)), keccak256(abi.encodePacked(ch)), keccak256(bytes(d)));
    }
    function _proposeSig(uint256 pk, address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c, string memory d, uint256 expiry)
        internal view returns (bytes memory)
    {
        bytes32 digest = dao.proposalDigest(proposer, t, v, s, c, d, expiry);
        (uint8 vv, bytes32 r, bytes32 ss) = vm.sign(pk, digest);
        return abi.encodePacked(r, ss, vv);
    }
    function _updateSig(uint256 pk, uint256 pid, address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c, string memory d, uint256 expiry)
        internal view returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSep(), keccak256(abi.encodePacked(
            UPDATE_PROPOSAL_TYPEHASH, abi.encodePacked(pid, _encodeData(proposer, t, v, s, c, d)), expiry))));
        (uint8 vv, bytes32 r, bytes32 ss) = vm.sign(pk, digest);
        return abi.encodePacked(r, ss, vv);
    }

    function _createCoSigned(address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c)
        internal returns (uint256 pid)
    {
        uint256 expiry = block.timestamp + 1 days;
        ShwounsDAOTypes.ProposerSignature[] memory ps = new ShwounsDAOTypes.ProposerSignature[](2);
        ps[0] = ShwounsDAOTypes.ProposerSignature({ sig: _proposeSig(sigAPk, t, v, s, c, "original", expiry), signer: sigA, expirationTimestamp: expiry });
        ps[1] = ShwounsDAOTypes.ProposerSignature({ sig: _proposeSig(sigBPk, t, v, s, c, "original", expiry), signer: sigB, expirationTimestamp: expiry });
        vm.prank(proposer);
        pid = dao.proposeBySigs(ps, t, v, s, c, "original");
    }

    function _editCoSigned(uint256 pid, address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) internal {
        uint256 expiry = block.timestamp + 1 days;
        ShwounsDAOTypes.ProposerSignature[] memory ps = new ShwounsDAOTypes.ProposerSignature[](2);
        ps[0] = ShwounsDAOTypes.ProposerSignature({ sig: _updateSig(sigAPk, pid, t, v, s, c, "edited", expiry), signer: sigA, expirationTimestamp: expiry });
        ps[1] = ShwounsDAOTypes.ProposerSignature({ sig: _updateSig(sigBPk, pid, t, v, s, c, "edited", expiry), signer: sigB, expirationTimestamp: expiry });
        vm.prank(proposer);
        dao.updateProposalBySigs(pid, ps, t, v, s, c, "edited", "co-signed edit");
    }

    function _oneAction(address target, uint256 value) internal pure
        returns (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c)
    {
        t = new address[](1); v = new uint256[](1); s = new string[](1); c = new bytes[](1);
        t[0] = target; v[0] = value;
    }

    function _propose() internal returns (uint256 pid) {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) =
            _oneAction(makeAddr("recipA"), 0);
        vm.prank(proposer);
        pid = dao.propose(t, v, s, c, "original");
    }

    function _state(uint256 pid) internal view returns (ShwounsDAOTypes.ProposalState) {
        return dao.state(pid);
    }

    function test_lifecycle_updatableThenPendingThenActive() public {
        uint256 created = block.number;
        uint256 pid = _propose();
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Updatable), "Updatable at creation");

        vm.roll(created + UPDATABLE); // last block of the update window
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Updatable), "still Updatable");

        vm.roll(created + UPDATABLE + 1); // startBlock = updatePeriodEnd + votingDelay(1)
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Pending), "Pending");

        vm.roll(created + UPDATABLE + 2);
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Active), "Active after update window + delay");
    }

    function test_updateProposal_editsActionsDuringWindow() public {
        uint256 pid = _propose();
        address newRecip = makeAddr("recipB");
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _oneAction(newRecip, 5 ether);

        vm.prank(proposer);
        dao.updateProposal(pid, t, v, s, c, "edited", "fixing recipient");

        (address[] memory gt, uint256[] memory gv,,) = dao.getActions(pid);
        assertEq(gt[0], newRecip, "target updated");
        assertEq(gv[0], 5 ether, "value updated");
    }

    function test_updateProposal_afterWindow_reverts() public {
        uint256 created = block.number;
        uint256 pid = _propose();
        vm.roll(created + UPDATABLE + 1); // now Pending — window closed
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _oneAction(makeAddr("x"), 0);
        vm.prank(proposer);
        vm.expectRevert(ShwounsDAOSignatures.CanOnlyEditUpdatableProposals.selector);
        dao.updateProposal(pid, t, v, s, c, "late", "too late");
    }

    function test_updateProposal_byNonProposer_reverts() public {
        uint256 pid = _propose();
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _oneAction(makeAddr("x"), 0);
        vm.prank(other);
        vm.expectRevert(ShwounsDAOSignatures.OnlyProposerCanEdit.selector);
        dao.updateProposal(pid, t, v, s, c, "hijack", "not mine");
    }

    function test_expired_ifNotQueuedBeforeDeadline() public {
        uint256 created = block.number;
        uint256 pid = _propose();
        vm.roll(created + UPDATABLE + 2); // Active
        vm.prank(proposer); dao.castVote(pid, 1);
        vm.roll(block.number + VOTING_PERIOD + 1); // voting ends → Succeeded
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Succeeded), "Succeeded");

        // Roll past the queue deadline (endBlock + QUEUE_PERIOD) without queueing.
        vm.roll(block.number + QUEUE_PERIOD + 1);
        assertEq(uint256(_state(pid)), uint256(ShwounsDAOTypes.ProposalState.Expired), "Expired");

        vm.expectRevert(ShwounsDAOProposals.InvalidProposalState.selector);
        dao.queue(pid);
    }

    // -- F: bulk getter + computed threshold --

    function test_proposalsGetter_returnsCondensedView() public {
        uint256 pid = _propose();
        ShwounsDAOTypes.ProposalCondensed memory c = dao.proposals(pid);
        assertEq(c.id, pid, "id");
        assertEq(c.proposer, proposer, "proposer");
        assertEq(uint256(c.state), uint256(ShwounsDAOTypes.ProposalState.Updatable), "state Updatable");
        assertEq(c.signers.length, 0, "no signers (normal propose)");
        assertEq(c.updatePeriodEndBlock, c.creationBlock + UPDATABLE, "update window end");
    }

    function test_proposalThreshold_isComputedFromSupply() public {
        // proposalThresholdBPS = 1, small supply → rounds to 0 absolute votes.
        assertEq(dao.proposalThreshold(), (token.totalSupply() * 1) / 10000);
    }

    // -- E: updateProposalBySigs (co-signed proposal editing) --

    function test_updateProposalBySigs_editsCoSignedProposal() public {
        (address[] memory t, uint256[] memory v, string[] memory s, bytes[] memory c) = _oneAction(makeAddr("r1"), 0);
        uint256 pid = _createCoSigned(t, v, s, c);
        assertEq(dao.proposalSigners(pid).length, 2, "two signers");

        // Edit within the updatable window — all signers re-sign the UPDATE digest, same order.
        address newRecip = makeAddr("r2");
        (address[] memory nt, uint256[] memory nv, string[] memory ns, bytes[] memory nc) = _oneAction(newRecip, 9 ether);
        _editCoSigned(pid, nt, nv, ns, nc);

        (address[] memory gt, uint256[] memory gv,,) = dao.getActions(pid);
        assertEq(gt[0], newRecip, "co-signed target updated");
        assertEq(gv[0], 9 ether, "co-signed value updated");
    }
}
