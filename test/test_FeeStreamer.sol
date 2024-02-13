// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "./Deployments.sol";
import "../contracts/vaults/FeeStreamer.sol";


contract FS is FeeStreamer {
  function _reserveFees(uint amount0, uint amount1, uint value) public {
    super.reserveFees(amount0, amount1, value);
  }
}

contract Test_FeeStreamer is Test, FeeStreamer {
  function test_ReserveFees0() public {
    FS fs = new FS();
    uint pending0;
    uint pending1;
    
    fs._reserveFees(1e18, 0, 1e18);
    
    (pending0, pending1) = fs.getPendingFees();
    assertEq(pending0, 1e18);
    // sleep till next day
    skip(86400 - block.timestamp % 86400);
    (pending0, pending1) = fs.getPendingFees();
    assertEq(pending0, 1e18);
    // check that fees are streamed linearly
    for (uint k =0; k< 10; k++){
      (pending0, pending1) = fs.getPendingFees();
      assertEq(pending0, 1e18 - k * 1e17);
      skip(8640);
    }
    
    (pending0, pending1) = fs.getPendingFees();
    assertEq(pending0, 0);
  }
  
  function test_ReserveFees1() public {
    uint pending0;
    uint pending1;
    
    reserveFees(0, 1e18, 1e18);
    
    (pending0, pending1) = getPendingFees();
    assertEq(pending1, 1e18);
    assertEq(pending0, 0);
    // sleep till next day
    skip(86400 - block.timestamp % 86400);
    (pending0, pending1) = getPendingFees();
    assertEq(pending1, 1e18);
    assertEq(pending0, 0);
    // check that fees are streamed linearly
    for (uint k =0; k< 10; k++){
      (pending0, pending1) = getPendingFees();
      assertEq(pending1, 1e18 - k * 1e17);
      assertEq(pending0, 0);
      skip(8640);
    }
    
    (pending0, pending1) = getPendingFees();
    assertEq(pending1, 0);
    assertEq(pending0, 0);
  }
}
