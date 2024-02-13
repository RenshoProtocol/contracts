// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "./Deployments.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";


/**
 * @dev Test PositionManager: Test contract acts as a vault to make/receive calls to/from PositionManager
 */
contract Test_PositionManager is Test, HasFunds, Oracle_Deployment, VaultBase {

  // Used for calls to Core
  address public treasury = Addresses.TREASURY;
  uint8 public treasuryShare = 20;
  Referrals internal referrals;
  int public latestAnswer; // WETH price to manipulate oracle, shoul
  
  constructor() {
    baseToken = ERC20(WETH9);
    quoteToken = ERC20(usd);
    WETH = IWETH(WETH9);
    oracle = testOracle;
    latestAnswer = int(oracle.getAssetPrice(WETH9));
    referrals = new Referrals();
    PositionManager pm = new PositionManager();
    controller = IController(new Controller(address(testOracle), Addresses.WETH, address(referrals), Addresses.TREASURY, address(pm)));
    controller.setTreasury(Addresses.TREASURY, 20);
  }  
  
  
  // Update local oracle with a new value, skip 1 day and snapshot
  function _update_next_oracle_value(int value) internal {
    skip(86400);
    address[] memory assets = new address[](1);
    assets[0] = Addresses.WETH;
    latestAnswer = latestAnswer + value;
    oracle.snapshotDailyAssetsPrices(assets);
  }

  function _seed_oracle() internal {
    // replace ETH oracle by address(this) to manipulate ETH price
    address[] memory assets = new address[](1);
    assets[0] = Addresses.WETH;
    address[] memory pricefeeds = new address[](1);
    pricefeeds[0] = address(this);
    testOracle.setAssetSources(assets, pricefeeds);
    // seed oracle with price volatility, while still matching pool price
    for(uint k = 0; k < 10; k++) _update_next_oracle_value( ((-1)**k) * 1e8);
  }
  
  // Create the PM and allow token transfers
  function _prepare_pm() internal {
    get_funds();
    _seed_oracle();
    positionManager = PositionManager(address(new PositionManager()));
    positionManager.initProxy(address(testOracle), WETH9, USD, address(this), address(referrals));
    weth.approve(address(positionManager), 2**256-1);
    usd.approve(address(positionManager), 2**256-1);
    
    string memory name = string(abi.encodePacked("Rensho Positions ", ERC20(baseToken).symbol(), "-", ERC20(quoteToken).symbol()));
    assertEq(name, positionManager.name());
    console.log(name, positionManager.name());
    string memory symbol = "Good-Trade";
    assertEq(symbol, positionManager.symbol());
    console.log(symbol, positionManager.symbol());
  }
  
  
  function test_Calls() public {
    _prepare_pm();
    
    vm.expectRevert("PM: Already Init");
    positionManager.initProxy(address(testOracle), WETH9, USD, address(this), address(referrals));
    
    // There are no positions
    assertEq(positionManager.totalSupply(), 0);
    // There is 1 dummy open strike at 0
    assertEq(positionManager.getOpenStrikesLength(), 1);
    
    bool isCall = true;
    uint callStrike = StrikeManager.getStrikeAbove(getBasePrice());

    vm.expectRevert("GEP: Min Duration");
    positionManager.openFixedPosition(isCall, callStrike, 1000e18, 86400 / 3);
    vm.expectRevert("GEP: Max Duration");
    positionManager.openFixedPosition(isCall, callStrike, 1000e18, 86400 * 11);

    vm.expectRevert("GEP: Not OTM");
    positionManager.openFixedPosition(!isCall, callStrike, 1000e18, 86400);
    vm.expectRevert("GEP: Invalid Strike");
    positionManager.openFixedPosition(isCall, 10001, 1000e18, 86400);

    (uint minPositionSize,,,,,,,,) = positionManager.getParameters();
    uint callSize = minPositionSize / 2 * 1e18 / oracle.getAssetPrice(WETH9);
    console.log('call size %s %s', callSize, minPositionSize);
    vm.expectRevert("GEP: Min Size Error");
    positionManager.openFixedPosition(isCall, callStrike, callSize, 86400); // 25 usd
    console.log('msdf %s %s', minPositionSize, minPositionSize / 200);
    vm.expectRevert("GEP: Min Size Error");
    positionManager.openFixedPosition(!isCall, callStrike - 100e8, minPositionSize / 200, 86400); // 25 usd
    
    
    uint baseTokenBalance = baseToken.balanceOf(address(this));
    vm.expectRevert("GEP: Max OI Reached");
    positionManager.openFixedPosition(isCall, callStrike, baseTokenBalance * 61 / 100, 86400); //  open >60% of the vault baseToken
    // higher utilization rate should make the larger notional option more expensive
    assertGt(positionManager.getOptionPrice(true, callStrike, 1000e18, 86400), positionManager.getOptionPrice(true, callStrike, 1e18, 86400));
    uint notionalSize = 1e18;
    console.log("option prices %s %s", positionManager.getOptionPrice(true, callStrike, 1000e18, 86400), positionManager.getOptionPrice(true, callStrike, 1e18, 86400));

    vm.expectRevert("GEP: Strike too far OTM");
    positionManager.openFixedPosition(isCall, callStrike * 2, notionalSize, 86400);
    
    uint callId = positionManager.openFixedPosition(isCall, callStrike, notionalSize, 86400);
    {
      (uint baseDue, uint quoteDue) = positionManager.getAssetsDue();
      assertEq(baseDue, notionalSize);
      assertEq(quoteDue, 0);
    }
    // Check balances moved accordingly
    assertEq(weth.balanceOf(address(positionManager)), notionalSize, "Wrong notional amount moved");

    // Check utilization rate change
    uint utilizationRate = positionManager.getUtilizationRate(isCall, 0);
    uint rateShouldBe = positionManager.strikeToOpenInterestCalls(callStrike) * 1e8 / weth.balanceOf(address(this));

    assertEq(positionManager.totalSupply(), 1, "Wrong position length");
    assertEq(positionManager.balanceOf(address(this)), 1, "Wrong user bal");
    assertEq(positionManager.getOpenStrikesLength(), 2, "Wrong openStrikes length");
    
    // 3rd party cant close it early
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("GEP: Invalid Close");
    positionManager.closePosition(callId);
    vm.stopPrank();
    
    // Skip until expiry duration.
    skip(86400);
    IPositionManager.Position memory pos = positionManager.getPosition(callId);
    // check check details
    
    positionManager.closePosition(callId);
    // check that both tokens are properly removed from the PM
    assertEq(0, usd.balanceOf(address(positionManager)));
    assertEq(0, weth.balanceOf(address(positionManager)));
    // Position doesnt exist anymore
    vm.expectRevert("ERC721: invalid token ID");
    positionManager.closePosition(callId);
    
    // test option price
    callId = positionManager.openFixedPosition(isCall, callStrike, notionalSize, 86400);
    uint collateralusd = usd.balanceOf(address(positionManager));
    positionManager.closePosition(callId);
    
    callId = positionManager.openFixedPosition(isCall, callStrike, 2 * notionalSize, 86400);
    // collatearl = premium + fixed fee, so here add 4e6 since
    assertGe(usd.balanceOf(address(positionManager)) + 4e6, 2 * collateralusd);
  }
  
  
  function test_Puts() public {
    _prepare_pm();
    
    bool isCall = true;
    uint putStrike = StrikeManager.getStrikeStrictlyBelow(getBasePrice());
    uint halfStrike = StrikeManager.getStrikeBelow(putStrike / 2);
    vm.expectRevert("GEP: Not OTM");
    positionManager.openFixedPosition(isCall, putStrike, 1e18, 86400);
    vm.expectRevert("GEP: Strike too far OTM");
    positionManager.openFixedPosition(!isCall, halfStrike, 1e18, 86400);
    
    uint putPrice = positionManager.getOptionPrice(false, putStrike, 1000e6, 86400);
    uint putId = positionManager.openFixedPosition(!isCall, putStrike, 1000e6, 86400);
    (uint baseDue, uint quoteDue) = positionManager.getAssetsDue();
    assertEq(baseDue, 0);
    assertEq(quoteDue, 1000e6);
    
    vm.expectRevert("GEP: Not Streaming Option");
    positionManager.increaseCollateral(putId, 10e6);
    
    positionManager.closePosition(putId);
    // check that both tokens are properly removed from the PM
    assertEq(0, usd.balanceOf(address(positionManager)));
    assertEq(0, weth.balanceOf(address(positionManager)));
    
    // Test closing as 3rd party
    uint putId2 = positionManager.openFixedPosition(!isCall, putStrike, 1000e6, 86400);
    skip(86400);
    // close position as 3rd party after it expires
    vm.prank(Addresses.RANDOM);
    positionManager.closePosition(putId2);
    assertEq(usd.balanceOf(Addresses.RANDOM), 2e6);
    // check that both tokens are properly removed from the PM
    assertEq(0, usd.balanceOf(address(positionManager)));
    assertEq(0, weth.balanceOf(address(positionManager)));
  }
  
  
  function test_StreamingOptions() public {
    _prepare_pm();
    
    uint callId = positionManager.openStreamingPosition(true, 1e18, 1e6);
    positionManager.increaseCollateral(callId, 1e6);
    IPositionManager.Position memory pos = positionManager.getPosition(callId);

    // colateral should be 1e6 + 1e6 + 4e6 (fixed exercise fee + twice 1e6)
    assertEq(6e6, pos.collateralAmount, "Wrong Result inc. collateral");
    
    // Check getFeesAccumulatedAndMin: feesAcc should still be 0, but minFees should not
    (uint feesAcc, uint feesMin) = positionManager.getFeesAccumulatedAndMin(callId);
    console.log('fees duemin', feesAcc, feesMin);
    assertEq(feesAcc, 0);
    assertGt(feesMin, 0);
    
    uint putId = positionManager.openStreamingPosition(false, 1000e6, 1e6);
    pos = positionManager.getPosition(putId);

    string memory tokenURI = positionManager.tokenURI(putId);
    skip(8640000);
    // close position as 3rd party after it expires
    vm.prank(Addresses.RANDOM);
    positionManager.closePosition(callId);
    assertEq(usd.balanceOf(Addresses.RANDOM), 2e6, "Wrong liquidator bal");
    positionManager.closePosition(putId);
  }
  
  
  // Test emergency function where far OTM options can be closed if the number of open strikes exceeds a treshold
  function test_Emergency() public {
    _prepare_pm();
    
    uint basePrice = getBasePrice();
    uint callStrike = StrikeManager.getStrikeStrictlyAbove(basePrice);
    (uint minPositionSize,,,,,,,,) = positionManager.getParameters();
    uint notionalValue = minPositionSize * 101e16 / testOracle.getAssetPrice(WETH9);
    uint callId0 = positionManager.openFixedPosition(true, callStrike, notionalValue, 86400);
    uint callId;
    uint gl;
    for (uint k = 0; k < 250; k++){
      callStrike = StrikeManager.getStrikeStrictlyAbove(callStrike);
      callId = positionManager.openFixedPosition(true, callStrike, notionalValue, 86400);
      // need to push price up a bit or eventually we're too far OTM
      latestAnswer = int(callStrike);
    }
    uint len = positionManager.getOpenStrikesLength();
    assertGt(len, 202);
    // check gas for all OTM
    gl = gasleft();
    (uint baseAmount, uint quoteAmount) = positionManager.getAssetsDue();
    // move price up to last strike
    int prevAnswer = latestAnswer;
    latestAnswer = int(callStrike);
    gl = gasleft();
    (baseAmount, quoteAmount) = positionManager.getAssetsDue();
    // revert
    latestAnswer = prevAnswer;
    
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("GEP: Invalid Close");
    positionManager.closePosition(100); // random one in the middle, isnt most OTM
    
    positionManager.closePosition(callId0);
    assertEq(positionManager.getOpenStrikesLength(), len - 1);
    
    positionManager.closePosition(1); // next furthest out in line for liquidation
    assertEq(positionManager.getOpenStrikesLength(), len - 2);
    
    vm.stopPrank();
  }
  
  
  // Test ITM option close
  function test_ItmClose() public {
    _prepare_pm();
    
    uint putStrike = StrikeManager.getStrikeBelow(getBasePrice());
    // use putStrike as size in usd
    uint putId = positionManager.openFixedPosition(false, putStrike, putStrike / 100, 86400);
    
    _manipulatePoolPrice(true);
    
    // transfer to user so easy to check pnl result
    positionManager.transferFrom(address(this), Addresses.RANDOM,  putId);
    assertEq(Addresses.RANDOM,  positionManager.ownerOf(putId));
    
    skip(86400);
    positionManager.closePosition(putId);
    // position is closed and all collateral spent + fixed fee distributed, pnl should be exactly the price difference
    uint pnl = usd.balanceOf(Addresses.RANDOM);
    // pnl should be the difference between strike and current price (pnl is in usd e6 while price is X8)
    assertEq(pnl, (putStrike - uint(latestAnswer)) / 100);
    
    // Test call
    uint callStrike = StrikeManager.getStrikeAbove(getBasePrice());
    // use putStrike as size in usd
    uint callId = positionManager.openFixedPosition(true, callStrike, 1e18, 86400);
    
    _manipulatePoolPrice(false);
    // transfer to user so easy to check pnl result
    positionManager.transferFrom(address(this), Addresses.RANDOM,  callId);
    assertEq(Addresses.RANDOM,  positionManager.ownerOf(callId));
    
    skip(86400);
    positionManager.closePosition(callId);
    // position is closed and all collateral spent + fixed fee distributed, pnl should be exactly the price difference
    pnl = weth.balanceOf(Addresses.RANDOM);
    // pnl should be the difference between strike and current price
    assertEq(pnl / 1e10, (uint(latestAnswer) - callStrike) * 1e8 / uint(latestAnswer));
  }
  
  
  // Manipulate pool price: swap a bunch to move price then record here as oracel price so no oracle error. 
  // can then check ITM option expiry
  function _manipulatePoolPrice(bool pushDown) internal returns (uint priceX8){
    // prepare big swap
    ISwapRouter router = ISwapRouter(Addresses.UNISWAP_ROUTER_V3);
    usd.approve(address(router), 2**256-1);
    weth.approve(address(router), 2**256-1);
    console.log('swapbals eth %s usd %s', weth.balanceOf(address(this)),  usd.balanceOf(address(this)));
    if (pushDown)
      router.exactInputSingle(
        ISwapRouter.ExactInputSingleParams(WETH9, USD, 500, msg.sender, block.timestamp, 3000e18, 100e6, 0)
      );
    else
      router.exactInputSingle(
        ISwapRouter.ExactInputSingleParams(USD, WETH9, 500, msg.sender, block.timestamp, 2_000_000e6, 100e6, 0)
      );
  
    // ETH pool
    IUniswapV3Pool uniswapPool = IUniswapV3Pool(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    (uint160 sqrtPriceX96,,,,,,) = uniswapPool.slot0();
    uint256 Q96 = 0x1000000000000000000000000;
    
    uint token0Decimals = ERC20(baseToken).decimals();
    uint token1Decimals = ERC20(quoteToken).decimals();

    // Based on https://github.com/rysk-finance/dynamic-hedging/blob/HOTFIX-14-08-23/packages/contracts/contracts/vendor/uniswap/RangeOrderUtils.sol
    uint256 sqrtPrice = uint256(sqrtPriceX96);
    if (sqrtPrice > Q96) {
        uint256 sqrtP = FullMath.mulDiv(sqrtPrice, 10 ** token0Decimals, Q96);
        priceX8 = FullMath.mulDiv(sqrtP, sqrtP, 10 ** token0Decimals);
    } else {
        uint256 numerator1 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1);
        uint256 numerator2 = 10 ** token0Decimals;
        priceX8 = FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }
    
    priceX8 = priceX8 * 10**8 / 10**token1Decimals;
    // set oracle price to manipulated price
    latestAnswer = int(priceX8);
  }
  
  
  function test_OptionCost() public {
    _prepare_pm();
    bool isCall = true;
    
    uint callStrike = StrikeManager.getStrikeStrictlyAbove(getBasePrice());
    uint price = positionManager.getOptionPrice(isCall, callStrike, 1e18, 86400);
    uint cost = positionManager.getOptionCost(isCall, callStrike, 1e18, 86400);
    uint cost2 = positionManager.getOptionCost(isCall, callStrike, 2e18, 86400);
    // price is USD x8, here cost is usd so X6
    assertEq(cost, price / 100);
    // cost for 2 options should be double price for 1 (+utilization rate but here very low, check its within 1%)
    assertApproxEqAbs(cost2, 2 * price / 100, 2 * price / 10000);
    
    uint putStrike = StrikeManager.getStrikeStrictlyBelow(getBasePrice());
    uint putSizeusd = putStrike / 100;
    // use putStrike div 100 to get the amonut in usd, so notional amount should be 1 ETH
    console.log('- cost for strike %s', putStrike);
    price = positionManager.getOptionPrice(!isCall, putStrike, putSizeusd, 86400);
    cost = positionManager.getOptionCost(!isCall, putStrike, putSizeusd, 86400);
    cost2 = positionManager.getOptionCost(!isCall, putStrike,  2 *putSizeusd, 86400);
    console.log('- price');
    console.log('cost %s price %s', cost, price);
    // price is USD x8, here cost is usd so X6
    assertEq(cost, price / 100);
    assertApproxEqAbs(cost2, 2 * price / 100, 2 * price / 10000);
  }
  
  
  // Test amount of strikes that can be open is within limits, check for various latest ETH prices
  // Will revert if maxStrikeDistanceX2 and MAX_OPEN_STRIKES conflict
  function test_MaxStrikeDistance0() public {
    _test_MaxStrikeDistance();
  }
  function test_MaxStrikeDistance1() public {
    latestAnswer = latestAnswer * 3 / 4;
    _test_MaxStrikeDistance();
  }
  function test_MaxStrikeDistance2() public {
    latestAnswer = latestAnswer * 5 / 4;
    _test_MaxStrikeDistance();
  }
  
  
  function _test_MaxStrikeDistance() internal {
    _prepare_pm();
    uint currentPrice = uint(latestAnswer);
    // require 100 * strikeDistance / basePrice <= maxStrikeDistanceX2
    (uint minPositionSize,,,,,,,uint8 maxStrikeDistanceX2,) = positionManager.getParameters();
    uint maxDistance = uint(maxStrikeDistanceX2) * currentPrice / 100;
    uint counter = 0;
    // lowest valid strike 
    uint strikeLow = StrikeManager.getStrikeStrictlyAbove(currentPrice - maxDistance);
    // highest valid strike
    uint strikeHigh = StrikeManager.getStrikeStrictlyBelow(currentPrice + maxDistance);
    
    uint strike = strikeLow;
    // check that after opening all valid strikes, still below the MAX_OPEN_STRIKES limit, ie we can concurrently open all
    while(strike < strikeHigh){
      bool isCall = strike < currentPrice ? false : true;
      uint size = isCall ? 1e17 : 100e6;
      
      positionManager.openFixedPosition(
        isCall,
        strike,
        size,
        86400
      );
      counter++;
      strike = StrikeManager.getStrikeStrictlyAbove(strike);
    }
    console.log('opened pos %s', counter);
  }
}
