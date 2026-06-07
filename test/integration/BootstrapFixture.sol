// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Bootstrap} from "../../src/governance/Bootstrap.sol";
import {ShwounsDeployer} from "../../script/ShwounsDeployer.sol";
import {ERC6551Registry} from "../mocks/ERC6551Registry.sol";
import {MockWETH} from "../mocks/MockWETH.sol";

/// @notice Shared deployment harness for the deployment-focused suites. Deploys the full system via
///         the SAME ShwounsDeployer path the broadcast script uses — the test contract is the
///         Bootstrap operator (it runs `new Bootstrap()` + the inlined library deploy calls), so the
///         on-chain operator-gated flow is exactly what these tests exercise (audit F1/F2/F3).
abstract contract BootstrapFixture is Test {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    Bootstrap b;
    Bootstrap.DeploymentManifest m;
    ShwounsDeployer.Config cfg;
    address foundersDAO = makeAddr("foundersDAO");

    /// @dev Etch the canonical ERC-6551 registry, then deploy + wire the whole system via Bootstrap
    ///      (pre-finalize: Bootstrap owns everything, auction paused, registry unbound).
    function _deploySystem() internal {
        ERC6551Registry tmp = new ERC6551Registry();
        vm.etch(CANONICAL_REGISTRY, address(tmp).code);
        MockWETH weth = new MockWETH();

        cfg = ShwounsDeployer.Config({
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
            objectionPeriodBlocks: 3
        });

        b = new Bootstrap();
        m = ShwounsDeployer.deployAll(b, cfg);
    }

    /// @dev Load MINIMAL art (1 of each trait) + lockParts through Bootstrap.executeBatch, so
    ///      finalize's `arePartsLocked` precheck passes and the genesis mint (seeder `% count`) works.
    ///      Trait counts come from the explicit imageCount arg (not the bytes), so placeholder bytes
    ///      suffice — the e2e flow never renders a tokenURI. Drives the descriptor through Bootstrap
    ///      (its owner), the production art-load path (audit F3).
    function _loadMinimalArtAndLock() internal {
        address d = m.descriptor;
        address[] memory targets = new address[](5);
        bytes[] memory datas = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) targets[i] = d;
        datas[0] = abi.encodeWithSignature("addBackground(string)", "ffffff");
        datas[1] = abi.encodeWithSignature("addBodies(bytes,uint80,uint16)", bytes(hex"00"), uint80(1), uint16(1));
        datas[2] = abi.encodeWithSignature("addAccessories(bytes,uint80,uint16)", bytes(hex"00"), uint80(1), uint16(1));
        datas[3] = abi.encodeWithSignature("addHeads(bytes,uint80,uint16)", bytes(hex"00"), uint80(1), uint16(1));
        datas[4] = abi.encodeWithSignature("lockParts()");
        b.executeBatch(targets, datas);
    }
}
