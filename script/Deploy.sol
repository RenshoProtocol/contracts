pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../contracts/Oracle/Oracle.sol";
import "../contracts/referrals/Referrals.sol";
import "../contracts/Controller.sol";
import "../contracts/vaults/presets/VaultAlgebra19.sol";
import "../contracts/vaults/presets/VaultUniV2.sol";
import "../contracts/vaults/presets/VaultUniV3.sol";
import "../test/Addresses.sol";


contract DeployScript is Script {

  address public constant TREASURY = 0x22Cc3f665ba4C898226353B672c5123c58751692;
  Controller public controller = Controller(0xdDeC418c1a825Ac09aD83cc1A28a2c5Bcd746050);
  bytes32 internal constant univ3VaultName = "UniswapV3-0.05";
  bytes32 internal constant univ2VaultName = "UniswapV2";
  bytes32 internal constant algebraVaultName = "Algebra-1.9";
  Referrals internal referrals = Referrals(0x6EE947E1eBB4dF794fBcbB0007523D2ca7d8c7fB);
  Oracle internal oracle = Oracle(0x4A9EB72b72cB6fBbD8eF8C83342f252e519559e9);
  PositionManager internal positionManager;
  
  
  function setUp() public {}
  

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    
    deploy_simple();
    /*
    update_vault_UniV2();
    update_vault_UniV3();
    update_vault_Algebra19();
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
    Oracle oracleCode = new Oracle(assets0, chainlinks0, address(0x0), Addresses.USD, 1e8, 45e5);
    
    UpgradeableBeacon oracleBeacon = UpgradeableBeacon(0xA99e324B34d463671140B72EF654c740466F40A8); 
    oracleBeacon.upgradeTo(address(oracleCode));
  }
  
  
  // Update all vault implementation after change such as name()
  function update_vault_UniV2() internal {
    VaultUniV2 _vaultUniV2 = new VaultUniV2();
    address vaultImpl = controller.vaultImplementations(univ2VaultName);
    controller.updateVaultBeacon(vaultImpl, address(_vaultUniV2));
  }
  
  
  function update_vault_UniV3() internal {
    VaultUniV3 _vaultUniV3 = new VaultUniV3();
    address vaultImpl = controller.vaultImplementations(univ3VaultName);
    controller.updateVaultBeacon(vaultImpl, address(_vaultUniV3));
  }
  
  // Update positionmanager implementation
  function update_pm() internal {
    PositionManager pm = new PositionManager();
    controller.updatePMBeacon(address(pm));
  }
  
  // Deploy Referrals
  function update_referrals() internal {
    referrals = new Referrals();
    controller.updateReferrals(address(referrals));
  }
  
  
  // Simple deployment for testing FE
  function deploy_simple() internal {
    referrals = new Referrals();
    positionManager = new PositionManager();
    deployOracle(); // proxy to oracle
    
    controller = new Controller(address(oracle), Addresses.WETH, address(referrals), TREASURY, address(positionManager));
    
    // deploy uni2 and alg vaults implementations
    deploy_vault_implementations();
  }
    
    
      
  function deployOracle() internal {
    address[] memory assets0 = new address[](0);
    address[] memory assets = new address[](1);
    assets[0] = Addresses.WETH;
    address[] memory chainlinks0 = new address[](0);
    address[] memory chainlinks = new address[](1);
    chainlinks[0] = Addresses.WETH_USD_CHAINLINK_FEED;
    Oracle oracleCode = new Oracle(assets0, chainlinks0, address(0x0), Addresses.USD, 1e8, 45e5);
    UpgradeableBeacon oracleUpgradeableBeacon = new UpgradeableBeacon(address(oracleCode));
    oracle = Oracle(address(new BeaconProxy(address(oracleUpgradeableBeacon), "")));
    oracle.initializer(assets, chainlinks, Addresses.USD, 1e8, 45e5);
  }
 
 
  function deploy_vault_implementations() internal {
    VaultUniV3 _vaultUniV3 = new VaultUniV3();
    UpgradeableBeacon _vaultUpgradeableBeacon = new UpgradeableBeacon(address(_vaultUniV3));
    controller.setVaultUpgradeableBeacon(address(_vaultUpgradeableBeacon), true);
    _vaultUpgradeableBeacon.transferOwnership(address(controller));
    // WETH-USD on Uni v3 0.05% fee
    controller.createVault(Addresses.WETH, Addresses.USD, controller.vaultImplementations(_vaultUniV3.ammType()));
    
    VaultUniV2 _vaultUniV2 = new VaultUniV2();
    _vaultUpgradeableBeacon = new UpgradeableBeacon(address(_vaultUniV2));
    controller.setVaultUpgradeableBeacon(address(_vaultUpgradeableBeacon), true);
    _vaultUpgradeableBeacon.transferOwnership(address(controller));
  }
  
}