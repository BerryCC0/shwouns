// SPDX-License-Identifier: GPL-3.0

/// @title The Shwouns ERC-721 token
/// @notice Forked from nouns-monorepo NounsToken.sol. Changes:
///   - Glasses field removed from Seed (matching IShwounsSeeder)
///   - OpenSea IProxyRegistry whitelist removed (Seaport-era; deprecated pattern)
///   - "nounders" renamed to "founders" for clarity
///   - Every 10th Noun goes to foundersDAO for the first 1820 IDs (matches Nouns)
///   - Vault auto-creation is NOT done here; AuctionHouse calls vaultRegistry.createVaultFor
///     after settlement. Token has no dependency on VaultRegistry.

pragma solidity ^0.8.6;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { ERC721Checkpointable } from './base/ERC721Checkpointable.sol';
import { IShwounsDescriptorMinimal } from '../interfaces/IShwounsDescriptorMinimal.sol';
import { IShwounsSeeder } from '../interfaces/IShwounsSeeder.sol';
import { IShwounsToken } from '../interfaces/IShwounsToken.sol';
import { ERC721 } from './base/ERC721.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

contract ShwounsToken is IShwounsToken, Ownable, ERC721Checkpointable {
    // The founders DAO address (creators org). Receives every 10th Noun up to FOUNDERS_REWARD_ENDS.
    address public foundersDAO;

    // Address authorized to mint (the AuctionHouse).
    address public minter;

    // The descriptor responsible for generating tokenURI / SVG.
    IShwounsDescriptorMinimal public descriptor;

    // The seeder responsible for generating trait seeds.
    IShwounsSeeder public seeder;

    // Lock flags — once set, cannot be unset.
    bool public isMinterLocked;
    bool public isDescriptorLocked;
    bool public isSeederLocked;

    // The Shwoun seeds.
    mapping(uint256 => IShwounsSeeder.Seed) public seeds;

    // The internal Shwoun ID tracker.
    uint256 private _currentShwounId;

    // IPFS content hash of contract-level metadata.
    string private _contractURIHash = '';

    /// @notice Last token ID at which founders receive a reward. Matches Nouns' 1820
    ///         (5 years × 365 days at 1 founder Noun per 10 daily auctions = 1820).
    uint256 public constant FOUNDERS_REWARD_ENDS = 1820;

    modifier whenMinterNotLocked() {
        require(!isMinterLocked, 'Minter is locked');
        _;
    }

    modifier whenDescriptorNotLocked() {
        require(!isDescriptorLocked, 'Descriptor is locked');
        _;
    }

    modifier whenSeederNotLocked() {
        require(!isSeederLocked, 'Seeder is locked');
        _;
    }

    modifier onlyFoundersDAO() {
        require(msg.sender == foundersDAO, 'Sender is not the founders DAO');
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, 'Sender is not the minter');
        _;
    }

    constructor(
        address _foundersDAO,
        address _minter,
        IShwounsDescriptorMinimal _descriptor,
        IShwounsSeeder _seeder
    ) ERC721('Shwouns', 'SHWN') {
        foundersDAO = _foundersDAO;
        minter = _minter;
        descriptor = _descriptor;
        seeder = _seeder;
    }

    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked('ipfs://', _contractURIHash));
    }

    function setContractURIHash(string memory newContractURIHash) external onlyOwner {
        _contractURIHash = newContractURIHash;
    }

    /// @notice Mint a Shwoun to the minter, with a possible founders reward Shwoun.
    /// @dev Founders reward Shwouns are minted every 10 IDs, starting at 0, until
    ///      FOUNDERS_REWARD_ENDS have been minted (5 years at 1/day auctions).
    function mint() public override onlyMinter returns (uint256) {
        if (_currentShwounId <= FOUNDERS_REWARD_ENDS && _currentShwounId % 10 == 0) {
            _mintTo(foundersDAO, _currentShwounId++);
        }
        return _mintTo(minter, _currentShwounId++);
    }

    /// @notice Burn a Shwoun. Restricted to the minter (the AuctionHouse).
    ///         In normal operation the AuctionHouse routes no-bid Shwouns to GovernanceRewards
    ///         via transferFrom rather than calling burn. This is retained for emergencies.
    function burn(uint256 shwounId) public override onlyMinter {
        _burn(shwounId);
        emit ShwounBurned(shwounId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), 'ShwounsToken: URI query for nonexistent token');
        return descriptor.tokenURI(tokenId, seeds[tokenId]);
    }

    function dataURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), 'ShwounsToken: URI query for nonexistent token');
        return descriptor.dataURI(tokenId, seeds[tokenId]);
    }

    function setFoundersDAO(address _foundersDAO) external onlyFoundersDAO {
        foundersDAO = _foundersDAO;
        emit FoundersDAOUpdated(_foundersDAO);
    }

    function setMinter(address _minter) external override onlyOwner whenMinterNotLocked {
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    function lockMinter() external override onlyOwner whenMinterNotLocked {
        isMinterLocked = true;
        emit MinterLocked();
    }

    function setDescriptor(IShwounsDescriptorMinimal _descriptor)
        external
        override
        onlyOwner
        whenDescriptorNotLocked
    {
        descriptor = _descriptor;
        emit DescriptorUpdated(_descriptor);
    }

    function lockDescriptor() external override onlyOwner whenDescriptorNotLocked {
        isDescriptorLocked = true;
        emit DescriptorLocked();
    }

    function setSeeder(IShwounsSeeder _seeder) external override onlyOwner whenSeederNotLocked {
        seeder = _seeder;
        emit SeederUpdated(_seeder);
    }

    function lockSeeder() external override onlyOwner whenSeederNotLocked {
        isSeederLocked = true;
        emit SeederLocked();
    }

    /// @dev Mint a Shwoun with `shwounId` to the provided `to` address.
    function _mintTo(address to, uint256 shwounId) internal returns (uint256) {
        IShwounsSeeder.Seed memory seed = seeds[shwounId] = seeder.generateSeed(shwounId, descriptor);

        _mint(owner(), to, shwounId);
        emit ShwounCreated(shwounId, seed);

        return shwounId;
    }
}
