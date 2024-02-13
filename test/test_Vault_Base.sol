// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "./Deployments.sol";


contract Test_GeVault_Base is Test, HasFunds, Oracle_Deployment, PositionManager_Deployment {
  VaultBase public vault;
  Referrals public referrals;

  receive() external payable {}
  // Used for calls to Core
  address public treasury = Addresses.TREASURY;
  uint8 public treasuryShareX2 = 20;
  bool public isPaused;


  function deploy_vault(address baseToken, address quoteToken) internal {
    vault = new VaultBase();
    referrals = new Referrals();
    ERC20(quoteToken).approve(address(pm), 2**256-1); // approve transferFrom when opening positions
    pm.initProxy(address(testOracle), baseToken, quoteToken, address(vault), address(referrals));
    vault.initProxy(baseToken, quoteToken, address(pm), WETH9, address(testOracle));
    string memory name = string(abi.encodePacked("Rensho ", ERC20(baseToken).symbol(), "-", ERC20(quoteToken).symbol()));
    assertEq(name, vault.name());
    string memory symbol = "Good-LP";
    assertEq(symbol, vault.symbol());
    bytes32 ammType = "";
    assertEq(ammType, vault.ammType());
  }


  function test_Base_DepositWithdrawTokens() public {
    deploy_vault(WETH9, USD);
    get_funds();
    
    uint basePrice = vault.getBasePrice();
    assertEq(basePrice, testOracle.getAssetPrice(WETH9) * 1e8 / testOracle.getAssetPrice(USD));
    
    vm.expectRevert("ERC20: insufficient allowance");
    vault.deposit(WETH9, 1000e18);
    weth.approve(address(vault), type(uint256).max);
    vault.setTvlCap(1e8);
    vm.expectRevert("GEV: Max Cap Reached");
    vault.deposit(WETH9, 1000e18);
    vault.setTvlCap(0);
    uint adjustedFee = vault.getAdjustedBaseFee(true);
    vm.expectRevert("GEV: Deposit Zero");
    vault.deposit(WETH9, 0);
    isPaused = true;
    vm.expectRevert("GEV: Pool Disabled");
    vault.deposit(WETH9, 1000e18);
    isPaused = false;
    vm.expectRevert("GEV: Invalid Token");
    vault.deposit(WETH9, 1000e18);
    vm.expectRevert("GEV: Invalid Weth");
    vault.deposit{value: 1e18}(WETH9, 1000e18);
    vault.deposit(WETH9, 1000e18);
    (uint amount0, uint amount1, uint tvl) = vault.getReserves();
    // Vault asset + treasury tax == amount deposited
    assertEq(1000e18, amount0 + weth.balanceOf(Addresses.TREASURY));
    assertEq(weth.balanceOf(Addresses.TREASURY), 1000e18 * adjustedFee / 1e4);
    //assertEq(vault.latestAnswer() * vault.totalSupply() / 1e18, amount0 * testOracle.getAssetPrice(WETH) / 1e18);
    (,,uint vaultValueX8) = vault.getReserves();
    assertEq(tvl, vaultValueX8);
    // Deposit USD, now both assets in the pool, should create the full range and deposit X% of min(WETH9 value, USD value) there
    usd.approve(address(vault), type(uint256).max);
    vault.deposit(USD, 2000e6);
    vault.deposit(USD, 4000e6);
    (amount0, amount1) = vault.getAmmAmounts();
    uint rangeValue = amount0 * testOracle.getAssetPrice(WETH9) / 10**weth.decimals() + amount1 * testOracle.getAssetPrice(USD) / 10**usd.decimals();
    uint WETH9Value = 1000e18 * testOracle.getAssetPrice(WETH9) / 5;
    uint USDValue = 2000e6 * testOracle.getAssetPrice(USD) / 5;
    // USD adjusted fees should be higher since currently USD price > 2 * WETH9 price and adjusted fees should be capped at 150% of basefee
    assertEq(vault.getAdjustedBaseFee(false), vault.baseFeeX4() * 3 / 2);
    assertEq(vault.getAdjustedBaseFee( true), vault.baseFeeX4() * 1 / 2);
    
    uint bal = vault.balanceOf(address(this));
    vm.expectRevert("GEV: Insufficient Balance");
    vault.withdraw(bal * 2, WETH9);
    
    vm.expectRevert("GEV: Invalid Token");
    vault.withdraw(bal, WETH9);
    vm.prank(Addresses.RANDOM);
    vault.withdraw(0, WETH9);
    uint bal10 = vault.balanceOf(address(this)) / 10;
    vault.withdraw(vault.balanceOf(address(this)) / 10, WETH9);
    vault.withdraw(vault.balanceOf(address(this)) / 10, USD);
    
    // open/close positions
    vm.expectRevert("GEV: Unallowed PM");
    vault.borrow(WETH9, 1e28);
    vm.expectRevert("GEP: Max OI Reached");
    pm.openStreamingPosition(true, 10e28, 10e6);

    uint tokenId = pm.openStreamingPosition(true, 100e18, 10e6);
    skip(15000); // skip time so fees accumulate on streaming position
    pm.closePosition(tokenId);
    
    // open/close put option
    tokenId = pm.openStreamingPosition(false, 100e6, 10e6);
    skip(15000); // skip time so fees accumulate on streaming position
    pm.closePosition(tokenId);
    
  }

  
  
  function test_WithdrawIntents() public {
    deploy_vault(WETH9, USD);
    get_funds();

    weth.approve(address(vault), type(uint256).max);
    vault.deposit(WETH9, 1000e18);
    skip(10);

    uint callId = pm.openStreamingPosition(true, 250e18, 10e6);
    pm.openFixedPosition(true, StrikeManager.getStrikeAbove(vault.getBasePrice() * 110 / 100), 250e18, 86400);

    (uint utilizationRate, uint maxRate) = pm.getUtilizationRateStatus();
    console.log('rates %s %s', utilizationRate, maxRate);
    // withdrawal should fail by pushing Utilization rate too high
    uint bal = vault.balanceOf(address(this));
    vm.expectRevert("GEV: Utilization Rate too high");
    vault.withdraw(bal / 3, WETH9);
    // Create withdrawal intent
    vault.setWithdrawalIntent(bal/3);
    assertEq(vault.totalIntents(), bal / 3);
    // transfer resets intent
    vault.transfer(Addresses.RANDOM, 1);
    assertEq(vault.totalIntents(), 0);
    assertEq(vault.withdrawalIntents(address(this)), 0);
    vault.setWithdrawalIntent(bal/3);
    
    // Check that now the utilization rate is higher than before, making opening new positions impossible
    uint utilizationRate2 = pm.getUtilizationRate(true, 0);
    console.log('rates2 %', utilizationRate2);
    assertGt(utilizationRate2, utilizationRate);
    
    // close on of the 2 positions
    pm.closePosition(callId);
    
    utilizationRate = pm.getUtilizationRate(true, 0);
    console.log('rates %', utilizationRate);
    assertGt(utilizationRate2, utilizationRate);
    // withdraw some assets, check intent has been reset
    vault.withdraw(bal/6, WETH9);
    assertEq(vault.withdrawalIntents(address(this)), 0);
    assertEq(vault.totalIntents(), 0);
    
    
    // deposit and set intents as another user
    vm.startPrank(Addresses.MUCH_USD);
    usd.approve(address(vault), type(uint256).max);
    vault.deposit(USD, 1000e6);

    bal = vault.balanceOf(Addresses.MUCH_USD);
    vault.setWithdrawalIntent(bal / 2);

    vm.stopPrank();
    assertEq(vault.withdrawalIntents(Addresses.MUCH_USD), bal / 2);

    // check that intents are properly accounted
    usd.approve(address(vault), type(uint256).max);
    vault.deposit(USD, 1000e6);
    console.log("-r");
    vault.setWithdrawalIntent(vault.balanceOf(address(this)));
    uint intent = vault.withdrawalIntents(address(this));
    uint totalIntents = vault.totalIntents();
    vault.setWithdrawalIntent(vault.balanceOf(address(this)));
    assertEq(intent, vault.withdrawalIntents(address(this)));
    assertEq(totalIntents, vault.totalIntents());

    skip(10);
    uint balThis = vault.balanceOf(address(this)) ;
    vault.withdraw(balThis/ 4, USD);
    // check: cant withdraw on behalf of someone with no intent
    vm.startPrank(vault.owner());
    vm.expectRevert("GEV: Intent Too Low");
    vault.withdrawOnBehalf(address(this), balThis / 4, USD);
    vm.stopPrank();
    
    assertEq(vault.withdrawalIntents(Addresses.MUCH_USD), bal / 2);
    // withdraw on behalf of
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("Ownable: caller is not the owner");
    vault.withdrawOnBehalf(Addresses.MUCH_USD, bal / 2, USD);
    vm.stopPrank();
    
    vm.startPrank(vault.owner());
    vault.withdrawOnBehalf(Addresses.MUCH_USD, bal / 2, USD);
    vm.stopPrank();
  }
}