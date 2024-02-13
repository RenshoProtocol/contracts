// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IOracle.sol";


/// @notice Commons for vaults and AMM positions for inheritance conflicts purposes
abstract contract Commons {
  /// @notice Vault underlying tokens
  ERC20 internal baseToken;
  ERC20 internal quoteToken;
  /// @notice Oracle address
  IOracle internal oracle;
}