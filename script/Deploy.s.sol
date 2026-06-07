// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { Bootstrap } from "../src/governance/Bootstrap.sol";
import { ShwounsDeployer } from "./ShwounsDeployer.sol";

/// @title Deploy — broadcast wrapper around the shared ShwounsDeployer orchestration
///
/// @notice Deploys ONE persistent generic Bootstrap (its address is `msg.sender` in every
///         constructor → no permanent EOA owns roles, A10.1) and drives the full deployment through
///         it via ShwounsDeployer. Bootstrap and this script embed NO contract creation code (audit
///         F1/H-02): the bytecode is read from artifacts at runtime by ShwounsDeployer (`vm.getCode`
///         + library link-patching). The broadcaster EOA is the Bootstrap `operator`, so only it can
///         drive deploy/execute/finalize (audit F2 — no front-running).
///
/// @dev Runbook (finalizeBootstrap is a SEPARATE step AFTER art is uploaded + locked, because it
///      unpauses → mints, and minting needs populated art; see shwouns/CLAUDE.md):
///        1. forge script script/Deploy.s.sol --rpc-url $RPC --broadcast --verify   (deploy only)
///        2. SHWOUNS_BOOTSTRAP=<b> SHWOUNS_DESCRIPTOR=<descriptor>
///             forge script script/CopyArtFromNouns.s.sol --broadcast               (load art via execute)
///        3. (operator) bootstrap.execute(descriptor, lockParts())                  (lock art when final)
///        4. (operator) bootstrap.finalizeBootstrap()                               (atomic handoff)
///      The end-to-end deploy→art→finalize→operate path is verified in Deployment.t.sol with the
///      ERC-6551 registry etched (a fresh `forge script` lacks it).
contract Deploy is Script {
    function defaultConfig() public view returns (ShwounsDeployer.Config memory c) {
        c.foundersDAO = vm.envOr("FOUNDERS_DAO", tx.origin);
        c.weth = vm.envOr("WETH_ADDRESS", address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
        c.auctionDuration = vm.envOr("AUCTION_DURATION_SEC", uint256(86400));
        c.reservePrice = uint192(vm.envOr("RESERVE_PRICE_WEI", uint256(0.01 ether)));
        c.timeBuffer = uint56(vm.envOr("TIME_BUFFER_SEC", uint256(300)));
        c.minBidIncrementPct = uint8(vm.envOr("MIN_BID_INCREMENT_PCT", uint256(2)));
        c.votingDelay = vm.envOr("VOTING_DELAY_BLOCKS", uint256(7200));
        c.votingPeriod = vm.envOr("VOTING_PERIOD_BLOCKS", uint256(36000));
        c.proposalThresholdBPS = vm.envOr("PROPOSAL_THRESHOLD_BPS", uint256(25));
        c.proposalUpdatablePeriodInBlocks = vm.envOr("PROPOSAL_UPDATABLE_PERIOD_BLOCKS", uint256(0));
        c.proposalQueuePeriodInBlocks = vm.envOr("PROPOSAL_QUEUE_PERIOD_BLOCKS", uint256(50400));
        c.quorumVotesBPS = vm.envOr("QUORUM_VOTES_BPS", uint256(1000));
        c.giMintPrice = vm.envOr("GI_MINT_PRICE_WEI", uint256(0.01 ether));
        c.proposalReward = vm.envOr("PROPOSAL_REWARD_WEI", uint256(0.1 ether));
        c.maxRefundPerVote = vm.envOr("MAX_REFUND_PER_VOTE_WEI", uint256(0.003 ether));
        c.lastMinuteWindowBlocks = uint32(vm.envOr("LAST_MINUTE_WINDOW_BLOCKS", uint256(1200)));
        c.objectionPeriodBlocks = uint32(vm.envOr("OBJECTION_PERIOD_BLOCKS", uint256(7200)));
    }

    /// @notice Deploy + wire the full system via Bootstrap (deploy-only; paused, all roles with
    ///         Bootstrap). Returns the Bootstrap and the manifest of deployed addresses.
    function run() external returns (Bootstrap b, Bootstrap.DeploymentManifest memory m) {
        ShwounsDeployer.Config memory cfg = defaultConfig();
        vm.startBroadcast();
        b = new Bootstrap();
        m = ShwounsDeployer.deployAll(b, cfg);
        vm.stopBroadcast();
    }
}
