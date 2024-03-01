// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AmmPositionBase.sol";
import "../../node_modules/@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../../node_modules/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../../node_modules/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


/**
 * @title TraderJoe V1 Avax Position
 * @author GoodEntry
 * @dev Allows depositing liquidity in a regular Uniswap v2 style AMM - TraderJoe on Avax
 */
contract JoeAvaxPosition is AmmPositionBase {
  
  address private lpToken;
  
  // TraderJoe Avax  router
  IUniswapV2Router02 private constant ROUTER_V2 = IUniswapV2Router02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
  
  /// @notice ammType name
  function ammType() public pure virtual override returns (bytes32 _ammType) {
    _ammType = "TraderJoeV1Avax";
  }
  
  
  /// @notice Called on setup
  function initAmm(address _baseToken, address _quoteToken) internal {
    lpToken = IUniswapV2Factory(ROUTER_V2.factory()).getPair(_baseToken, _quoteToken);
    require(lpToken != address(0), "TR: No Such Pool");
  }
  
  
  /// @notice Deposit assets
  function depositAmm(uint baseAmount, uint quoteAmount) internal virtual override returns (uint liquidity) {
    if (baseAmount > 0 && quoteAmount > 0) {
      checkSetApprove(address(baseToken), address(ROUTER_V2), baseAmount);
      checkSetApprove(address(quoteToken), address(ROUTER_V2), quoteAmount);
      (,, liquidity) = ROUTER_V2.addLiquidity(address(baseToken), address(quoteToken), baseAmount, quoteAmount, 0, 0, address(this), block.timestamp);
    }
  }
  
  
  /// @notice Withdraw
  function withdrawAmm() internal virtual override returns (uint256 removed0, uint256 removed1) {
    require(poolPriceMatchesOracle(), "TR: Oracle Price Mismatch");
    uint bal = ERC20(lpToken).balanceOf(address(this));
    checkSetApprove(lpToken, address(ROUTER_V2), bal);
    if (bal > 0) (removed0, removed1) = ROUTER_V2.removeLiquidity(address(baseToken), address(quoteToken), bal, 0, 0, address(this), block.timestamp);
  }
  
  
  /// @notice This range underlying token amounts
  function _getReserves() internal override view returns (uint baseAmount, uint quoteAmount) {
    uint supply = ERC20(lpToken).totalSupply();
    if (supply == 0) return (0, 0);
    uint share = ERC20(lpToken).balanceOf(address(this));
    
    (uint amount0, uint amount1, ) = IUniswapV2Pair(lpToken).getReserves();
    amount0 = amount0 * share / supply;
    amount1 = amount1 * share / supply;
    
    (baseAmount,  quoteAmount) = baseToken < quoteToken ? (amount0, amount1) : (amount1, amount0);
  }
}