// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IController.sol";


interface IVaultConfigurator  {
  function controller() external view returns (IController);
  function baseFeeX4() external view returns (uint24);
  function owner() external view returns (address);
  function transferOwnership(address newOwner) external;
}