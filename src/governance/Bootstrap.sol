// SPDX-License-Identifier: GPL-3.0

/// @title Bootstrap — minimal generic operator-gated deployment coordinator (A10, audit F1/F2/F3)
///
/// @notice A small, GENERIC coordinator that holds NO embedded contract creation code (the old
///         deploy-everything Bootstrap was 143KB — far over EIP-170, undeployable; audit F1). The
///         ephemeral deploy script supplies each contract's creation bytecode; Bootstrap CREATE2-
///         deploys it, so Bootstrap is `msg.sender` in every constructor and thus the transient
///         owner/admin/art-descriptor/auth-binder of the whole system — no permanent EOA ever holds
///         a role (A10.1). A single `finalizeBootstrap()` validates the complete wiring and atomically
///         hands every role to the DAO, then permanently disables itself.
///
/// @dev Security model (audit F2 — the old deploy()/finalize() were permissionless and front-runnable):
///        - `operator` is the trusted deployer, pinned to `msg.sender` at construction.
///        - `onlyOperator` gates deploy/execute/registerManifest/finalize.
///        - `notFinalized` is a one-way latch: after finalize, deploy/execute/registerManifest revert
///          forever, so no residual authority survives the handoff.
///        - `execute` may only target Bootstrap-deployed (`isRegistered`) contracts.
///        - `finalizeBootstrap` operates on a STORED manifest (not caller-supplied addresses), and
///          asserts ownership + every one-shot lock + the operational wiring + the IMMUTABLE/
///          constructor wiring matrix BEFORE the handoff, and the destination state AFTER — so a
///          wiring or omission mistake reverts a finalize, never silently strands or mis-wires a role.
pragma solidity ^0.8.19;

// ---------------------------------------------------------------------------------------------------
// Lean interfaces for the finalize prechecks/handoff. Bootstrap imports NO concrete contract (so it
// embeds no creation code); it only needs these getters/setters at handoff. Getters that return a
// typed contract on the real contract are declared here as `address` — ABI-identical (20-byte word).
// ---------------------------------------------------------------------------------------------------

interface IOwnableLike {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IGovernedLike {
    function governanceAuth() external view returns (address);
}

interface ITokenLike {
    function minter() external view returns (address);
    function descriptor() external view returns (address);
}

interface IAuctionLike {
    function governanceRewards() external view returns (address);
    function vaultRegistry() external view returns (address);
    function shwouns() external view returns (address);
    function governanceRewardsLocked() external view returns (bool);
    function vaultRegistryLocked() external view returns (bool);
    function paused() external view returns (bool);
    function unpause() external;
}

interface IVaultRegistryLike {
    function vaultImplementation() external view returns (address);
    function vaultImplementationLocked() external view returns (bool);
    function daoLogic() external view returns (address);
    function daoLogicLocked() external view returns (bool);
    function shwounsToken() external view returns (address);
}

interface IRewardsLike {
    function dao() external view returns (address);
    function approvalRegistry() external view returns (address);
    function daoLocked() external view returns (bool);
    function approvalRegistryLocked() external view returns (bool);
}

interface IGiLike {
    function proceedsRecipient() external view returns (address);
}

interface IApprovalRegistryLike {
    function giNFT() external view returns (address);
}

interface IDescriptorLike {
    function art() external view returns (address);
    function arePartsLocked() external view returns (bool);
}

interface IArtLike {
    function descriptor() external view returns (address);
}

interface IVaultImplLike {
    function vaultRegistry() external view returns (address);
}

interface IEscrowImplLike {
    function daoLogic() external view returns (address);
    function residualSink() external view returns (address);
}

interface IDAOLike {
    function governanceRewards() external view returns (address);
    function governanceRewardsLocked() external view returns (bool);
    function proposalEscrowImplementation() external view returns (address);
    function proposalEscrowImplementationLocked() external view returns (bool);
    function shwouns() external view returns (address);
    function vaultRegistry() external view returns (address);
    function admin() external view returns (address);
    function setAdminToDAO() external;
}

interface IAuthRegistryLike {
    function binder() external view returns (address);
    function daoLogic() external view returns (address);
    function bindDAOLogic(address daoLogic) external;
}

contract Bootstrap {
    /// @notice The complete, typed set of addresses finalizeBootstrap operates on. Set once via
    ///         registerManifest. Role-holders (transferred to the DAO) PLUS the impls/peripherals the
    ///         wiring asserts reference. NOT caller-supplied at finalize (audit plan-review F2): the
    ///         exact set is committed up front so nothing can be silently omitted.
    struct DeploymentManifest {
        // Role-holders — every one is an Ownable transferred to the DAO at handoff.
        address dao; // DAO proxy (admin handed over via setAdminToDAO, not transferOwnership)
        address authRegistry; // GovernanceAuthRegistry (binder is immutable; not Ownable)
        address auctionHouse;
        address token;
        address descriptor;
        address vaultRegistry;
        address rewards;
        address giNFT;
        address approvalRegistry;
        // Impls/peripherals referenced by the wiring asserts (NOT transferred — stateless or non-Ownable).
        address art;
        address vaultImpl;
        address proposalEscrowImpl;
    }

    /// @notice The trusted deployer. Pinned at construction; the only address that may drive Bootstrap.
    address public immutable operator;

    /// @notice One-way latch. Once true, deploy/execute/registerManifest revert forever.
    bool public finalized;

    /// @notice Whether registerManifest has run (finalize requires it).
    bool public manifestRegistered;

    /// @notice Contracts CREATE2-deployed by this Bootstrap. `execute` may only target these.
    mapping(address => bool) public isRegistered;

    /// @notice The stored deployment manifest (set once).
    DeploymentManifest public manifest;

    event Deployed(address indexed addr, bytes32 indexed salt);
    event Executed(address indexed target);
    event ManifestRegistered(address indexed dao);
    event Finalized(address indexed dao);

    error NotOperator();
    error AlreadyFinalized();
    error NotRegistered(address target);
    error DeployFailed();
    error ManifestAlreadySet();
    error ManifestNotSet();
    error BatchLengthMismatch();

    constructor() {
        operator = msg.sender;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier notFinalized() {
        if (finalized) revert AlreadyFinalized();
        _;
    }

    // -------------------------------------------------------------------------
    // Deploy + drive (operator-only, pre-finalize)
    // -------------------------------------------------------------------------

    /// @notice CREATE2-deploy supplied creation code (constructor args already appended by the
    ///         caller). Because Bootstrap executes the CREATE2, `msg.sender` in the constructor is
    ///         Bootstrap → every Ownable it deploys is owned by Bootstrap (A10.1: no EOA owns roles).
    function deploy(bytes calldata creationCode, bytes32 salt)
        external
        onlyOperator
        notFinalized
        returns (address addr)
    {
        bytes memory code = creationCode;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
        }
        if (addr == address(0)) revert DeployFailed();
        isRegistered[addr] = true;
        emit Deployed(addr, salt);
    }

    /// @notice Drive an `onlyOwner`/`onlyAdmin`/`onlyDescriptor` call on a Bootstrap-deployed
    ///         contract (wiring + art load/lock). Restricted to registered targets and bubbles the
    ///         target's revert. Non-payable: no protocol wiring needs value, and the contracts are
    ///         funded later by auctions/governance.
    function execute(address target, bytes calldata data)
        external
        onlyOperator
        notFinalized
        returns (bytes memory)
    {
        if (!isRegistered[target]) revert NotRegistered(target);
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        emit Executed(target);
        return ret;
    }

    /// @notice Batched `execute` — for the ~20-30 art-load ops in a few txs. Same registered-target
    ///         + revert-bubble semantics per call.
    function executeBatch(address[] calldata targets, bytes[] calldata datas)
        external
        onlyOperator
        notFinalized
    {
        if (targets.length != datas.length) revert BatchLengthMismatch();
        for (uint256 i = 0; i < targets.length; i++) {
            if (!isRegistered[targets[i]]) revert NotRegistered(targets[i]);
            (bool ok, bytes memory ret) = targets[i].call(datas[i]);
            if (!ok) {
                assembly {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
            emit Executed(targets[i]);
        }
    }

    // -------------------------------------------------------------------------
    // Manifest (operator-only, pre-finalize, once)
    // -------------------------------------------------------------------------

    /// @notice Commit the complete deployment manifest. Each address must be Bootstrap-deployed
    ///         (isRegistered), nonzero, and pairwise-distinct — so the exact set finalize checks is
    ///         fixed up front and nothing can be omitted, duplicated, or foreign.
    function registerManifest(DeploymentManifest calldata m) external onlyOperator notFinalized {
        if (manifestRegistered) revert ManifestAlreadySet();

        address[12] memory a = [
            m.dao, m.authRegistry, m.auctionHouse, m.token, m.descriptor, m.vaultRegistry,
            m.rewards, m.giNFT, m.approvalRegistry, m.art, m.vaultImpl, m.proposalEscrowImpl
        ];
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "manifest: zero address");
            require(isRegistered[a[i]], "manifest: not bootstrap-deployed");
            for (uint256 j = i + 1; j < a.length; j++) {
                require(a[i] != a[j], "manifest: duplicate address");
            }
        }

        manifest = m;
        manifestRegistered = true;
        emit ManifestRegistered(m.dao);
    }

    // -------------------------------------------------------------------------
    // Finalize — one-shot atomic handoff (A10.5) with full pre/post validation
    // -------------------------------------------------------------------------

    /// @notice Validate the complete wiring on the STORED manifest, then atomically hand every role
    ///         to the DAO and permanently disable Bootstrap. Reverts (changing nothing but `finalized`,
    ///         which a revert rolls back) if any precheck fails — so a mis-wire can never be handed off.
    function finalizeBootstrap() external onlyOperator notFinalized {
        if (!manifestRegistered) revert ManifestNotSet();
        finalized = true; // bars deploy/execute/registerManifest; rolled back atomically if we revert

        _checkOwnership();
        _checkLocksAndWiring();
        _checkImmutableMatrix();
        _handoffToDAO();
        _assertHandoffComplete();

        emit Finalized(manifest.dao);
    }

    /// @dev Every manifest Ownable (the 7 role-holders) must currently be owned by Bootstrap.
    function _checkOwnership() internal view {
        DeploymentManifest memory m = manifest;
        require(IOwnableLike(m.token).owner() == address(this), "own: token");
        require(IOwnableLike(m.descriptor).owner() == address(this), "own: descriptor");
        require(IOwnableLike(m.vaultRegistry).owner() == address(this), "own: vaultRegistry");
        require(IOwnableLike(m.rewards).owner() == address(this), "own: rewards");
        require(IOwnableLike(m.giNFT).owner() == address(this), "own: giNFT");
        require(IOwnableLike(m.approvalRegistry).owner() == address(this), "own: approvalRegistry");
        require(IOwnableLike(m.auctionHouse).owner() == address(this), "own: auctionHouse");
    }

    /// @dev Every settable wiring relationship AND its one-shot lock (audit plan-review2 F2 / F3):
    ///      a successful finalize guarantees not just ownership but that the system is fully, lockably
    ///      wired and the art is finalized — so nothing can be handed off half-configured.
    function _checkLocksAndWiring() internal view {
        DeploymentManifest memory m = manifest;

        // Token wiring.
        require(ITokenLike(m.token).minter() == m.auctionHouse, "wire: token.minter");
        require(ITokenLike(m.token).descriptor() == m.descriptor, "wire: token.descriptor");

        // Vault registry: impl + DAO, both locked.
        require(IVaultRegistryLike(m.vaultRegistry).vaultImplementation() == m.vaultImpl, "wire: vr.vaultImpl");
        require(IVaultRegistryLike(m.vaultRegistry).vaultImplementationLocked(), "lock: vr.vaultImpl");
        require(IVaultRegistryLike(m.vaultRegistry).daoLogic() == m.dao, "wire: vr.daoLogic");
        require(IVaultRegistryLike(m.vaultRegistry).daoLogicLocked(), "lock: vr.daoLogic");

        // Rewards: DAO + approval registry, both locked.
        require(IRewardsLike(m.rewards).dao() == m.dao, "wire: rewards.dao");
        require(IRewardsLike(m.rewards).daoLocked(), "lock: rewards.dao");
        require(IRewardsLike(m.rewards).approvalRegistry() == m.approvalRegistry, "wire: rewards.approvalRegistry");
        require(IRewardsLike(m.rewards).approvalRegistryLocked(), "lock: rewards.approvalRegistry");

        // DAO: rewards + escrow impl, both locked.
        require(IDAOLike(m.dao).governanceRewards() == m.rewards, "wire: dao.rewards");
        require(IDAOLike(m.dao).governanceRewardsLocked(), "lock: dao.rewards");
        require(IDAOLike(m.dao).proposalEscrowImplementation() == m.proposalEscrowImpl, "wire: dao.escrowImpl");
        require(IDAOLike(m.dao).proposalEscrowImplementationLocked(), "lock: dao.escrowImpl");

        // Auction house: rewards + registry, both locked.
        require(IAuctionLike(m.auctionHouse).governanceRewards() == m.rewards, "wire: ah.rewards");
        require(IAuctionLike(m.auctionHouse).governanceRewardsLocked(), "lock: ah.rewards");
        require(IAuctionLike(m.auctionHouse).vaultRegistry() == m.vaultRegistry, "wire: ah.vaultRegistry");
        require(IAuctionLike(m.auctionHouse).vaultRegistryLocked(), "lock: ah.vaultRegistry");

        // GI proceeds + approval registry's GI ref.
        require(IGiLike(m.giNFT).proceedsRecipient() == m.rewards, "wire: gi.proceeds");
        require(IApprovalRegistryLike(m.approvalRegistry).giNFT() == m.giNFT, "wire: ar.giNFT");

        // Art handed to the descriptor AND finalized: the runbook runs lockParts via execute before
        // finalize, so art can't be handed off unfinished (audit plan-review3).
        require(IArtLike(m.art).descriptor() == m.descriptor, "wire: art.descriptor");
        require(IDescriptorLike(m.descriptor).arePartsLocked(), "lock: descriptor.parts");
    }

    /// @dev The IMMUTABLE / constructor wiring matrix (audit plan-review4): these are fixed at
    ///      construction and CANNOT be repaired post-deploy, so a mis-constructed dependency would be
    ///      handed off permanently broken. Assert them all against the stored manifest.
    function _checkImmutableMatrix() internal view {
        DeploymentManifest memory m = manifest;

        require(IAuthRegistryLike(m.authRegistry).binder() == address(this), "imm: authRegistry.binder");

        // Every governed contract's immutable governanceAuth points at the one auth registry.
        require(IGovernedLike(m.token).governanceAuth() == m.authRegistry, "imm: token.auth");
        require(IGovernedLike(m.vaultRegistry).governanceAuth() == m.authRegistry, "imm: vr.auth");
        require(IGovernedLike(m.rewards).governanceAuth() == m.authRegistry, "imm: rewards.auth");
        require(IGovernedLike(m.giNFT).governanceAuth() == m.authRegistry, "imm: gi.auth");
        require(IGovernedLike(m.approvalRegistry).governanceAuth() == m.authRegistry, "imm: ar.auth");
        require(IGovernedLike(m.descriptor).governanceAuth() == m.authRegistry, "imm: descriptor.auth");
        require(IGovernedLike(m.auctionHouse).governanceAuth() == m.authRegistry, "imm: ah.auth");

        // Auction/registry/vault-impl/descriptor/escrow-impl constructor refs.
        require(IAuctionLike(m.auctionHouse).shwouns() == m.token, "imm: ah.shwouns");
        require(IVaultRegistryLike(m.vaultRegistry).shwounsToken() == m.token, "imm: vr.shwounsToken");
        require(IVaultImplLike(m.vaultImpl).vaultRegistry() == m.vaultRegistry, "imm: vaultImpl.registry");
        require(IDescriptorLike(m.descriptor).art() == m.art, "imm: descriptor.art");
        require(IEscrowImplLike(m.proposalEscrowImpl).daoLogic() == m.dao, "imm: escrowImpl.daoLogic");
        require(IEscrowImplLike(m.proposalEscrowImpl).residualSink() == m.rewards, "imm: escrowImpl.sink");

        // The DAO proxy's initialize() references.
        require(IDAOLike(m.dao).shwouns() == m.token, "imm: dao.shwouns");
        require(IDAOLike(m.dao).vaultRegistry() == m.vaultRegistry, "imm: dao.vaultRegistry");
    }

    /// @dev The A10.5-validated handoff ordering. Bind the registry FIRST (so governed contracts
    ///      resolve the canonical DAO during the atomic handoff), KICK OFF auction #1 while Bootstrap
    ///      still owns the auction house (post-handoff, unpausing would need voting power that only
    ///      auctions mint — a deadlock), THEN transfer every Ownable to the DAO and set DAO admin.
    function _handoffToDAO() internal {
        DeploymentManifest memory m = manifest;

        IAuthRegistryLike(m.authRegistry).bindDAOLogic(m.dao);

        if (IAuctionLike(m.auctionHouse).paused()) IAuctionLike(m.auctionHouse).unpause();

        IOwnableLike(m.rewards).transferOwnership(m.dao);
        IOwnableLike(m.approvalRegistry).transferOwnership(m.dao);
        IOwnableLike(m.giNFT).transferOwnership(m.dao);
        IOwnableLike(m.auctionHouse).transferOwnership(m.dao);
        IOwnableLike(m.token).transferOwnership(m.dao);
        IOwnableLike(m.vaultRegistry).transferOwnership(m.dao);
        IOwnableLike(m.descriptor).transferOwnership(m.dao);

        IDAOLike(m.dao).setAdminToDAO();
    }

    /// @dev After the handoff: every role-holder is DAO-owned, the DAO is its own admin, the registry
    ///      is bound, and the auction is running. Bootstrap now holds NO role; `finalized` bars re-entry.
    function _assertHandoffComplete() internal view {
        DeploymentManifest memory m = manifest;
        require(IOwnableLike(m.token).owner() == m.dao, "post: token owner");
        require(IOwnableLike(m.descriptor).owner() == m.dao, "post: descriptor owner");
        require(IOwnableLike(m.vaultRegistry).owner() == m.dao, "post: vaultRegistry owner");
        require(IOwnableLike(m.rewards).owner() == m.dao, "post: rewards owner");
        require(IOwnableLike(m.giNFT).owner() == m.dao, "post: giNFT owner");
        require(IOwnableLike(m.approvalRegistry).owner() == m.dao, "post: approvalRegistry owner");
        require(IOwnableLike(m.auctionHouse).owner() == m.dao, "post: auctionHouse owner");
        require(IDAOLike(m.dao).admin() == m.dao, "post: dao admin");
        require(IAuthRegistryLike(m.authRegistry).daoLogic() == m.dao, "post: registry bound");
        require(!IAuctionLike(m.auctionHouse).paused(), "post: auction paused");
    }
}
