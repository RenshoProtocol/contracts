// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "./Deployments.sol";
import "../contracts/Controller.sol";
import "../contracts/ammPositions/Algebra19Position.sol";
import "../contracts/interfaces/IVaultConfigurator.sol";


contract Test_Core is Test, Oracle_Deployment {
  Controller internal controller;
  Referrals internal referrals;
  bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");
  PositionManager internal pm;
  
  constructor() {
    referrals = new Referrals();
    pm = new PositionManager();
  }

  function test_Deployment() public {
    vm.expectRevert("controller: Invalid WETH");
    controller = new Controller(address(testOracle), address(0x0), address(referrals), Addresses.TREASURY, address(pm));
    vm.expectRevert("controller: Invalid Oracle");
    controller = new Controller(address(0x0), Addresses.WETH, address(referrals), Addresses.TREASURY, address(pm));
    vm.expectRevert("controller: Invalid Referrals");
    controller = new Controller(address(testOracle), Addresses.WETH, address(0x0), Addresses.TREASURY, address(pm));
    vm.expectRevert("controller: Invalid PM");
    controller = new Controller(address(testOracle), Addresses.WETH, address(referrals), Addresses.TREASURY, address(0));
    
    controller = new Controller(address(testOracle), Addresses.WETH, address(referrals), Addresses.TREASURY, address(pm));
  }
  
  
  function test_controller () public {
    controller = new Controller(address(testOracle), Addresses.WETH, address(referrals), Addresses.TREASURY, address(pm));
    bytes32 name = "UniswapV3-0.05";
    VaultUniV3 _vaultUniV3= new VaultUniV3();
    UpgradeableBeacon vaultUpgradeableBeacon = new UpgradeableBeacon(address(_vaultUniV3));
    controller.setVaultUpgradeableBeacon(address(vaultUpgradeableBeacon), true);
    
    vm.expectRevert("controller: Invalid Treasury");
    controller.setTreasury(address(0x0), 30);
    vm.expectRevert("controller: Invalid Treasury Share");
    controller.setTreasury(Addresses.TREASURY, 120);
    controller.setTreasury(Addresses.TREASURY, 30);
    assertEq(controller.treasury(), Addresses.TREASURY);
    assertEq(controller.treasuryShareX2(), 30);
    vm.expectRevert("controller: Duplicate Tokens");
    controller.createVault(Addresses.WETH, Addresses.WETH, address(vaultUpgradeableBeacon));

    vm.expectRevert("GEV: Invalid Vault Beacon");
    controller.createVault(Addresses.WETH, Addresses.USD, address(0));
    
    assertEq(address(0), controller.getVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon)));
    address vault = controller.createVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon));
    assertEq(vault, controller.getVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon)));
    vm.expectRevert("controller: Already Deployed");
    controller.createVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon));

    assertEq(controller.isPermissionlessVaultCreation(), false);
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("controller: Unauthorized");
    controller.createVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon));
    vm.expectRevert("AccessControl: account 0x0000000000000000000010000000000000000101 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
    controller.setPermissionlessVaultCreation(true);
    vm.stopPrank();
    
    controller.setPermissionlessVaultCreation(true);
    vm.startPrank(Addresses.RANDOM);
    
    controller.createVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon));
    vm.stopPrank();
    
    // checks that vaults created are sane
    IVaultConfigurator v = IVaultConfigurator(controller.getVault(Addresses.WETH, Addresses.USD, address(vaultUpgradeableBeacon)));
    assertEq(v.owner(), address(this));
    assertGt(v.baseFeeX4(), 0);
    
    // Test granting pauser role
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("AccessControl: account 0x0000000000000000000010000000000000000101 is missing role 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a");
    controller.setPaused(true);
    vm.stopPrank();
    
    controller.grantRole(PAUSER_ROLE, Addresses.RANDOM);
    vm.startPrank(Addresses.RANDOM);
    controller.setPaused(true);
    vm.stopPrank();
  }
  
  
  function test_Beacons() public {
    controller = new Controller(address(testOracle), Addresses.WETH, address(referrals), Addresses.TREASURY, address(pm));
    
    VaultUniV3 _vaultUniV3 = new VaultUniV3();
    UpgradeableBeacon _vaultUpgradeableBeaconV3 = new UpgradeableBeacon(address(_vaultUniV3));
    assertEq(controller.vaultUpgradeableBeacons(address(_vaultUpgradeableBeaconV3)), false);
    controller.setVaultUpgradeableBeacon(address(_vaultUpgradeableBeaconV3), true);
    assertEq(controller.vaultUpgradeableBeacons(address(_vaultUpgradeableBeaconV3)), true);
    _vaultUpgradeableBeaconV3.transferOwnership(address(controller));
    
    VaultUniV2 _vaultUniV2 = new VaultUniV2();
    UpgradeableBeacon _vaultUpgradeableBeaconV2 = new UpgradeableBeacon(address(_vaultUniV2));
    assertEq(controller.vaultUpgradeableBeacons(address(_vaultUpgradeableBeaconV2)), false);
    controller.setVaultUpgradeableBeacon(address(_vaultUpgradeableBeaconV2), true);
    assertEq(controller.vaultUpgradeableBeacons(address(_vaultUpgradeableBeaconV2)), true);
    
    VaultAlgebra19 _vaultAlgebra = new VaultAlgebra19();
    UpgradeableBeacon _vaultUpgradeableBeaconAlg = new UpgradeableBeacon(address(_vaultAlgebra));
    assertEq(controller.vaultUpgradeableBeacons(address(_vaultUpgradeableBeaconAlg)), false);
    controller.setVaultUpgradeableBeacon(address(_vaultUpgradeableBeaconAlg), true);
    assertEq(controller.vaultUpgradeableBeacons(address(_vaultUpgradeableBeaconAlg)), true);
    
    //test update beacon
    VaultUniV3 _vaultUniV32 = new VaultUniV3();
    vm.expectRevert("controller: Wrong Impl");
    controller.updateVaultBeacon(address(_vaultUpgradeableBeaconV2), address(_vaultUniV32));
    vm.expectRevert("controller: Invalid Beacon");
    controller.updateVaultBeacon(address(_vaultUpgradeableBeaconV3), address(0));
    controller.updateVaultBeacon(address(_vaultUpgradeableBeaconV3), address(_vaultUniV32));
    
    // PM beacon
    PositionManager _pmImplementationV2 = new PositionManager();
    vm.expectRevert("controller: Invalid Beacon");
    controller.updatePMBeacon(address(0x0));
    controller.updatePMBeacon(address(_pmImplementationV2));
    
    referrals = new Referrals();
    vm.expectRevert("controller: Invalid Beacon");
    controller.updateReferrals(address(0x0));
    controller.updateReferrals(address(referrals));
    

  }
  

}