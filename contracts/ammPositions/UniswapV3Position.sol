// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


import "../../interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../lib/Uniswap/TickMath.sol";
import "../lib/Uniswap/LiquidityAmounts.sol";
import "./AmmPositionBase.sol";


abstract contract UniswapV3Position is AmmPositionBase {
  /// Uni v3 position parameters
  /// @notice Uni v3 pool parameters
  int24 internal lowerTick;
  int24 internal upperTick;
  uint256 internal tokenId;
  /// @notice Fee tier
  uint24 internal feeTier;
  
  // These are constant across chains - https://docs.uniswap.org/protocol/reference/deployments
  INonfungiblePositionManager private constant _nonFungiblePositionManager = INonfungiblePositionManager(0xa4b568bCdeD46bB8F84148fcccdeA37e262A3848);
  IUniswapV3Factory private constant uniswapV3Factory = IUniswapV3Factory(0xbAB2F66B5B3Be3cC158E3aC1007A8DF0bA5d67F4);
  
  /// @notice Return nonFungiblePositionManager contract
  function nonFungiblePositionManager() internal pure virtual returns (address){
    return address(_nonFungiblePositionManager);
  }
  
  
  /// @notice Additional initialization tasks
  function initTicks(uint24 _feeTier) internal virtual {
    feeTier = _feeTier;
    upperTick = TickMath.MAX_TICK - TickMath.MAX_TICK % int24(_feeTier);
    lowerTick = -upperTick;
  }
  
  
  /// @notice Claim the accumulated Uniswap V3 trading fees and send partially to treasury partially to vault
  function claimFees() internal virtual returns (uint baseAmount, uint quoteAmount) {
    if(tokenId == 0) return (0, 0);
    (uint fee0, uint fee1) = INonfungiblePositionManager(nonFungiblePositionManager()).collect( 
      INonfungiblePositionManager.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: UINT128MAX,
        amount1Max: UINT128MAX
      })
    );
    (baseAmount, quoteAmount) = baseToken < quoteToken ? (fee0, fee1) : (fee1, fee0);
    if (baseAmount + quoteAmount > 0){
      _afterClaimFees(baseAmount, quoteAmount);
      baseFees += baseAmount;
      quoteFees += quoteAmount;
      emit ClaimFees(baseAmount, quoteAmount);
    }
  }
  
  
  /// @notice Withdraw assets from the ticker
  function withdrawAmm() internal virtual override returns (uint baseAmount, uint quoteAmount) {
    if(tokenId == 0) return (0, 0);
    require(poolPriceMatchesOracle(), "TR: Oracle Price Mismatch");
    claimFees();
    (uint removed0, uint removed1) = INonfungiblePositionManager(nonFungiblePositionManager()).decreaseLiquidity(
      INonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: getLiquidity(),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    if (removed0 > 0 || removed1 > 0){
      INonfungiblePositionManager(nonFungiblePositionManager()).collect( 
        INonfungiblePositionManager.CollectParams({
          tokenId: tokenId,
          recipient: address(this),
          amount0Max: uint128(removed0),
          amount1Max: uint128(removed1)
        })
      );
    }
    (baseAmount,  quoteAmount) = baseToken < quoteToken ? (removed0, removed1) : (removed1, removed0);
  }
  
  
  /// @notice Deposit assets
  function depositAmm(uint256 baseAmount, uint256 quoteAmount) internal virtual override returns (uint256 newLiquidity) {
    claimFees();
    checkSetApprove(address(baseToken), address(nonFungiblePositionManager()), baseAmount);
    checkSetApprove(address(quoteToken), address(nonFungiblePositionManager()), quoteAmount);

    // New liquidity is indeed the amount of liquidity added, not the total, despite being unclear in Uniswap doc
    if (tokenId > 0){
      (uint128 nl,,) = INonfungiblePositionManager(nonFungiblePositionManager()).increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams({
          tokenId: tokenId,
          amount0Desired: baseToken < quoteToken ? baseAmount : quoteAmount,
          amount1Desired: baseToken < quoteToken ? quoteAmount : baseAmount,
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp
        })
      );
      newLiquidity = uint(nl);
    } else
      (tokenId, newLiquidity) = _mint(baseToken < quoteToken ? baseAmount : quoteAmount, baseToken < quoteToken ? quoteAmount : baseAmount);
  }
  
  /// @notice Mint function, separated as overriden by Algebra
  function _mint(uint amount0Desired, uint amount1Desired) internal virtual returns (uint _tokenId, uint newLiquidity){
    (address token0, address token1) = getTokenAddresses();
    (_tokenId, newLiquidity,,) = INonfungiblePositionManager(nonFungiblePositionManager()).mint( 
      INonfungiblePositionManager.MintParams({
        token0: token0,
        token1: token1,
        fee: feeTier * 100,
        tickLower: lowerTick,
        tickUpper: upperTick,
        amount0Desired: amount0Desired,
        amount1Desired: amount1Desired,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp
      })
    );
  }

  
  // @notice Get position liquidity
  function getLiquidity() internal virtual view returns (uint128 liquidity) {
    if (tokenId > 0) (,,,,,,, liquidity,,,,) = INonfungiblePositionManager(nonFungiblePositionManager()).positions(tokenId);
  }
  
  
  /// @notice Callback after fees are claimed, eg reserve fees
  function _afterClaimFees(uint baseAmount, uint quoteAmount) internal virtual {}
  
  /// @notice Get ammType, for naming and tracking purposes
  function ammType() public pure virtual override returns (bytes32 _ammType){
    _ammType = "UniswapV3-0.05";
  }
  
  /// @notice Return token0 and token1 for pool interactions
  function getTokenAddresses() internal view returns (address token0, address token1) {
    (token0, token1) = baseToken < quoteToken ? (address(baseToken), address(quoteToken)) : (address(quoteToken),  address(baseToken));
  }
  
  
  /// @notice Get the AMM position underlying tokens amounts
  function _getReserves() internal override view returns (uint baseAmount, uint quoteAmount){
    uint token0Amount; uint token1Amount;
    uint128 liquidity = uint128(getLiquidity());
    if (liquidity > 0){
      uint160 sqrtPriceX96 = _sqrtPriceX96();
      (token0Amount, token1Amount) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(upperTick),  liquidity);
    }
    (baseAmount, quoteAmount) = baseToken < quoteToken ? (token0Amount, token1Amount) : (token1Amount, token0Amount);
  }
  
  
  /// @notice Returns the sqrtPriceX96 of the underlying Uniswap pool, used for calculation and comparison with oracle
  function _sqrtPriceX96() internal virtual view returns (uint160 sqrtPriceX96){
    (address token0, address token1) = getTokenAddresses();
    address pool = uniswapV3Factory.getPool(token0, token1, feeTier * 100);
    (sqrtPriceX96,,,,,,)  = IUniswapV3Pool(pool).slot0();
  }
}


