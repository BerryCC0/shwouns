// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ShwounsToken } from "../src/token/ShwounsToken.sol";
import { ShwounsSeeder } from "../src/token/ShwounsSeeder.sol";
import { ShwounsDescriptor } from "../src/token/ShwounsDescriptor.sol";
import { ShwounsArt } from "../src/token/ShwounsArt.sol";
import { Inflator } from "../src/token/Inflator.sol";
import { SVGRenderer } from "../src/token/SVGRenderer.sol";
import { IShwounsDescriptorMinimal } from "../src/interfaces/IShwounsDescriptorMinimal.sol";
import { IShwounsArt } from "../src/interfaces/IShwounsArt.sol";
import { ISVGRenderer } from "../src/interfaces/ISVGRenderer.sol";
import { IInflator } from "../src/interfaces/IInflator.sol";

import { ShwounsVault } from "../src/vault/ShwounsVault.sol";
import { ShwounsVaultRegistry } from "../src/vault/ShwounsVaultRegistry.sol";

import { ShwounsAuctionHouse } from "../src/auction/ShwounsAuctionHouse.sol";
import { IShwounsToken } from "../src/interfaces/IShwounsToken.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/IChainalysisSanctionsList.sol";

import { GovernanceRewards } from "../src/rewards/GovernanceRewards.sol";
import { GovernanceIncentivesNFT } from "../src/rewards/GovernanceIncentivesNFT.sol";
import { ApprovalRegistry } from "../src/rewards/ApprovalRegistry.sol";

import { ShwounsDAOLogic } from "../src/governance/ShwounsDAOLogic.sol";
import { ShwounsDAOTypes, IShwounsTokenLike } from "../src/governance/ShwounsDAOInterfaces.sol";
import { ShwounsDAOData } from "../src/governance/data/ShwounsDAOData.sol";
import { ProposalEscrow } from "../src/governance/ProposalEscrow.sol";

/// @title Deploy — full Shwouns protocol deployment script
///
/// @notice Deploys all 11 production contracts and handles the cross-wiring. The deployment
///         order navigates the circular dependencies between Token / VaultRegistry / Vault impl
///         and between DAOLogic / GovernanceRewards / ApprovalRegistry via one-time setters
///         that lock on first use.
///
/// Run:
///   ANVIL:   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
///   SEPOLIA: forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
///   MAINNET: forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
///
/// Configuration (via env vars; defaults shown):
///   FOUNDERS_DAO          — recipient of every 10th Shwoun (default: tx.origin)
///   WETH_ADDRESS          — WETH9 address (default: mainnet)
///   AUCTION_DURATION_SEC  — daily auction = 86400 (default)
///   RESERVE_PRICE_WEI     — minimum bid (default 0.01 ETH)
///   TIME_BUFFER_SEC       — last-minute bid auction extension (default 300)
///   MIN_BID_INCREMENT_PCT — bid increment vs previous (default 2)
///   VOTING_DELAY_BLOCKS   — delay before voting starts (default 7200 ≈ 1 day at 12s blocks)
///   VOTING_PERIOD_BLOCKS  — voting period (default 36000 ≈ 5 days)
///   PROPOSAL_THRESHOLD_BPS — % of supply needed to propose (default 25 = 0.25%)
///   QUORUM_VOTES_BPS      — % of supply needed for For-majority (default 1000 = 10%)
///   GI_MINT_PRICE_WEI     — GovernanceIncentives NFT mint price (default 0.01 ETH)
///   PROPOSAL_REWARD_WEI   — per-proposal voter reward pool (default 0.1 ETH)
///   MAX_REFUND_PER_VOTE_WEI — gas refund cap per vote (default 0.003 ETH)
///   LAST_MINUTE_WINDOW_BLOCKS — objection trigger window (default 1200 ≈ 4h)
///   OBJECTION_PERIOD_BLOCKS — objection duration (default 7200 ≈ 1 day)
///
/// @dev `ShwounsArt` deployment is NOT in this script — we shipped the Descriptor + Seeder
///      but did not build a `ShwounsArt` storage contract this session. Mainnet deployment
///      requires an art contract; this script can be wired up to a deployed art address by
///      passing one via `ART_ADDRESS`. For testing/development, callers should deploy
///      a mock art and pass its address.

contract Deploy is Script {
    struct Config {
        address foundersDAO;
        address weth;
        uint256 auctionDuration;
        uint192 reservePrice;
        uint56 timeBuffer;
        uint8 minBidIncrementPct;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThresholdBPS;
        uint256 proposalUpdatablePeriodInBlocks;
        uint256 proposalQueuePeriodInBlocks;
        uint256 quorumVotesBPS;
        uint256 giMintPrice;
        uint256 proposalReward;
        uint256 maxRefundPerVote;
        uint32 lastMinuteWindowBlocks;
        uint32 objectionPeriodBlocks;
        IShwounsArt art; // optional; if address(0), Descriptor is deployed without art
        ISVGRenderer renderer; // optional; same caveat
        /// @notice Optionally pass a pre-built descriptor. Used in tests where we want
        ///         a MockDescriptor instead of building a real ShwounsDescriptor with art=0
        ///         (which would revert on tokenURI lookups during auction settlement).
        IShwounsDescriptorMinimal preDeployedDescriptor;
        /// @notice The address that ends up as DAO admin AND owner of all Ownable contracts
        ///         before transferOwnershipToDAO is called. _deploy uses address(this) as
        ///         the temporary admin so internal setX calls work, then setPendingAdmin
        ///         to this target. Target must call dao.acceptAdmin() to finalize.
        address adminTarget;
    }

    /// @notice The deployed contract addresses, returned to the caller for verification.
    struct Deployment {
        ShwounsToken token;
        ShwounsSeeder seeder;
        ShwounsDescriptor descriptor;
        ShwounsArt art;                           // address(0) if a pre-deployed descriptor was used
        Inflator inflator;                         // address(0) if a pre-deployed art/inflator was used
        SVGRenderer renderer;                      // address(0) if a pre-deployed renderer was used
        ShwounsVaultRegistry vaultRegistry;
        ShwounsVault vaultImpl;
        ShwounsAuctionHouse auctionHouse;          // proxy address
        ShwounsAuctionHouse auctionHouseImpl;
        ShwounsDAOLogic dao;                       // proxy address
        ShwounsDAOLogic daoImpl;
        ProposalEscrow proposalEscrowImpl;         // per-proposal escrow clone source
        GovernanceRewards rewards;
        GovernanceIncentivesNFT giNFT;
        ApprovalRegistry approvalRegistry;
        ShwounsDAOData daoData;
    }

    function defaultConfig() public view returns (Config memory c) {
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
        c.adminTarget = vm.envOr("ADMIN_TARGET", tx.origin);
        // preDeployedDescriptor stays at zero address by default (real deploy builds ShwounsDescriptor)
    }

    function run() external returns (Deployment memory) {
        Config memory cfg = defaultConfig();
        vm.startBroadcast();
        Deployment memory d = _deploy(cfg);
        vm.stopBroadcast();
        return d;
    }

    /// @notice Internal deploy used by both `run()` and tests. Tests call this directly
    ///         without broadcasting.
    function _deploy(Config memory cfg) public returns (Deployment memory d) {
        // ─────── 1. Art layer ───────
        // Three resolution paths for the descriptor (the thing token.descriptor() points to):
        //   (a) cfg.preDeployedDescriptor is set → use it. Skip everything else (used by tests
        //       that wire a MockDescriptor).
        //   (b) cfg.art + cfg.renderer are BOTH non-zero → use them as pre-deployed dependencies,
        //       deploy a new Descriptor pointing to them.
        //   (c) Otherwise → deploy the full art stack: Inflator + SVGRenderer + ShwounsArt +
        //       ShwounsDescriptor, wired together. This is the production path.
        d.seeder = new ShwounsSeeder();
        IShwounsDescriptorMinimal descriptorForToken;
        if (address(cfg.preDeployedDescriptor) != address(0)) {
            descriptorForToken = cfg.preDeployedDescriptor;
            // All art-related fields stay at address(0); caller doesn't need them.
        } else {
            IShwounsArt artForDescriptor = cfg.art;
            ISVGRenderer rendererForDescriptor = cfg.renderer;

            if (address(rendererForDescriptor) == address(0)) {
                d.renderer = new SVGRenderer();
                rendererForDescriptor = ISVGRenderer(address(d.renderer));
            }
            if (address(artForDescriptor) == address(0)) {
                d.inflator = new Inflator();
                // Temporary descriptor = address(this) so Art.onlyDescriptor lets US populate it
                // after the real descriptor is deployed via the setDescriptor handoff below.
                d.art = new ShwounsArt(address(this), IInflator(address(d.inflator)));
                artForDescriptor = IShwounsArt(address(d.art));
            }

            d.descriptor = new ShwounsDescriptor(artForDescriptor, rendererForDescriptor);
            descriptorForToken = IShwounsDescriptorMinimal(address(d.descriptor));

            // If we deployed Art ourselves, hand off control to the real descriptor.
            // From this point, Art's onlyDescriptor gate accepts the descriptor, not us.
            if (address(d.art) != address(0)) {
                d.art.setDescriptor(address(d.descriptor));
            }
        }

        // ─────── 2. Token (minter set to deployer temporarily; updated to auction house below) ───────
        d.token = new ShwounsToken(
            cfg.foundersDAO,
            msg.sender, // temporary minter; replaced by auction house after wiring
            descriptorForToken,
            d.seeder
        );

        // ─────── 3. Vault layer (registry needs token; impl needs registry; lock impl) ───────
        d.vaultRegistry = new ShwounsVaultRegistry(address(d.token));
        d.vaultImpl = new ShwounsVault(address(d.vaultRegistry));
        d.vaultRegistry.setVaultImplementation(address(d.vaultImpl)); // locks

        // ─────── 4. Rewards + GI NFT + ApprovalRegistry ───────
        d.rewards = new GovernanceRewards();
        d.giNFT = new GovernanceIncentivesNFT(cfg.giMintPrice);
        d.approvalRegistry = new ApprovalRegistry(IERC721(address(d.giNFT)));

        // GI NFT mint proceeds forward to GovernanceRewards
        d.giNFT.transferOwnership(address(d.rewards));

        // Configure reward amounts
        d.rewards.setProposalRewardAmount(cfg.proposalReward);
        d.rewards.setMaxRefundPerVote(cfg.maxRefundPerVote);
        d.rewards.setApprovalRegistry(d.approvalRegistry); // locks

        // ─────── 5. Auction House (UUPS proxy) ───────
        d.auctionHouseImpl = new ShwounsAuctionHouse(
            IShwounsToken(address(d.token)),
            cfg.weth,
            cfg.auctionDuration
        );
        bytes memory ahInit = abi.encodeWithSelector(
            ShwounsAuctionHouse.initialize.selector,
            cfg.reservePrice,
            cfg.timeBuffer,
            cfg.minBidIncrementPct,
            IChainalysisSanctionsList(address(0))
        );
        d.auctionHouse = ShwounsAuctionHouse(
            payable(address(new ERC1967Proxy(address(d.auctionHouseImpl), ahInit)))
        );
        d.auctionHouse.setGovernanceRewards(address(d.rewards));
        d.auctionHouse.setVaultRegistry(d.vaultRegistry);

        // Wire token's minter to the auction house (now that AH exists)
        d.token.setMinter(address(d.auctionHouse));

        // ─────── 6. DAO Logic (UUPS proxy) ───────
        d.daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory daoParams = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: cfg.votingPeriod,
            votingDelay: cfg.votingDelay,
            proposalThresholdBPS: cfg.proposalThresholdBPS,
            proposalUpdatablePeriodInBlocks: cfg.proposalUpdatablePeriodInBlocks,
            proposalQueuePeriodInBlocks: cfg.proposalQueuePeriodInBlocks
        });
        // Seed dynamic quorum: min = configured quorum BPS (legacy fixed-quorum fallback tracks
        // the min), max = 6000, coefficient = 0. The min must be in [200, 2000].
        ShwounsDAOTypes.DynamicQuorumParams memory daoQuorum = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: uint16(cfg.quorumVotesBPS),
            maxQuorumVotesBPS: 6000,
            quorumCoefficient: 0
        });
        // Initialize DAO with THIS Deploy contract as admin so subsequent setX calls work.
        // We hand off admin to cfg.adminTarget at the end of _deploy via setPendingAdmin.
        bytes memory daoInit = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this), // admin (temporary; hands off below)
            address(0), // vetoer
            IShwounsTokenLike(address(d.token)),
            d.vaultRegistry,
            daoParams,
            daoQuorum
        );
        d.dao = ShwounsDAOLogic(
            payable(address(new ERC1967Proxy(address(d.daoImpl), daoInit)))
        );

        // Configure objection period parameters
        if (cfg.lastMinuteWindowBlocks > 0) {
            d.dao.setLastMinuteWindowInBlocks(cfg.lastMinuteWindowBlocks);
        }
        if (cfg.objectionPeriodBlocks > 0) {
            d.dao.setObjectionPeriodDurationInBlocks(cfg.objectionPeriodBlocks);
        }

        // ─────── 7. Cross-wire DAO ↔ Vault Registry, DAO ↔ GovernanceRewards ───────
        d.vaultRegistry.setDAOLogic(address(d.dao)); // locks vault.pullProRata gate
        d.dao.setGovernanceRewards(address(d.rewards));
        d.rewards.setDAOLogic(address(d.dao)); // locks

        // Per-proposal escrow implementation (the EIP-1167 clone source). Deployed AFTER DAOLogic so
        // its immutable daoLogic = the DAO proxy address; residualSink = GovernanceRewards. Then
        // registered + locked on the DAO (admin is this Deploy contract here). Phase 6 folds this
        // into the Bootstrap coordinator.
        d.proposalEscrowImpl = new ProposalEscrow(address(d.dao), address(d.rewards));
        d.dao.setProposalEscrowImplementation(address(d.proposalEscrowImpl));

        // ─────── 8. Candidates (standalone, no wiring needed) ───────
        d.daoData = new ShwounsDAOData();

        // ─────── 9. Hand off DAO admin to the configured target ───────
        // Target must call dao.acceptAdmin() to finalize the transfer. Until then,
        // address(this) (Deploy contract) remains admin — which is fine because
        // Deploy is an ephemeral deployment helper.
        if (cfg.adminTarget != address(0) && cfg.adminTarget != address(this)) {
            d.dao.setPendingAdmin(cfg.adminTarget);
        }

        // Ownership transfers + auction kickoff are extracted to separate functions
        // so tests can deploy without sealing themselves out of administrative control.
        return d;
    }

    /// @notice Transfer ownership of all DAO-controlled contracts to the DAO. Call this
    ///         AFTER initial setup is verified. Once called, parameter changes require
    ///         governance proposals. Idempotent per-contract — fine to call multiple
    ///         times on partially-transferred deployments (the per-contract check is
    ///         "is current owner the caller").
    function transferOwnershipToDAO(Deployment memory d) external {
        // GovernanceRewards: DAO can sweep ETH/tokens via proposal
        d.rewards.transferOwnership(address(d.dao));
        // ApprovalRegistry: DAO controls the allowlist via proposal
        d.approvalRegistry.transferOwnership(address(d.dao));
        // AuctionHouse: DAO can upgrade it via UUPS and adjust knobs
        d.auctionHouse.transferOwnership(address(d.dao));
        // Token: DAO controls minter/descriptor/seeder updates + lock states
        d.token.transferOwnership(address(d.dao));
        // Descriptor: DAO controls art updates + lock states (skip if we used a
        // preDeployedDescriptor — that contract isn't owned by Deploy)
        if (address(d.descriptor) != address(0)) {
            d.descriptor.transferOwnership(address(d.dao));
        }
        // NOTE: DAOLogic admin is NOT transferred to itself by default — that would lock
        //   parameter changes behind a full proposal cycle from day one. Operators can
        //   transfer admin to the DAO once initial setup is stable via setPendingAdmin.
    }

    /// @notice Kick off the first auction. AuctionHouse is paused in initialize();
    ///         call this BEFORE transferOwnershipToDAO if you want a single-tx kickoff.
    ///         After ownership transfer, unpause requires a DAO proposal.
    function startFirstAuction(Deployment memory d) external {
        d.auctionHouse.unpause();
    }

    /// @notice Convenience: do everything in one tx. Wraps _deploy + startFirstAuction
    ///         + transferOwnershipToDAO. Use this for prod mainnet deploys.
    function deployAndStart(Config memory cfg) external returns (Deployment memory d) {
        d = _deploy(cfg);
        d.auctionHouse.unpause();
        this.transferOwnershipToDAO(d);
    }
}
