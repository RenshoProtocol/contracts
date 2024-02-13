// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


/// @notice Dumb centralized oracle for early testing 
contract DumbOracle {
  address public owner;
  int256 public price;
  string public name;

  constructor() {
    owner = msg.sender;
  }

  function setOwner(address _owner) public {
    require(msg.sender == owner, "Forbidden");
    owner = _owner;
  }

  function setPrice(int256 _price) public {
    require(msg.sender == owner, "Forbidden");
    price = _price;
  }

  function latestAnswer() external view returns (int256) {
    return price;
  }
}
