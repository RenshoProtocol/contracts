// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../VaultBase.sol";
import "../../ammPositions/Algebra19Position.sol";
import "../../interfaces/IVault.sol";


/// @notice Vault with specific parameters for handling Uniswap v3 positions
contract VaultAlgebra19 is IVault, Algebra19Position, VaultBase {
  using SafeERC20 for ERC20;
  
  
  /// @notice Initialize the vault, use after spawning a new proxy. Caller should be an instance of Controller
  function initProxy(address _baseToken, address _quoteToken, address _positionManager, address weth, address _oracle) 
    public virtual override(IVault, VaultBase)
  {
    VaultBase.initProxy(_baseToken, _quoteToken, _positionManager,  weth,  _oracle);
    // Algebra tick spacing 
    initTicks(60);
  }
  
  
  /// @notice Withdraw all from AMM
  function withdrawAmm() internal override(UniswapV3Position, VaultBase) returns (uint baseAmount, uint quoteAmount) {
    (baseAmount, quoteAmount) = UniswapV3Position.withdrawAmm();
  }
  
  
  /// @notice Deposit in Amm
  function depositAmm(uint baseAmount, uint quoteAmount) internal override (UniswapV3Position, VaultBase) returns (uint256 liquidity) {
    liquidity = UniswapV3Position.depositAmm(baseAmount,  quoteAmount);
  }
  
  
  /// @notice Get AMM range amounts
  function getAmmAmounts() public view override returns (uint baseAmount, uint quoteAmount){
    (baseAmount,  quoteAmount) = _getReserves();
  }

  
  /// @notice Send amounts to treasury 
  function sendToTreasury(uint baseAmount, uint quoteAmount) internal {
    address treasury = controller.treasury();
    // Send share to treasury
    if (baseAmount  > 0) ERC20(baseToken).safeTransfer(treasury, baseAmount);
    if (quoteAmount > 0) ERC20(quoteToken).safeTransfer(treasury, quoteAmount);
  }
  
  
  /// @notice Callback after fees are claimed to reserve fees
  function _afterClaimFees(uint baseAmount, uint quoteAmount) internal override {
    uint treasuryShareX2 = uint(controller.treasuryShareX2());
    uint baseTreasuryAmount = baseAmount * treasuryShareX2 / 100;
    uint quoteTreasuryAmount = quoteAmount * treasuryShareX2 / 100; 
    if(treasuryShareX2 > 0) sendToTreasury(baseTreasuryAmount, quoteTreasuryAmount);
    uint valueFees = baseAmount * oracle.getAssetPrice(address(baseToken)) / 10**baseToken.decimals() 
                  + quoteAmount * oracle.getAssetPrice(address(quoteToken)) / 10**quoteToken.decimals();
    reserveFees(baseAmount - baseTreasuryAmount, quoteAmount - quoteTreasuryAmount, valueFees);
  }

  
  function ammType() public pure override(Algebra19Position, IVault, VaultBase) returns (bytes32 _ammType){
    return Algebra19Position.ammType();
  }
}