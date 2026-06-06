// SPDX-License-Identifier: GPL-3.0

/// @title Bootstrap — persistent deployment coordinator + one-shot trust handoff (A10, H-02)
///
/// @notice The ephemeral Foundry script can't be a transient owner/admin/art-descriptor — Foundry
///         rejects `address(this)` of an ephemeral script contract (H-02). Bootstrap is a REAL
///         deployed contract: it deploys the whole system with ITS OWN address as the transient
///         owner/admin/art-descriptor and as the auth-registry binder, then a single one-shot
///         `finalizeBootstrap()` atomically (a) binds the registry to the DAOLogic proxy, (b)
///         transfers every Ownable's ownership to the DAO, (c) sets DAOLogic's admin to the DAO
///         directly (the proxy can't self-accept the two-step), and (d) revokes itself. The auction
///         stays PAUSED until after the handoff. No permanent EOA holds any role (A10/A10.5).
///
/// @dev deploy() performs the full deployment in one call (Bootstrap = deployer = owner). For a
///      mainnet broadcast this is a single large tx; if it exceeds practical gas it can be split
///      along the layer boundaries below. The registry-first ordering (round-6 finding 3) lets every
///      governed contract take an immutable governanceAuth reference before the DAO proxy exists.
pragma solidity ^0.8.19;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ShwounsToken } from "../token/ShwounsToken.sol";
import { ShwounsSeeder } from "../token/ShwounsSeeder.sol";
import { ShwounsDescriptor } from "../token/ShwounsDescriptor.sol";
import { ShwounsArt } from "../token/ShwounsArt.sol";
import { Inflator } from "../token/Inflator.sol";
import { SVGRenderer } from "../token/SVGRenderer.sol";
import { IShwounsDescriptorMinimal } from "../interfaces/IShwounsDescriptorMinimal.sol";
import { IShwounsArt } from "../interfaces/IShwounsArt.sol";
import { ISVGRenderer } from "../interfaces/ISVGRenderer.sol";
import { IInflator } from "../interfaces/IInflator.sol";

import { ShwounsVault } from "../vault/ShwounsVault.sol";
import { ShwounsVaultRegistry } from "../vault/ShwounsVaultRegistry.sol";

import { ShwounsAuctionHouse } from "../auction/ShwounsAuctionHouse.sol";
import { IShwounsToken } from "../interfaces/IShwounsToken.sol";
import { IChainalysisSanctionsList } from "../interfaces/IChainalysisSanctionsList.sol";

import { GovernanceRewards } from "../rewards/GovernanceRewards.sol";
import { GovernanceIncentivesNFT } from "../rewards/GovernanceIncentivesNFT.sol";
import { ApprovalRegistry } from "../rewards/ApprovalRegistry.sol";

import { ShwounsDAOLogic } from "./ShwounsDAOLogic.sol";
import { ShwounsDAOTypes, IShwounsTokenLike } from "./ShwounsDAOInterfaces.sol";
import { ShwounsDAOData } from "./data/ShwounsDAOData.sol";
import { ProposalEscrow } from "./ProposalEscrow.sol";
import { GovernanceAuthRegistry } from "./GovernanceAuthRegistry.sol";

contract Bootstrap {
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
        IShwounsArt art;
        ISVGRenderer renderer;
        IShwounsDescriptorMinimal preDeployedDescriptor;
    }

    // Deployed addresses (set by deploy()).
    GovernanceAuthRegistry public authRegistry;
    ShwounsToken public token;
    ShwounsSeeder public seeder;
    ShwounsDescriptor public descriptor;
    ShwounsArt public art;
    Inflator public inflator;
    SVGRenderer public renderer;
    ShwounsVaultRegistry public vaultRegistry;
    ShwounsVault public vaultImpl;
    ShwounsAuctionHouse public auctionHouse; // proxy
    ShwounsAuctionHouse public auctionHouseImpl;
    ShwounsDAOLogic public dao; // proxy
    ShwounsDAOLogic public daoImpl;
    ProposalEscrow public proposalEscrowImpl;
    GovernanceRewards public rewards;
    GovernanceIncentivesNFT public giNFT;
    ApprovalRegistry public approvalRegistry;
    ShwounsDAOData public daoData;

    bool public deployed;
    bool public finalized;

    event Deployed(address dao, address authRegistry);
    event Finalized();

    error AlreadyDeployed();
    error NotDeployed();
    error AlreadyFinalized();

    /// @notice Deploy + wire the whole system, with Bootstrap as the transient owner/admin and the
    ///         auth-registry binder. The auction starts paused (AuctionHouse.initialize pauses it).
    function deploy(Config calldata cfg) external {
        if (deployed) revert AlreadyDeployed();
        deployed = true;

        // 0. Auth registry FIRST (binder = this Bootstrap). Bound to the DAO in finalizeBootstrap.
        authRegistry = new GovernanceAuthRegistry();
        address auth = address(authRegistry);

        // 1. Art layer (Bootstrap is the transient Art descriptor — a legitimate persistent address)
        seeder = new ShwounsSeeder();
        IShwounsDescriptorMinimal descriptorForToken;
        if (address(cfg.preDeployedDescriptor) != address(0)) {
            descriptorForToken = cfg.preDeployedDescriptor;
        } else {
            ISVGRenderer rendererForDescriptor = cfg.renderer;
            IShwounsArt artForDescriptor = cfg.art;
            if (address(rendererForDescriptor) == address(0)) {
                renderer = new SVGRenderer();
                rendererForDescriptor = ISVGRenderer(address(renderer));
            }
            if (address(artForDescriptor) == address(0)) {
                inflator = new Inflator();
                // Temp Art descriptor = this Bootstrap, so we can populate Art before handing the
                // descriptor over. (This is the H-02 fix: a persistent address, not the script.)
                art = new ShwounsArt(address(this), IInflator(address(inflator)));
                artForDescriptor = IShwounsArt(address(art));
            }
            descriptor = new ShwounsDescriptor(artForDescriptor, rendererForDescriptor, auth);
            descriptorForToken = IShwounsDescriptorMinimal(address(descriptor));
            if (address(art) != address(0)) {
                art.setDescriptor(address(descriptor));
            }
        }

        // 2. Token (minter = Bootstrap temporarily; updated to the auction house below)
        token = new ShwounsToken(cfg.foundersDAO, address(this), descriptorForToken, seeder, auth);

        // 3. Vault layer
        vaultRegistry = new ShwounsVaultRegistry(address(token), auth);
        vaultImpl = new ShwounsVault(address(vaultRegistry));
        vaultRegistry.setVaultImplementation(address(vaultImpl)); // locks

        // 4. Rewards + GI NFT + ApprovalRegistry (A6: proceedsRecipient = GR; owner -> DAO at handoff)
        rewards = new GovernanceRewards(auth);
        giNFT = new GovernanceIncentivesNFT(cfg.giMintPrice, auth);
        approvalRegistry = new ApprovalRegistry(IERC721(address(giNFT)), auth);
        giNFT.setProceedsRecipient(address(rewards));
        rewards.setProposalRewardAmount(cfg.proposalReward);
        rewards.setMaxRefundPerVote(cfg.maxRefundPerVote);
        rewards.setApprovalRegistry(approvalRegistry); // locks

        // 5. Auction House (UUPS proxy) — initialize pauses it
        auctionHouseImpl = new ShwounsAuctionHouse(IShwounsToken(address(token)), cfg.weth, cfg.auctionDuration, auth);
        bytes memory ahInit = abi.encodeWithSelector(
            ShwounsAuctionHouse.initialize.selector,
            cfg.reservePrice, cfg.timeBuffer, cfg.minBidIncrementPct, IChainalysisSanctionsList(address(0))
        );
        auctionHouse = ShwounsAuctionHouse(payable(address(new ERC1967Proxy(address(auctionHouseImpl), ahInit))));
        auctionHouse.setGovernanceRewards(address(rewards));
        auctionHouse.setVaultRegistry(vaultRegistry);
        token.setMinter(address(auctionHouse));

        // 6. DAO Logic (UUPS proxy) — admin = Bootstrap transiently
        daoImpl = new ShwounsDAOLogic();
        ShwounsDAOTypes.ShwounsDAOParams memory daoParams = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: cfg.votingPeriod,
            votingDelay: cfg.votingDelay,
            proposalThresholdBPS: cfg.proposalThresholdBPS,
            proposalUpdatablePeriodInBlocks: cfg.proposalUpdatablePeriodInBlocks,
            proposalQueuePeriodInBlocks: cfg.proposalQueuePeriodInBlocks
        });
        ShwounsDAOTypes.DynamicQuorumParams memory daoQuorum = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: uint16(cfg.quorumVotesBPS), maxQuorumVotesBPS: 6000, quorumCoefficient: 0
        });
        bytes memory daoInit = abi.encodeWithSelector(
            ShwounsDAOLogic.initialize.selector,
            address(this), address(0), IShwounsTokenLike(address(token)), vaultRegistry, daoParams, daoQuorum
        );
        dao = ShwounsDAOLogic(payable(address(new ERC1967Proxy(address(daoImpl), daoInit))));
        if (cfg.lastMinuteWindowBlocks > 0) dao.setLastMinuteWindowInBlocks(cfg.lastMinuteWindowBlocks);
        if (cfg.objectionPeriodBlocks > 0) dao.setObjectionPeriodDurationInBlocks(cfg.objectionPeriodBlocks);

        // 7. Cross-wire DAO <-> registries; ProposalEscrow impl (immutable daoLogic = DAO proxy)
        vaultRegistry.setDAOLogic(address(dao)); // locks vault.pullProRata gate
        dao.setGovernanceRewards(address(rewards));
        rewards.setDAOLogic(address(dao)); // locks
        proposalEscrowImpl = new ProposalEscrow(address(dao), address(rewards));
        dao.setProposalEscrowImplementation(address(proposalEscrowImpl));

        // 8. Candidates (standalone)
        daoData = new ShwounsDAOData();

        emit Deployed(address(dao), auth);
    }

    /// @notice One-shot atomic handoff (A10). Binds the registry FIRST (so the no-EOA destination
    ///         checks resolve the canonical DAO), KICKS OFF the first auction (while Bootstrap still
    ///         owns it), transfers every Ownable to the DAO, sets DAOLogic admin to the DAO directly,
    ///         and revokes Bootstrap. Callable exactly once.
    /// @dev The auction is paused throughout the bootstrap/wiring phase (A10.1) and started here, at
    ///      handoff — the genesis kickoff. It MUST be started before ownership moves to the DAO:
    ///      post-handoff, unpausing would require a governance proposal, which requires voting power
    ///      from Shwouns that only auctions mint — a deadlock. (Mirrors Nouns' deployer kickoff.)
    function finalizeBootstrap() external {
        if (!deployed) revert NotDeployed();
        if (finalized) revert AlreadyFinalized();
        finalized = true;

        // Bind the registry to the DAO BEFORE transfers, so governed contracts validate the
        // canonical DAO destination during the atomic handoff (review §11).
        authRegistry.bindDAOLogic(address(dao));

        // Kick off auction #1 while Bootstrap still owns the auction house (deadlock-free genesis).
        if (auctionHouse.paused()) auctionHouse.unpause();

        // Transfer every Ownable's ownership to the DAO (A10.5: DAO or zero only).
        rewards.transferOwnership(address(dao));
        approvalRegistry.transferOwnership(address(dao));
        giNFT.transferOwnership(address(dao));
        auctionHouse.transferOwnership(address(dao));
        token.transferOwnership(address(dao));
        vaultRegistry.transferOwnership(address(dao));
        if (address(descriptor) != address(0)) descriptor.transferOwnership(address(dao));

        // Set DAOLogic admin to the DAO directly (the proxy can't self-accept the two-step).
        dao.setAdminToDAO();

        // Bootstrap now holds NO role (all ownership -> DAO, admin -> DAO). finalized bars re-entry.
        emit Finalized();
    }
}
