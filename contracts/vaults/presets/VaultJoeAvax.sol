// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../VaultBase.sol";
import "../../ammPositions/JoeAvaxPosition.sol";
import "../../interfaces/IVault.sol";


/// @notice Vault with specific parameters for handling Uniswap v2 positions
contract VaultJoeAvax is IVault, JoeAvaxPosition, VaultBase {
  using SafeERC20 for ERC20;
  
  
  
  /// @notice Initialize the vault, use after spawning a new proxy. Caller should be an instance of Controller
  function initProxy(address _baseToken, address _quoteToken, address _positionManager, address weth, address _oracle) 
    public virtual override(IVault, VaultBase)
  {
    super.initProxy(_baseToken, _quoteToken, _positionManager,  weth,  _oracle);
    initAmm(_baseToken, _quoteToken);
  }
  
  
  /// @notice Withdraw all from AMM
  function withdrawAmm() internal override(JoeAvaxPosition, VaultBase) returns (uint baseAmount, uint quoteAmount) {
    (baseAmount, quoteAmount) = JoeAvaxPosition.withdrawAmm();
  }
  
  
  /// @notice Deposit in Amm
  function depositAmm(uint baseAmount, uint quoteAmount) internal override(JoeAvaxPosition, VaultBase) returns (uint liquidity) {
    liquidity = JoeAvaxPosition.depositAmm(baseAmount,  quoteAmount);
  }
  
  
  /// @notice Get AMM range amounts
  function getAmmAmounts() public view override returns (uint baseAmount, uint quoteAmount){
    (baseAmount,  quoteAmount) = _getReserves();
  }

  
  /// @notice Get Amm type 
  function ammType() public pure override(JoeAvaxPosition, IVault, VaultBase) returns (bytes32 _ammType){
    return JoeAvaxPosition.ammType();
  }
}