pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../contracts/Oracle/Oracle.sol";
import "../contracts/referrals/Referrals.sol";
import "../contracts/Controller.sol";
import "../contracts/vaults/presets/VaultJoeAvax.sol";
import "../test/Addresses.sol";


contract DeployAvaxScript is Script {

  address public constant TREASURY = 0x22Cc3f665ba4C898226353B672c5123c58751692;
  Controller public controller = Controller(0x553Fe5115392e2f024F1099E41A2f8ccB5eD2BcA);
  Oracle internal oracle = Oracle(0x71AC388e32B27F91b1d9696742fd63F5A1f41F94);
  bytes32 internal constant joeVaultName = "TraderJoeV1Avax";
  
  address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address internal constant JOE = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
  address internal constant USDT = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
  
  address internal constant WAVAX_USD_CHAINLINK_FEED = 0x0A77230d17318075983913bC2145DB16C7366156;
  address internal constant JOE_USD_CHAINLINK_FEED = 0x02D35d3a8aC3e1626d3eE09A78Dd87286F5E8e3a;
  address internal constant USDT_USD_CHAINLINK_FEED = 0xEBE676ee90Fe1112671f19b6B7459bC678B67e8a;
  
  
  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    
    //deploy_simple();
    deploy_joe();
    /*
    update_vault_Joe();
    */
    //update_pm();
    //update_oracle();
    //update_referrals();
    
    vm.stopBroadcast();
  }
  
  
  // Update the oracle
  function update_oracle() internal {
    address[] memory assets0 = new address[](0);
    address[] memory chainlinks0 = new address[](0);
    Oracle oracleCode = new Oracle(assets0, chainlinks0, address(0x0), USDT, 1e8, 45e5);
    
    UpgradeableBeacon oracleBeacon = UpgradeableBeacon(0x5d8b66928fc6716C8FDEB29593FCD18b57e9e8E0);
    
    oracleBeacon.upgradeTo(address(oracleCode));
  }
  
  
  // Update all vault implementation after change such as name()
  function update_vault_Joe() internal {
    VaultJoeAvax _vault = new VaultJoeAvax();
    address vaultImpl = controller.vaultImplementations(joeVaultName);
    controller.updateVaultBeacon(vaultImpl, address(_vault));
  }
 
  
  // Update positionmanager implementation
  function update_pm() internal {
    PositionManager pm = new PositionManager();
    controller.updatePMBeacon(address(pm));
  }

  
  // Deploy Referrals
  function update_referrals() internal {
    Referrals referrals = new Referrals();
    controller.updateReferrals(address(referrals));
  }
  
  
  // Simple deployment for testing FE
  function deploy_simple() internal {
    Referrals referrals = new Referrals();
    PositionManager positionManager = new PositionManager();
    // oracle = deployOracle(); // proxy to oracle 
    
    controller = new Controller(address(oracle), WAVAX, address(referrals), TREASURY, address(positionManager));
    
    // deploy vaults implementations
    deploy_vault_implementations();
  }
    
    
      
  function deployOracle() internal {
    address[] memory assets0 = new address[](0);
    address[] memory assets = new address[](2);
    assets[0] = WAVAX;
    assets[1] = JOE;
    address[] memory chainlinks0 = new address[](0);
    address[] memory chainlinks = new address[](2);
    chainlinks[0] = WAVAX_USD_CHAINLINK_FEED;
    chainlinks[1] = JOE_USD_CHAINLINK_FEED;
    Oracle oracleCode = new Oracle(assets0, chainlinks0, address(0x0), USDT, 1e8, 45e5);
    UpgradeableBeacon oracleUpgradeableBeacon = new UpgradeableBeacon(address(oracleCode));
    oracle = Oracle(address(new BeaconProxy(address(oracleUpgradeableBeacon), "")));
    oracle.initializer(assets, chainlinks, USDT, 1e8, 45e5);
  }
 
 
  function deploy_vault_implementations() internal {
    VaultJoeAvax _vaultJoeAvax = new VaultJoeAvax();
    UpgradeableBeacon _vaultUpgradeableBeacon = new UpgradeableBeacon(address(_vaultJoeAvax));
    controller.setVaultUpgradeableBeacon(address(_vaultUpgradeableBeacon), true);
    _vaultUpgradeableBeacon.transferOwnership(address(controller));
    // WAVAX-USDT on JoeV1
    controller.createVault(WAVAX, USDT, controller.vaultImplementations(_vaultJoeAvax.ammType()));
  }
 
  function deploy_joe() internal {

    // JOE-USDT on JoeV1
    controller.createVault(JOE, USDT, controller.vaultImplementations("TraderJoeV1Avax"));
  }
  
}