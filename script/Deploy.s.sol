// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { Bootstrap } from "../src/governance/Bootstrap.sol";
import { IShwounsArt } from "../src/interfaces/IShwounsArt.sol";
import { ISVGRenderer } from "../src/interfaces/ISVGRenderer.sol";
import { IShwounsDescriptorMinimal } from "../src/interfaces/IShwounsDescriptorMinimal.sol";

/// @title Deploy — thin broadcaster for the persistent Bootstrap coordinator
///
/// @notice H-02 fix: the old script used the EPHEMERAL script contract's `address(this)` as the
///         temporary Art descriptor and DAO admin, which Foundry rejects during `forge script
///         --broadcast`. This script instead deploys ONE persistent `Bootstrap` contract and
///         delegates the whole deployment + wiring to it (Bootstrap's `address(this)` is a
///         legitimate persistent address). A single `finalizeBootstrap()` then atomically hands all
///         ownership/admin to governance, kicks off the first auction, and revokes Bootstrap —
///         leaving no permanent EOA authority (A10/A10.5).
///
/// Run:
///   MAINNET: forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
///   then (mainnet only) copy Nouns art via CopyArtFromNouns.s.sol before unpausing if using a real
///   ShwounsArt with empty pages. See shwouns/CLAUDE.md for the runbook.
///
/// Configuration via env vars (see defaultConfig). The deployed Bootstrap exposes every address
/// (b.dao(), b.token(), ...) for verification.
contract Deploy is Script {
    function defaultConfig() public view returns (Bootstrap.Config memory c) {
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
        c.art = IShwounsArt(vm.envOr("ART_ADDRESS", address(0)));
        c.renderer = ISVGRenderer(vm.envOr("RENDERER_ADDRESS", address(0)));
        // preDeployedDescriptor stays zero for a real deploy (Bootstrap builds the art stack).
    }

    /// @notice Deploy the full system via Bootstrap (paused, all roles held by Bootstrap). Returns
    ///         the Bootstrap so the caller can read every deployed address.
    ///
    /// @dev Runbook (mainnet) — finalizeBootstrap is a SEPARATE step AFTER art is uploaded, because
    ///      it kicks off the first auction, and minting needs populated art (the seeder computes
    ///      `% traitCount`, which is zero on a fresh ShwounsArt):
    ///        1. forge script script/Deploy.s.sol --broadcast            (this: deploy only)
    ///        2. SHWOUNS_DESCRIPTOR=<b.descriptor()> forge script
    ///             script/CopyArtFromNouns.s.sol --broadcast             (populate art)
    ///        3. cast send <b.descriptor()> lockParts                    (lock art when final)
    ///        4. cast send <bootstrap> finalizeBootstrap                 (handoff + start auction #1)
    ///      The end-to-end deploy→finalize→operate path is verified in Deployment.t.sol with the
    ///      ERC-6551 registry etched (a fresh `forge script` lacks it).
    function run() external returns (Bootstrap b) {
        Bootstrap.Config memory cfg = defaultConfig();
        vm.startBroadcast();
        b = new Bootstrap();
        b.deploy(cfg);
        vm.stopBroadcast();
    }
}
