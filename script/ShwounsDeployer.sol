// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { Bootstrap } from "../src/governance/Bootstrap.sol";
import { ShwounsDAOTypes } from "../src/governance/ShwounsDAOInterfaces.sol";
// Imported only to force compilation of its artifact, which we deploy via vm.getCode (the proxies are
// CREATE2-deployed through Bootstrap, not `new`-ed here, so nothing else pulls it into the build).
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title ShwounsDeployer — shared, deterministic deployment orchestration (audit A2)
///
/// @notice The single source of truth for "deploy the whole Shwouns system via Bootstrap." Used by
///         both the broadcast script (Deploy.s.sol) and the integration tests, so the on-chain path
///         is exactly what tests exercise. It is a LIBRARY with INTERNAL functions: they inline into
///         the caller, so every `b.deploy/execute/registerManifest` call has the caller (the trusted
///         operator who deployed Bootstrap) as `msg.sender`, satisfying Bootstrap's onlyOperator gate.
///
/// @dev It supplies each contract's creation bytecode via `vm.getCode` (no embedded code → neither
///      Bootstrap nor the script bloats past EIP-170). Contracts that link external libraries
///      (ShwounsDescriptor → NFTDescriptorV2; ShwounsDAOSignatures → ShwounsDAOProposals; the
///      ShwounsDAOLogic impl → all three governance libs) cannot be read by `vm.getCode` (its
///      placeholders aren't valid hex), so for those we read the artifact's `bytecode.object` string,
///      replace each library's `__$<34hex>$__` placeholder with the deployed library address, assert
///      no placeholder remains (completeness — equivalent to resolving every linkReference), and only
///      then `vm.parseBytes`. The placeholder hash is the canonical
///      `keccak256("src/path.sol:Name")[0:34 hex]` (verified against the artifacts).
library ShwounsDeployer {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Deployment parameters (was Bootstrap.Config; Bootstrap is now generic so it lives here).
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
    }

    // Library fully-qualified names for link-placeholder computation.
    string internal constant FQN_NFT_DESCRIPTOR = "src/libs/NFTDescriptorV2.sol:NFTDescriptorV2";
    string internal constant FQN_PROPOSALS = "src/governance/ShwounsDAOProposals.sol:ShwounsDAOProposals";
    string internal constant FQN_SIGNATURES = "src/governance/ShwounsDAOSignatures.sol:ShwounsDAOSignatures";
    string internal constant FQN_QUORUM = "src/governance/ShwounsDAOQuorum.sol:ShwounsDAOQuorum";

    // The ShwounsDAOLogic.initialize selector (struct params: ShwounsDAOParams, DynamicQuorumParams).
    bytes4 internal constant DAO_INIT_SELECTOR = bytes4(
        keccak256(
            "initialize(address,address,address,address,(uint256,uint256,uint256,uint256,uint256),(uint16,uint16,uint32))"
        )
    );
    bytes4 internal constant AH_INIT_SELECTOR = bytes4(keccak256("initialize(uint192,uint56,uint8,address)"));

    /// @notice Deploy + wire the entire system via Bootstrap and register the manifest. Leaves the
    ///         system PAUSED with Bootstrap holding every role (pre-finalize). Art-load, lockParts and
    ///         finalizeBootstrap are SEPARATE runbook steps (finalize unpauses → mints, which needs
    ///         populated art). Returns the manifest (also stored in Bootstrap).
    function deployAll(Bootstrap b, Config memory cfg)
        internal
        returns (Bootstrap.DeploymentManifest memory m)
    {
        // 0. Auth registry FIRST (binder = Bootstrap) so every governed contract can take an
        //    immutable governanceAuth reference before the DAO proxy exists.
        m.authRegistry = b.deploy(vm.getCode("GovernanceAuthRegistry.sol:GovernanceAuthRegistry"), _salt("authRegistry"));

        // 1. Art stack. Descriptor links NFTDescriptorV2 (deploy it first, then link-patch).
        (m.art, m.descriptor) = _deployArtStack(b, m.authRegistry);

        // 2. Token (minter = Bootstrap temporarily; updated to the auction house below).
        address seeder = b.deploy(vm.getCode("ShwounsSeeder.sol:ShwounsSeeder"), _salt("seeder"));
        m.token = b.deploy(
            bytes.concat(
                vm.getCode("ShwounsToken.sol:ShwounsToken"),
                abi.encode(cfg.foundersDAO, address(b), m.descriptor, seeder, m.authRegistry)
            ),
            _salt("token")
        );

        // 3. Vault layer.
        m.vaultRegistry = b.deploy(
            bytes.concat(vm.getCode("ShwounsVaultRegistry.sol:ShwounsVaultRegistry"), abi.encode(m.token, m.authRegistry)),
            _salt("vaultRegistry")
        );
        m.vaultImpl = b.deploy(
            bytes.concat(vm.getCode("ShwounsVault.sol:ShwounsVault"), abi.encode(m.vaultRegistry)),
            _salt("vaultImpl")
        );
        b.execute(m.vaultRegistry, abi.encodeWithSignature("setVaultImplementation(address)", m.vaultImpl)); // locks

        // 4. Rewards + GI + ApprovalRegistry (A6: GI proceeds -> GR; owners -> DAO at handoff).
        m.rewards = b.deploy(bytes.concat(vm.getCode("GovernanceRewards.sol:GovernanceRewards"), abi.encode(m.authRegistry)), _salt("rewards"));
        m.giNFT = b.deploy(bytes.concat(vm.getCode("GovernanceIncentivesNFT.sol:GovernanceIncentivesNFT"), abi.encode(cfg.giMintPrice, m.authRegistry)), _salt("giNFT"));
        m.approvalRegistry = b.deploy(bytes.concat(vm.getCode("ApprovalRegistry.sol:ApprovalRegistry"), abi.encode(m.giNFT, m.authRegistry)), _salt("approvalRegistry"));
        b.execute(m.giNFT, abi.encodeWithSignature("setProceedsRecipient(address)", m.rewards));
        b.execute(m.rewards, abi.encodeWithSignature("setProposalRewardAmount(uint256)", cfg.proposalReward));
        b.execute(m.rewards, abi.encodeWithSignature("setMaxRefundPerVote(uint256)", cfg.maxRefundPerVote));
        b.execute(m.rewards, abi.encodeWithSignature("setApprovalRegistry(address)", m.approvalRegistry)); // locks

        // 5. Auction House (UUPS proxy; initialize pauses it).
        m.auctionHouse = _deployAuction(b, cfg, m.token, m.authRegistry, m.rewards, m.vaultRegistry);

        // 6. DAO Logic (libs + linked impl + UUPS proxy; admin = Bootstrap transiently).
        m.dao = _deployDAO(b, cfg, m.token, m.vaultRegistry);
        if (cfg.lastMinuteWindowBlocks > 0) b.execute(m.dao, abi.encodeWithSignature("setLastMinuteWindowInBlocks(uint32)", cfg.lastMinuteWindowBlocks));
        if (cfg.objectionPeriodBlocks > 0) b.execute(m.dao, abi.encodeWithSignature("setObjectionPeriodDurationInBlocks(uint32)", cfg.objectionPeriodBlocks));

        // 7. Cross-wire DAO <-> registries; ProposalEscrow impl (immutable daoLogic = DAO proxy).
        b.execute(m.vaultRegistry, abi.encodeWithSignature("setDAOLogic(address)", m.dao)); // locks
        b.execute(m.dao, abi.encodeWithSignature("setGovernanceRewards(address)", m.rewards)); // locks
        b.execute(m.rewards, abi.encodeWithSignature("setDAOLogic(address)", m.dao)); // locks
        m.proposalEscrowImpl = b.deploy(
            bytes.concat(vm.getCode("ProposalEscrow.sol:ProposalEscrow"), abi.encode(m.dao, m.rewards)),
            _salt("proposalEscrowImpl")
        );
        b.execute(m.dao, abi.encodeWithSignature("setProposalEscrowImplementation(address)", m.proposalEscrowImpl)); // locks

        // 8. Candidates registry (standalone; not a role-holder, not in the manifest).
        b.deploy(vm.getCode("ShwounsDAOData.sol:ShwounsDAOData"), _salt("daoData"));

        // 9. Commit the complete manifest (validates registered + nonzero + unique).
        b.registerManifest(m);
    }

    /// @dev Real art stack: NFTDescriptorV2 (linked into the descriptor), Inflator, SVGRenderer,
    ///      ShwounsArt (descriptor temp = Bootstrap so it can be re-pointed), ShwounsDescriptor, then
    ///      hand Art's authority to the descriptor. Returns (art, descriptor).
    function _deployArtStack(Bootstrap b, address authRegistry) private returns (address art, address descriptor) {
        address nftDescriptor = b.deploy(vm.getCode("NFTDescriptorV2.sol:NFTDescriptorV2"), _salt("nftDescriptor"));
        address inflator = b.deploy(vm.getCode("Inflator.sol:Inflator"), _salt("inflator"));
        address renderer = b.deploy(vm.getCode("SVGRenderer.sol:SVGRenderer"), _salt("renderer"));

        // ShwounsArt(address descriptor, IInflator inflator) — descriptor temp = Bootstrap.
        art = b.deploy(
            bytes.concat(vm.getCode("ShwounsArt.sol:ShwounsArt"), abi.encode(address(b), inflator)),
            _salt("art")
        );

        // ShwounsDescriptor(IShwounsArt art, ISVGRenderer renderer, address governanceAuth) — links NFTDescriptorV2.
        string[] memory fqns = new string[](1);
        fqns[0] = FQN_NFT_DESCRIPTOR;
        address[] memory libs = new address[](1);
        libs[0] = nftDescriptor;
        descriptor = b.deploy(
            _linkedInitcode(
                "out/ShwounsDescriptor.sol/ShwounsDescriptor.json",
                fqns,
                libs,
                abi.encode(art, renderer, authRegistry)
            ),
            _salt("descriptor")
        );

        // Hand Art's onlyDescriptor authority to the real descriptor.
        b.execute(art, abi.encodeWithSignature("setDescriptor(address)", descriptor));
    }

    function _deployAuction(
        Bootstrap b,
        Config memory cfg,
        address token,
        address authRegistry,
        address rewards,
        address vaultRegistry
    ) private returns (address auctionHouse) {
        address ahImpl = b.deploy(
            bytes.concat(
                vm.getCode("ShwounsAuctionHouse.sol:ShwounsAuctionHouse"),
                abi.encode(token, cfg.weth, cfg.auctionDuration, authRegistry)
            ),
            _salt("auctionHouseImpl")
        );
        bytes memory init = abi.encodeWithSelector(
            AH_INIT_SELECTOR, cfg.reservePrice, cfg.timeBuffer, cfg.minBidIncrementPct, address(0)
        );
        auctionHouse = b.deploy(
            bytes.concat(vm.getCode("ERC1967Proxy.sol:ERC1967Proxy"), abi.encode(ahImpl, init)),
            _salt("auctionHouse")
        );
        b.execute(auctionHouse, abi.encodeWithSignature("setGovernanceRewards(address)", rewards)); // locks
        b.execute(auctionHouse, abi.encodeWithSignature("setVaultRegistry(address)", vaultRegistry)); // locks
        b.execute(token, abi.encodeWithSignature("setMinter(address)", auctionHouse));
    }

    function _deployDAO(Bootstrap b, Config memory cfg, address token, address vaultRegistry)
        private
        returns (address dao)
    {
        // Governance libraries: Proposals + Quorum (no external deps) → Signatures (links Proposals)
        // → DAOLogic impl (links all three). Link addresses come from the prior CREATE2 returns.
        address proposalsLib = b.deploy(vm.getCode("ShwounsDAOProposals.sol:ShwounsDAOProposals"), _salt("proposalsLib"));
        address quorumLib = b.deploy(vm.getCode("ShwounsDAOQuorum.sol:ShwounsDAOQuorum"), _salt("quorumLib"));

        string[] memory sigFqns = new string[](1);
        sigFqns[0] = FQN_PROPOSALS;
        address[] memory sigLibs = new address[](1);
        sigLibs[0] = proposalsLib;
        address sigsLib = b.deploy(
            _linkedInitcode("out/ShwounsDAOSignatures.sol/ShwounsDAOSignatures.json", sigFqns, sigLibs, ""),
            _salt("signaturesLib")
        );

        string[] memory daoFqns = new string[](3);
        daoFqns[0] = FQN_PROPOSALS;
        daoFqns[1] = FQN_SIGNATURES;
        daoFqns[2] = FQN_QUORUM;
        address[] memory daoLibs = new address[](3);
        daoLibs[0] = proposalsLib;
        daoLibs[1] = sigsLib;
        daoLibs[2] = quorumLib;
        address daoImpl = b.deploy(
            _linkedInitcode("out/ShwounsDAOLogic.sol/ShwounsDAOLogic.json", daoFqns, daoLibs, ""),
            _salt("daoImpl")
        );

        ShwounsDAOTypes.ShwounsDAOParams memory p = ShwounsDAOTypes.ShwounsDAOParams({
            votingPeriod: cfg.votingPeriod,
            votingDelay: cfg.votingDelay,
            proposalThresholdBPS: cfg.proposalThresholdBPS,
            proposalUpdatablePeriodInBlocks: cfg.proposalUpdatablePeriodInBlocks,
            proposalQueuePeriodInBlocks: cfg.proposalQueuePeriodInBlocks
        });
        ShwounsDAOTypes.DynamicQuorumParams memory q = ShwounsDAOTypes.DynamicQuorumParams({
            minQuorumVotesBPS: uint16(cfg.quorumVotesBPS),
            maxQuorumVotesBPS: 6000,
            quorumCoefficient: 0
        });
        // admin = Bootstrap transiently; vetoer = 0.
        bytes memory init = abi.encodeWithSelector(DAO_INIT_SELECTOR, address(b), address(0), token, vaultRegistry, p, q);
        dao = b.deploy(
            bytes.concat(vm.getCode("ERC1967Proxy.sol:ERC1967Proxy"), abi.encode(daoImpl, init)),
            _salt("dao")
        );
    }

    // -------------------------------------------------------------------------
    // Link patching + helpers
    // -------------------------------------------------------------------------

    /// @dev Read an artifact's (possibly unlinked) creation bytecode, replace each library's
    ///      placeholder with its deployed address, ASSERT no placeholder remains (every link
    ///      resolved), then return parseBytes(linked) ++ ctorArgs.
    function _linkedInitcode(
        string memory artifactPath,
        string[] memory fqns,
        address[] memory libs,
        bytes memory ctorArgs
    ) internal view returns (bytes memory) {
        string memory obj = vm.parseJsonString(vm.readFile(artifactPath), ".bytecode.object");
        for (uint256 i = 0; i < fqns.length; i++) {
            // placeholder = "__$" + keccak256(fqn)[0:34 hex] + "$__"
            string memory ph = string.concat("__$", _slice(vm.toString(keccak256(bytes(fqns[i]))), 2, 36), "$__");
            // library address as 40 lowercase hex chars (parseBytes is case-insensitive anyway).
            string memory addrHex = _slice(vm.toString(libs[i]), 2, 42);
            obj = vm.replace(obj, ph, addrHex);
        }
        require(!_contains(obj, "__$"), "ShwounsDeployer: unresolved library link");
        return bytes.concat(vm.parseBytes(obj), ctorArgs);
    }

    function _salt(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("shwouns.v1.", label));
    }

    /// @dev Substring s[start:end) (byte indices).
    function _slice(string memory s, uint256 start, uint256 end) private pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(end - start);
        for (uint256 i = start; i < end; i++) out[i - start] = b[i];
        return string(out);
    }

    /// @dev True iff `needle` occurs in `hay`.
    function _contains(string memory hay, string memory needle) private pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || h.length < n.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) { ok = false; break; }
            }
            if (ok) return true;
        }
        return false;
    }
}
