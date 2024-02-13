// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../contracts/Oracle/Oracle.sol";
import "../contracts/ammPositions/UniswapV3Position.sol";
import "../contracts/ammPositions/Algebra19Position.sol";
import "../contracts/ammPositions/UniswapV2Position.sol";
import "../contracts/PositionManager/PositionManager.sol";
import "../contracts/vaults/VaultBase.sol";
import "../contracts/vaults/presets/VaultUniV2.sol";
import "../contracts/vaults/presets/VaultUniV3.sol";
import "../contracts/vaults/presets/VaultAlgebra19.sol";
import "../contracts/referrals/Referrals.sol";
import "../contracts/Controller.sol";
import "../node_modules/@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./Addresses.sol";

 
abstract contract HasFunds is Test {
  address internal constant WETH9 = Addresses.WETH;
  ERC20 internal constant weth = ERC20(Addresses.WETH);
  address internal constant USD = Addresses.USD;
  ERC20 internal constant usd = ERC20(Addresses.USD);
  
  
  function get_funds() internal {
    //address _sender = msg.sender;
    vm.prank(Addresses.MUCH_USD);
    usd.transfer(address(this), 5_000_000e18);
    vm.prank(Addresses.MUCH_WETH);
    weth.transfer(address(this), 10_000e18);
  }
}


abstract contract Oracle_Deployment {
  Oracle public testOracle;
  
  constructor () {
    address[] memory assets = new address[](1);
    assets[0] = Addresses.WETH;
    address[] memory chainlinks = new address[](1);
    chainlinks[0] = Addresses.WETH_USD_CHAINLINK_FEED;
    testOracle = new Oracle(assets, chainlinks, address(0x0), Addresses.USD, 1e8, 5e6);
  }
}


abstract contract Core_Deployment is Oracle_Deployment {
  Controller public controller;
  Referrals public referrals;
  
  constructor () {
    referrals = new Referrals();
    PositionManager positionManager = new PositionManager();
    controller = new Controller(address(testOracle), Addresses.WETH, address(referrals), Addresses.TREASURY, address(positionManager));
  }
}


abstract contract PositionManager_Deployment {
  PositionManager public pmImplementation;
  UpgradeableBeacon public pmUpgradeableBeacon;
  PositionManager public pm;

  constructor() {
    pmImplementation = new PositionManager();
    pmUpgradeableBeacon = new UpgradeableBeacon(address(pmImplementation));
    BeaconProxy pmbp = new BeaconProxy(address(pmUpgradeableBeacon), "");
    pm = PositionManager(address(pmbp));
  }
}



