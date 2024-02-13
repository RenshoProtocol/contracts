// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../contracts/Oracle/Oracle.sol";
import "../node_modules/@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../node_modules/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "./Addresses.sol";

contract Test_Oracle is Test {
  Oracle private oracle;
  
  int256 private constant RFR = 5e6;
  int256 public latestAnswer = 1e8;
  address constant USD = Addresses.USD;
  
  /// @notice Deploy a regular oracle, and add address(this) as another asset source, which answer we can easily manipulate
  function deploy_oracle() private {
    address[] memory assets = new address[](2);
    assets[0] = Addresses.WETH;
    assets[1] = address(this);
    address[] memory pricefeeds = new address[](2);
    pricefeeds[0] = Addresses.WETH_USD_CHAINLINK_FEED;
    pricefeeds[1] = address(this);
    oracle = new Oracle(assets, pricefeeds, address(0x0), Addresses.USD, 1e8, RFR);
  }
  
  function test_Initializer() public {
    address[] memory assets0 = new address[](0);
    address[] memory assets = new address[](2);
    assets[0] = Addresses.WETH;
    assets[1] = address(this);
    address[] memory chainlinks0 = new address[](0);
    address[] memory chainlinks = new address[](2);
    chainlinks[0] = Addresses.WETH_USD_CHAINLINK_FEED;
    chainlinks[1] = address(this);
    Oracle oracleCode = new Oracle(assets0, chainlinks0, address(0x0), Addresses.USD, 1e8, 45e5);
    UpgradeableBeacon oracleUpgradeableBeacon = new UpgradeableBeacon(address(oracleCode));
    oracle = Oracle(address(new BeaconProxy(address(oracleUpgradeableBeacon), "")));
    oracle.initializer(assets, chainlinks, Addresses.USD, 1e8, 45e5);
    assertEq(oracle.owner(), address(this));
    assertEq(oracle.getSourceOfAsset(Addresses.WETH), Addresses.WETH_USD_CHAINLINK_FEED);
  }
  
  
  function test_SingleAsset() public {
    address[] memory assets = new address[](1);
    assets[0] = Addresses.USD;
    address[] memory pricefeeds = new address[](1);
    pricefeeds[0] = Addresses.WETH_USD_CHAINLINK_FEED;
    oracle = new Oracle(assets, pricefeeds, address(0x0), Addresses.USD, 1e8, RFR);
    
    oracle.getAssetPrice(Addresses.USD);
    
    assertEq(oracle.getRiskFreeRate(), RFR);
    oracle.setRiskFreeRate(RFR * 2);
    assertEq(oracle.getRiskFreeRate(), RFR * 2);
    
    // add a fallback oracle
    assets[0] = Addresses.WETH;
    pricefeeds[0] = Addresses.WETH_USD_CHAINLINK_FEED;
    Oracle geo = new Oracle(assets, pricefeeds, address(0x0), Addresses.USD, 1e8, RFR);
    oracle.setFallbackOracle(address(geo));
    // oracle should use fallback to get ARB price
    assertGt(oracle.getAssetPrice(Addresses.WETH), 0);
    
    oracle.setIVMultiplier(120);
    assertEq(oracle.getIVMultiplier(), 120);
  }

  
  function test_Volatility() public {
    _test_Volatility();
  }
  function _test_Volatility() internal {
    deploy_oracle();
    
    // check that basic functions are working out of the box
    // oracle.getOptionPrice(true, Addresses.ARB, Addresses.USD, 1e8, 3600, 0) ;
    
    _update_next_oracle_value(1);
    // saves prices as increasing by 1 daily over a few days
    for(uint k = 0; k < 10; k++){
      _update_next_oracle_value(k+1);
      assertEq(uint(latestAnswer), oracle.getAssetPriceAtDay(address(this), block.timestamp / 86400));
      // go forward 1 day
    }
    uint volatility;
    volatility = oracle.getAssetVolatility(address(this), 0);
    assertEq(volatility, 0);
    volatility = oracle.getAssetVolatility(address(this), 10);
    // annualized vol over 365d for a serie [1, 10] is 3.75
    assertApproxEqAbs(volatility, 375000000, 1e6);
  }
  
  
  function test_OptionPrices() public {
    // set volatility to known values
    _test_Volatility();
    
    // current price is 10e8, volatility 375% * 135 = 506.25% (IV calculation), rfr 5% 
    uint priceX8 = oracle.getAssetPrice(address(this)) * 1e8 / oracle.getAssetPrice(USD);
    
    // very very OTM option price should be min == 0.01e6
    uint op = oracle.getOptionPrice(true, address(this), USD, 1e15, 86400, 0);
    assertEq(op, 1e6);
    op = oracle.getOptionPrice(false, address(this), USD, 1, 86400, 0);
    assertEq(op, 1e6);
    
    // 1 dte call/put $1.05 = 105e6
    op = oracle.getOptionPrice(true, address(this), USD, priceX8, 86400, 0);
    assertApproxEqAbs(op, 105e6, 1e6);
    op = oracle.getOptionPrice(false, address(this), USD, priceX8, 86400, 0);
    assertApproxEqAbs(op, 105e6, 1e6);
    
    // strike 9e8, call: $1.58 put $0.58
    op = oracle.getOptionPrice(true, address(this), USD, 9e8, 86400, 0);
    assertApproxEqAbs(op, 158e6, 1e6);
    op = oracle.getOptionPrice(false, address(this), USD, 9e8, 86400, 0);
    assertApproxEqAbs(op, 58e6, 1e6);
    
    // strike 12e8, call $0.42, put $2.42
    op = oracle.getOptionPrice(true, address(this), USD, 12e8, 86400, 0);
    assertApproxEqAbs(op, 42e6, 1e6);
    op = oracle.getOptionPrice(false, address(this), USD, 12e8, 86400, 0);
    assertApproxEqAbs(op, 242e6, 1e6);
    
    _update_next_oracle_value(10);
    _update_next_oracle_value(10);
    _update_next_oracle_value(10);
    _update_next_oracle_value(10);
    _update_next_oracle_value(10);
    // HV is now 145%, IV 195
    
    // strike 11e8, call $0.10, put $1.10
    op = oracle.getOptionPrice(true, address(this), USD, 11e8, 86400, 0);
    assertApproxEqAbs(op,   10e6, 1e6);
    op = oracle.getOptionPrice(false, address(this), USD, 11e8, 86400, 0);
    assertApproxEqAbs(op, 110e6, 1e6);
    
    // push utilization rate to 100%: adjusts vol up check oracle code, last adjustment at +33.3%, check prices call $0.20 put $1.20
    op = oracle.getOptionPrice(true, address(this), USD, 11e8, 86400, 100);
    assertApproxEqAbs(op,  20e6, 1e6);
    op = oracle.getOptionPrice(false, address(this), USD, 11e8, 86400, 100);
    assertApproxEqAbs(op, 120e6, 1e6);
  }
  
  
  // Update local oracle with a new value, skip 1 day and snapshot
  function _update_next_oracle_value(uint value) internal {
    skip(86400);
    address[] memory assets = new address[](1);
    assets[0] = address(this);
    latestAnswer = int(value) * 1e8;
    oracle.snapshotDailyAssetsPrices(assets);
  }
}