// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IController.sol";
import "../interfaces/IVaultConfigurator.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IWETH.sol";

abstract contract VaultConfigurator is Ownable {
  event SetFee(uint baseFeeX4);
  event SetTvlCap(uint tvlCapX8);
  event SetAmmPositionShare(uint8 ammPositionShareX2);


  /// @notice Controller address
  IController public controller;
  /// @notice Pool base fee X4: 20 => 0.2%
  uint24 public baseFeeX4 = 20;
  // Useful to adjust fees down
  uint internal constant FEE_MULTIPLIER = 1e4;
  /// @notice Percentage of assets deployed in a full range
  uint8 public ammPositionShareX2 = 50;
  /// @notice Max vault TVL with 8 decimals, 0 for no limit
  uint96 public tvlCapX8;
  /// @notice WETH addrsss to handle ETH deposits
  IWETH internal WETH;
  // Obsolete but cant remove or will affect proxy storage stack
  mapping(address => uint) public depositTime;
  mapping(address => uint) public depositBalance;
  
  /// @notice initialize the value when a vault is created as a proxy
  function initializeConfig() internal {
    setBaseFee(20);
    setAmmPositionShare(50);
  }
  
  
  /// @notice Set ammPositionShare (how much of assets go into the AMM)
  /// @param _ammPositionShareX2 proportion of liquidity going into the AMM
  /// @dev Since liquidity is balanced between both assets, the share is taken according to lowest available token
  /// That share is therefore strictly lower that the TVL total
  function setAmmPositionShare(uint8 _ammPositionShareX2) public onlyOwner { 
    require(_ammPositionShareX2 <= 100, "VC: Invalid FRS");
    ammPositionShareX2 = _ammPositionShareX2; 
    emit SetAmmPositionShare(_ammPositionShareX2);
  }
  

  /// @notice Set the base fee
  /// @param _baseFeeX4 New base fee in E4, cant be > 100% = 1e4
  function setBaseFee(uint24 _baseFeeX4) public onlyOwner {
    require(_baseFeeX4 < FEE_MULTIPLIER, "VC: Invalid Base Fee");
    baseFeeX4 = _baseFeeX4;
    emit SetFee(_baseFeeX4);
  }
  
  
  /// @notice Set the TVL cap
  /// @param _tvlCapX8 New TVL cap
  function setTvlCap(uint96 _tvlCapX8) public onlyOwner {
    tvlCapX8 = _tvlCapX8;
    emit SetTvlCap(_tvlCapX8);
  }
}