// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { Bootstrap } from "../src/governance/Bootstrap.sol";
import { ShwounsDeployer } from "./ShwounsDeployer.sol";
import { ShwounsToken } from "../src/token/ShwounsToken.sol";
import { ShwounsDAOLogic } from "../src/governance/ShwounsDAOLogic.sol";
import { ShwounsAuctionHouse } from "../src/auction/ShwounsAuctionHouse.sol";
import { ShwounsVaultRegistry } from "../src/vault/ShwounsVaultRegistry.sol";
import { GovernanceAuthRegistry } from "../src/governance/GovernanceAuthRegistry.sol";

/// @title RehearseDeploy — full end-to-end deploy rehearsal for a real broadcast (audit plan-review F4)
///
/// @notice `forge script` (simulation) alone passed last round yet the system was undeployable, so
///         this runs the WHOLE runbook in ONE broadcast — deploy → load minimal art → lockParts →
///         finalizeBootstrap — exercising CREATE2, library link-patching, the operator gate, and the
///         atomic handoff as real transactions with receipts. Drive it against a local anvil that has
///         the canonical ERC-6551 registry etched (see rehearse-deploy.sh). Loads MINIMAL placeholder
///         art (trait counts come from the explicit imageCount, not the bytes) so the genesis mint
///         works; mainnet uses CopyArtFromNouns instead. NOT for mainnet.
contract RehearseDeploy is Script {
    function _config() internal view returns (ShwounsDeployer.Config memory c) {
        c.foundersDAO = vm.envOr("FOUNDERS_DAO", tx.origin);
        c.weth = vm.envOr("WETH_ADDRESS", address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        c.auctionDuration = 86400;
        c.reservePrice = 0.01 ether;
        c.timeBuffer = 300;
        c.minBidIncrementPct = 2;
        c.votingDelay = 7200;
        c.votingPeriod = 7200;
        c.proposalThresholdBPS = 25;
        c.proposalUpdatablePeriodInBlocks = 0;
        c.proposalQueuePeriodInBlocks = 50400;
        c.quorumVotesBPS = 1000;
        c.giMintPrice = 0.01 ether;
        c.proposalReward = 0.1 ether;
        c.maxRefundPerVote = 0.003 ether;
        c.lastMinuteWindowBlocks = 1200;
        c.objectionPeriodBlocks = 7200;
    }

    function run() external returns (Bootstrap b, Bootstrap.DeploymentManifest memory m) {
        ShwounsDeployer.Config memory cfg = _config();
        vm.startBroadcast();

        b = new Bootstrap();
        m = ShwounsDeployer.deployAll(b, cfg);

        // Load minimal placeholder art + lock, then finalize (unpauses → genesis mint).
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

        b.finalizeBootstrap();

        vm.stopBroadcast();

        // Post-asserts (checked in simulation before the broadcast commits).
        require(ShwounsToken(m.token).owner() == m.dao, "token not handed to DAO");
        require(ShwounsVaultRegistry(m.vaultRegistry).owner() == m.dao, "registry not handed to DAO");
        require(ShwounsDAOLogic(payable(m.dao)).admin() == m.dao, "DAO admin not DAO");
        require(GovernanceAuthRegistry(m.authRegistry).daoLogic() == m.dao, "registry not bound");
        require(!ShwounsAuctionHouse(payable(m.auctionHouse)).paused(), "auction still paused");
        require(ShwounsAuctionHouse(payable(m.auctionHouse)).auction().shwounId == 1, "genesis auction not started");
    }
}
