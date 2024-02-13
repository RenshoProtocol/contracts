// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IVault.sol";
import "../Commons.sol";


abstract contract AmmPositionBase is Commons {
  using SafeERC20 for ERC20;
  
  /// EVENTS
  event ClaimFees(uint fee0, uint fee1);
  
  // Position parameters
  uint internal baseFees;
  uint internal quoteFees;
  
  uint128 constant UINT128MAX = type(uint128).max;
  uint256 constant UINT256MAX = type(uint256).max;

  
  /// @notice Checks whether AMM price and oracle price match
  /// @dev For a balanced pool (UniV2 or UniV3 full range), both tokens should be present in equal values by design
  function poolPriceMatchesOracle() public virtual returns (bool isMatching) {
    (uint baseAmount, uint quoteAmount) = _getReserves();
    uint baseValue = baseAmount * oracle.getAssetPrice(address(baseToken)) / 10**baseToken.decimals();
    uint quoteValue = quoteAmount * oracle.getAssetPrice(address(quoteToken)) / 10**quoteToken.decimals();
    isMatching = baseValue >= quoteValue * 97 / 100 && quoteValue >= baseValue * 97 / 100;
  }
  
    
  /// @notice Get lifetime fees
  function getLifetimeFees() public virtual view returns (uint, uint) {
    return (baseFees, quoteFees);
  }
  
  
  /// @notice Helper that checks current allowance and approves if necessary
  function checkSetApprove(address token, address spender, uint amount) internal {
    uint currentAllowance = ERC20(token).allowance(address(this), spender);
    if (currentAllowance < amount) ERC20(token).safeIncreaseAllowance(spender, UINT256MAX - currentAllowance);
  }
  
  
  function _getReserves() internal virtual view returns (uint baseAmount, uint quoteAmount) {}
  /// @notice Deposit assets and get exactly the expected liquidity
  /// @param baseAmount Amount of base asset
  /// @param quoteAmount Amount of quote asset
  /// @return liquidity Amount of LP tokens created
  function depositAmm(uint baseAmount, uint quoteAmount) internal virtual returns (uint liquidity);
  function withdrawAmm() internal virtual returns (uint baseAmount, uint quoteAmount);
  /// @notice Get ammType, for naming and tracking purposes
  function ammType() public pure virtual returns (bytes32 _ammType);
}