// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IAlgebraNonfungiblePositionManager.sol";
import "../../interfaces/IAlgebraFactory.sol";
import "../../interfaces/IAlgebraPool.sol";
import "./UniswapV3Position.sol";


/// @notice Tokenize a Uniswap V3 NFT position
contract Algebra19Position is UniswapV3Position{
  /// @notice Camelot V3 Factory, see https://docs.camelot.exchange/contracts/amm-v3/
  IAlgebraFactory private constant algebraFactory = IAlgebraFactory(0x1a3c9B1d2F0529D97f2afC5136Cc23e58f1FD35B); 
  IAlgebraNonfungiblePositionManager private constant _nonFungiblePositionManager = IAlgebraNonfungiblePositionManager(0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15);

  
  /// @notice Return nonFungiblePositionManager contract
  function nonFungiblePositionManager() internal pure override returns (address){
    return address(_nonFungiblePositionManager);
  }

  
  /// @notice Additional initialization tasks
  function initTicks(uint24 _feeTier) internal override {
    feeTier = 60;
    upperTick = TickMath.MAX_TICK - TickMath.MAX_TICK % int24(60);
    lowerTick = -upperTick;
  }
  
  /// @notice Mint function, as Algebra doesnt use fee parameter
  function _mint(uint amount0Desired, uint amount1Desired) internal override returns (uint tokenId, uint newLiquidity){
    (address token0, address token1) = getTokenAddresses();
    (tokenId, newLiquidity,,) = IAlgebraNonfungiblePositionManager(nonFungiblePositionManager()).mint( 
      IAlgebraNonfungiblePositionManager.MintParams({
        token0: token0,
        token1: token1,
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

  
  // @notice Get position liquidity, overriden as Algebra doesnt include a fee param in the return struct
  function getLiquidity() internal override view returns (uint128 liquidity) {
    if (tokenId > 0) (,,,,,, liquidity,,,,) = IAlgebraNonfungiblePositionManager(nonFungiblePositionManager()).positions(tokenId);
  }



  /// @notice Returns the sqrtPriceX96 of the underlying Uniswap pool, used for calculation and comparison with oracle
  function _sqrtPriceX96() internal view override returns (uint160 sqrtPriceX96){
    (address token0, address token1) = getTokenAddresses();
    address pool = algebraFactory.poolByPair(token0, token1);
    (sqrtPriceX96,,,,,,,)  = IAlgebraPool(pool).globalState();
  }
  
  
  /// @notice Get ammType, for naming and tracking purposes
  function ammType() public pure virtual override returns (bytes32 _ammType) {
    _ammType = "Algebra-1.9";
  }
  
}