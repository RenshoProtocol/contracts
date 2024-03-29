// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IReferrals {
  function registerName(bytes32 name) external;
  function registerReferrer(bytes32 name) external;
  function getReferrer(address user) external view returns (address referrer);
  function getRefereesLength(address referrer) external view returns (uint length);
  function getReferee(address referrer, uint index) external view returns (address referee);
  function getReferralParameters(address user) external view returns (bytes32 name, uint referreesLength, address _referrer, uint16 _rebateReferrer, uint16 _discountReferee);
  function addVipNft(address _nft) external;
  function removeVipNft(address _nft) external;
}