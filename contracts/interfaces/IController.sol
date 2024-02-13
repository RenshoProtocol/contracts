// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


interface IController {
  function referrals() external view returns (address);
  function treasury() external view returns (address);
  function treasuryShareX2() external view returns (uint8);
  function setTreasury(address _treasury, uint8 _treasuryShareX2) external;
  function updateReferrals(address _referrals) external;
  function isPaused() external view returns(bool);
}