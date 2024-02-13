// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Deployments.sol";
import "./Addresses.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";



contract Test_GeVault_UniswapV3 is Test, HasFunds, Oracle_Deployment, UniswapV3Position, PositionManager_Deployment {
  VaultUniV3 public vault;
  Referrals public referrals;

  receive() external payable {}
  // Used for calls to Core
  address public treasury = Addresses.TREASURY;
  uint8 public treasuryShareX2 = 20;
  bool public isPaused;


  function deploy_vault(address baseToken, address quoteToken) internal {
    vault = new VaultUniV3();
    referrals = new Referrals();
    ERC20(quoteToken).approve(address(pm), 2**256-1); // approve transferFrom when opening positions
    pm.initProxy(address(testOracle), baseToken, quoteToken, address(vault), address(referrals));
    vault.initProxy(baseToken, quoteToken, address(pm), WETH9, address(testOracle));
    bytes32 amm = "UniswapV3-0.05";
    assertEq(amm, vault.ammType());
  }


  function test_Univ3_DepositWithdrawTokens() public {
    deploy_vault(WETH9, USD);
    get_funds();
    
    uint basePrice = vault.getBasePrice();
    assertEq(basePrice, testOracle.getAssetPrice(WETH9) * 1e8 / testOracle.getAssetPrice(USD));
    // error 0x13be252b instead of "ERC20: insufficient allowance"?
    vm.expectRevert();
    vault.deposit(WETH9, 10e18);
    weth.approve(address(vault), type(uint256).max);
    vault.setTvlCap(1e8);
    vm.expectRevert("GEV: Max Cap Reached");
    vault.deposit(WETH9, 10e18);
    vault.setTvlCap(0);
    uint adjustedFee = vault.getAdjustedBaseFee(true);
    vm.expectRevert("GEV: Deposit Zero");
    vault.deposit(WETH9, 0);
    isPaused = true;
    vm.expectRevert("GEV: Pool Disabled");
    vault.deposit(WETH9, 10e18);
    isPaused = false;
    vm.expectRevert("GEV: Invalid Token");
    vault.deposit(Addresses.RANDOM, 10e18);
    vault.deposit(WETH9, 10e18);
    (uint amount0, uint amount1, uint tvl) = vault.getReserves();
    // Vault asset + treasury tax == amount deposited
    assertEq(10e18, amount0 + weth.balanceOf(Addresses.TREASURY));
    assertEq(weth.balanceOf(Addresses.TREASURY), 10e18 * adjustedFee / 1e4);
    //assertEq(vault.latestAnswer() * vault.totalSupply() / 1e18, amount0 * testOracle.getAssetPrice(WETH9) / 1e18);
    (,,uint vaultValueX8) = vault.getReserves();
    assertEq(tvl, vaultValueX8);
    skip(10);
    vault.withdraw(1e18, WETH9);
    // Deposit USD, now both assets in the pool, should create the full range and deposit X% of min(WETH9 value, USD value) there
    usd.approve(address(vault), type(uint256).max);
    vault.deposit(USD, 2000e18);
    vault.deposit(USD, 4000e18);
    (amount0, amount1) = vault.getAmmAmounts();
    uint rangeValue = amount0 * testOracle.getAssetPrice(WETH9) / 10**weth.decimals() + amount1 * testOracle.getAssetPrice(USD) / 10**usd.decimals();

    // 10 ETH ~$20k >> $2k and adjusted fees should be capped at 150% of basefee
    assertEq(vault.getAdjustedBaseFee( true), vault.baseFeeX4() * 3 / 2);
    assertEq(vault.getAdjustedBaseFee(false), vault.baseFeeX4() * 1 / 2);
    
    uint bal = vault.balanceOf(address(this));
    vm.expectRevert("GEV: Insufficient Balance");
    vault.withdraw(bal * 2, WETH9);
    
    vm.prank(Addresses.RANDOM);
    vault.withdraw(0, WETH9);
    skip(10);
    vault.withdraw(vault.balanceOf(address(this)) / 10, WETH9);
    vault.withdraw(vault.balanceOf(address(this)) / 10, USD);
    
    // open/close positions
    vm.expectRevert("GEV: Unallowed PM");
    vault.borrow(WETH9, 1e28);
    vm.expectRevert("GEP: Max OI Reached");
    pm.openStreamingPosition(true, 10e28, 10e18);
    uint tokenId = pm.openStreamingPosition(true, 1e18, 10e18);
    skip(15000); // skip time so fees accumulate on streaming position
    pm.closePosition(tokenId);
    
    // open/close put option
    tokenId = pm.openStreamingPosition(false, 100e18, 10e18);
    skip(15000); // skip time so fees accumulate on streaming position
    pm.closePosition(tokenId);
    
  }
  
  
  function test_UniV3_SwapFees_Sandwich() public {
    deploy_vault(WETH9, USD);
    get_funds();
    weth.approve(address(vault), type(uint256).max); vault.deposit(WETH9, 10e18);
    usd.approve(address(vault), type(uint256).max); vault.deposit(USD, 1000e18);
    skip(10);

    ISwapRouter router = ISwapRouter(Addresses.UNISWAP_ROUTER_V3);
    usd.approve(address(router), 2**256-1);
    weth.approve(address(router), 2**256-1);
    uint fee0; uint fee1;
    // Swap USD -> WETH9, check claim fees USD
    router.exactInputSingle(
      ISwapRouter.ExactInputSingleParams(USD, WETH9, 500, msg.sender, block.timestamp, 10_000e18, 1000e18, 0)
    );
    vault.withdraw(1,  WETH9);
    (fee0, fee1) = vault.getPendingFees();
    assertGt(fee1, 0);
    (uint lifetimeFee0, uint lifetimeFee1) = vault.getLifetimeFees();
    uint fee1Treasury = lifetimeFee1 * treasuryShareX2 / 100;
    assertEq(fee1, lifetimeFee1 - fee1Treasury);

    // Swap WETH9 -> USD, check claim fees WETH9
    router.exactInputSingle(
      ISwapRouter.ExactInputSingleParams(WETH9, USD, 500, msg.sender, block.timestamp, 1000e18, 100e18, 0)
    );
    vault.withdraw(1,  WETH9);
    (fee0, fee1) = vault.getPendingFees();
    assertGt(fee0, 0);    
    (lifetimeFee0, lifetimeFee1) = vault.getLifetimeFees();
    uint fee0Treasury = lifetimeFee0 * treasuryShareX2 / 100;
    assertEq(fee0, lifetimeFee0 - fee0Treasury);
    
    // Large swap, price movement
    router.exactInputSingle(
      ISwapRouter.ExactInputSingleParams(WETH9, USD, 500, msg.sender, block.timestamp, 500_000e18, 100e18, 0)
    );
    assertEq(vault.poolPriceMatchesOracle(), false);

    uint bal = vault.balanceOf(address(this));
    vm.expectRevert("TR: Oracle Price Mismatch");
    vault.withdraw(bal / 2, WETH9);
  }
}