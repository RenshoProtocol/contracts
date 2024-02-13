// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IController.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultConfigurator.sol";
import "./vaults/VaultBase.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/IWETH.sol";


/**
 * @title Controller
 * @dev handles parameters for creating and managing multiple vaults
 * As vault can be spawned on top of any v3
 */
contract Controller is IController, AccessControlEnumerable {
  event SetTreasury(address treasury, uint8 treasuryShareX2);
  event SetPermissionlessVaultCreation(bool isPermissionless);
  event SetVaultUpgradeableBeacon(address trBeacon, bool isEnabled);
  event SetVaultBeacon(address vaultUpgradeableBeacon, address vaultBeacon);
  event SetPMBeacon(address pmBeacon);
  event SetReferrals(address referrals);
  event SetPaused(bool _isPaused);
  event VaultCreated(address vault, address baseToken, address quoteToken, address vaultUpgradeableBeacon);

  /// @notice Pauser role for emergencies
  bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

  /// @notice Oracle Address
  IOracle public oracle;
  /// @notice Treasury address
  address public treasury = 0x22Cc3f665ba4C898226353B672c5123c58751692;
  /// @notice Treasury fee share in percent
  uint8 public treasuryShareX2 = 20;
  /// @notice Wrapped native asset (would actually be WMATIC on Polygon, etc.)
  IWETH public immutable WETH;
  /// @notice Permissionless spawning vaults?
  bool public isPermissionlessVaultCreation;
  /// @notice GEC+GEV paused or not
  bool public isPaused;
  
  /// @notice All existing vaults
  mapping(bytes32 => address) private _vaults;
  
  /// @notice Referrals contract
  address public referrals;
  
  /// @notice AmmPositionProxy Upgradable Beacon List for various Amms
  mapping(address => bool) public vaultUpgradeableBeacons;
  /// @notice mapping from ammType anme to UpgradeableBeacon address
  mapping(bytes32 => address) public vaultImplementations;
  /// @notice Position Manager upgradeable beacon
  UpgradeableBeacon public immutable pmUpgradeableBeacon;
  /// @notice Referrals contract, used when spawning new position manager
  
  
  constructor(address _oracle, address _WETH, address _referrals, address _treasury, address _positionManager) {
    require(_WETH != address(0x0), "GEC: Invalid WETH");
    WETH = IWETH(_WETH);
    require(_oracle != address(0x0), "GEC: Invalid Oracle");
    oracle = IOracle(_oracle);
    require(_referrals != address(0x0), "GEC: Invalid Referrals");
    referrals = _referrals;
    require(_positionManager != address(0), "GEC: Invalid PM");
    
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(PAUSER_ROLE, msg.sender);

    pmUpgradeableBeacon = new UpgradeableBeacon(address(_positionManager));

    setTreasury(_treasury, 20);
  }
  
  
  /// @notice Pause/unpause GEC and vaults
  function setPaused(bool _isPaused) public onlyRole(PAUSER_ROLE) {
    isPaused = _isPaused;
    emit SetPaused(_isPaused);
  }
  

  /// @notice Set treasury address
  /// @param _treasury New address
  function setTreasury(address _treasury, uint8 _treasuryShareX2) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_treasury != address(0x0), "GEC: Invalid Treasury");
    require(_treasuryShareX2 <= 100, "GEC: Invalid Treasury Share");
    treasury = _treasury; 
    treasuryShareX2 = _treasuryShareX2;
    emit SetTreasury(_treasury, _treasuryShareX2);
  } 

  
  /// @notice Set treasury address
  function setPermissionlessVaultCreation(bool _isPermissionlessVaultCreation) public onlyRole(DEFAULT_ADMIN_ROLE) {
    isPermissionlessVaultCreation = _isPermissionlessVaultCreation; 
    emit SetPermissionlessVaultCreation(_isPermissionlessVaultCreation);
  }
  
  
  /// @notice Add a new Rensho Vault proxy, e.g supporting a new AMM
  function setVaultUpgradeableBeacon(address _vaultUpgradeableBeacon, bool isEnabled) public onlyRole(DEFAULT_ADMIN_ROLE) {
    vaultUpgradeableBeacons[_vaultUpgradeableBeacon] = isEnabled;
    vaultImplementations[IVault(payable(UpgradeableBeacon(_vaultUpgradeableBeacon).implementation())).ammType()] = _vaultUpgradeableBeacon;
    emit SetVaultUpgradeableBeacon(_vaultUpgradeableBeacon, isEnabled);
  }
  
  
  /// @notice Upgrade the TokenisableRange implementations
  function updateVaultBeacon(address _vaultUpgradeableBeacon, address _newVaultImpl) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_newVaultImpl != address(0x0), "GEC: Invalid Beacon");
    require(
      keccak256(abi.encodePacked(IVault(payable(UpgradeableBeacon(_vaultUpgradeableBeacon).implementation())).ammType()))
      == keccak256(abi.encodePacked(IVault(payable(_newVaultImpl)).ammType() )),
      "GEC: Wrong Impl");
    UpgradeableBeacon(_vaultUpgradeableBeacon).upgradeTo(_newVaultImpl);
    emit SetVaultBeacon(_vaultUpgradeableBeacon, _newVaultImpl);
  }
  
  
  /// @notice Upgrade the TokenisableRange implementations
  function updateReferrals(address _referrals) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_referrals!= address(0x0), "GEC: Invalid Beacon");
    referrals = _referrals;
    emit SetReferrals(_referrals);
  }
  
  
  /// @notice Upgrade the PositionManager ammType
  function updatePMBeacon(address _pmImpl) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_pmImpl != address(0x0), "GEC: Invalid Beacon");
    pmUpgradeableBeacon.upgradeTo(_pmImpl);
    emit SetPMBeacon(_pmImpl);
  }
  
  
  /// @notice Create a new vault from 2 existing tokens, on a target AMM with fee tier
  /// @param vaultUpgradeableBeacon address of the proxy to the desired AmmPositionProxy instance (UniV3, Algebra...)
  function createVault(address baseToken, address quoteToken, address vaultUpgradeableBeacon) public returns (address vault) {
    require(baseToken != quoteToken, "GEC: Duplicate Tokens");
    require(isPermissionlessVaultCreation || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "GEC: Unauthorized");
    require(vaultUpgradeableBeacons[vaultUpgradeableBeacon], "GEV: Invalid Vault Beacon");
    
    // Spawn a proxy for the vault
    vault = address(new BeaconProxy(address(vaultUpgradeableBeacon), ""));
    bytes32 vaultId = getVaultId(baseToken, quoteToken, vaultUpgradeableBeacon);
    require(_vaults[vaultId] == address(0x0), "GEC: Already Deployed");
    _vaults[vaultId] = vault;

    // Spawn a proxy for the position manager
    BeaconProxy _bpm = new BeaconProxy(address(pmUpgradeableBeacon), "");
    IPositionManager _pm = IPositionManager(address(_bpm));
    _pm.initProxy(address(oracle), baseToken, quoteToken, vault, referrals);
    // Init the vault using one of the interfaces, all vaults implement initProxy method
    IVault(vault).initProxy(baseToken, quoteToken, address(_pm), address(WETH), address(oracle));
    // Transfer owner ship of vaults to this owner (governance, first listed admin)
    IVaultConfigurator(vault).transferOwnership(getRoleMember(DEFAULT_ADMIN_ROLE, 0));
    emit VaultCreated(vault, baseToken, quoteToken, vaultUpgradeableBeacon);
  }
  
  
  /// @notice Getter for vaults
  function getVault(address baseToken, address quoteToken, address vaultUpgradeableBeacon) public view returns (address vault) {
    vault = _vaults[getVaultId(baseToken, quoteToken, vaultUpgradeableBeacon)];
  }
  
  
  /// @notice compute vault ID
  function getVaultId(address baseToken, address quoteToken, address vaultUpgradeableBeacon) internal view returns (bytes32 vaultId) {
    bool baseTokenIsToken0 = baseToken < quoteToken;
    address token0 = baseTokenIsToken0 ? baseToken : quoteToken;
    address token1 = baseTokenIsToken0 ? quoteToken : baseToken;
    vaultId = sha256(abi.encode(token0, token1, vaultUpgradeableBeacon));
  }
}