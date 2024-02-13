// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "../contracts/PositionManager/StrikeManager.sol";


contract Test_StrikeManager is Test {
  
  function test_TickSpacing() public {
    assertEq(StrikeManager.getStrikeSpacing(20), 1);
    assertEq(StrikeManager.getStrikeSpacing(80), 1);
    
    assertEq(StrikeManager.getStrikeSpacing(100), 1);
    assertEq(StrikeManager.getStrikeSpacing(200), 1);
    assertEq(StrikeManager.getStrikeSpacing(800), 2);
    
    assertEq(StrikeManager.getStrikeSpacing(1000), 10);
    assertEq(StrikeManager.getStrikeSpacing(2000), 10);
    assertEq(StrikeManager.getStrikeSpacing(8000), 20);
    
    assertEq(StrikeManager.getStrikeSpacing(10000), 100);
    assertEq(StrikeManager.getStrikeSpacing(20000), 100);
    assertEq(StrikeManager.getStrikeSpacing(80000), 200);
    
    assertEq(StrikeManager.getStrikeSpacing(100000), 1000);
    assertEq(StrikeManager.getStrikeSpacing(200000), 1000);
    assertEq(StrikeManager.getStrikeSpacing(800000), 2000);
    
    assertEq(StrikeManager.getStrikeSpacing(1000000), 10000);
    assertEq(StrikeManager.getStrikeSpacing(2000000), 10000);
    assertEq(StrikeManager.getStrikeSpacing(8000000), 20000);
  }
  
  function test_StrikeAbove() public {
    assertEq(StrikeManager.getStrikeAbove(100), 100);
    assertEq(StrikeManager.getStrikeAbove(150), 150);
    assertEq(StrikeManager.getStrikeAbove(401), 401);
    assertEq(StrikeManager.getStrikeAbove(500), 500);
    
    assertEq(StrikeManager.getStrikeAbove(1001), 1010);
    assertEq(StrikeManager.getStrikeAbove(1501), 1510);
    assertEq(StrikeManager.getStrikeAbove(4020), 4020);
    assertEq(StrikeManager.getStrikeAbove(5008), 5020);
  }  
  
  function test_StrikeStrictlyAbove() public {
    assertEq(StrikeManager.getStrikeStrictlyAbove(100), 101);
    assertEq(StrikeManager.getStrikeStrictlyAbove(150), 151);
    assertEq(StrikeManager.getStrikeStrictlyAbove(401), 402);
    assertEq(StrikeManager.getStrikeStrictlyAbove(500), 502);
    
    assertEq(StrikeManager.getStrikeStrictlyAbove(1000), 1010);
    assertEq(StrikeManager.getStrikeStrictlyAbove(1500), 1510);
    assertEq(StrikeManager.getStrikeStrictlyAbove(4010), 4020);
    assertEq(StrikeManager.getStrikeStrictlyAbove(5000), 5020);
  }
  
  
  function test_StrikeBelow() public {
    assertEq(StrikeManager.getStrikeBelow(100), 100);
    assertEq(StrikeManager.getStrikeBelow(149), 149);
    assertEq(StrikeManager.getStrikeBelow(401), 401);
    assertEq(StrikeManager.getStrikeBelow(500), 500);
    
    assertEq(StrikeManager.getStrikeBelow(1001), 1000);
    assertEq(StrikeManager.getStrikeBelow(1501), 1500);
    assertEq(StrikeManager.getStrikeBelow(4012), 4010);
    assertEq(StrikeManager.getStrikeBelow(5005), 5000);
  }  
  
  function test_StrikeStrictlyBelow() public {
    assertEq(StrikeManager.getStrikeStrictlyBelow(100), 99);
    assertEq(StrikeManager.getStrikeStrictlyBelow(150), 149);
    assertEq(StrikeManager.getStrikeStrictlyBelow(401), 400);
    assertEq(StrikeManager.getStrikeStrictlyBelow(500), 499);
    
    assertEq(StrikeManager.getStrikeStrictlyBelow(1000), 998);
    assertEq(StrikeManager.getStrikeStrictlyBelow(1500), 1490);
    assertEq(StrikeManager.getStrikeStrictlyBelow(4010), 4000);
    assertEq(StrikeManager.getStrikeStrictlyBelow(5000), 4990);
  }
  
  function test_IsValidStrike() public {
    assertEq(StrikeManager.isValidStrike(0), false);
    assertEq(StrikeManager.isValidStrike(109), true);
    assertEq(StrikeManager.isValidStrike(150), true);
    assertEq(StrikeManager.isValidStrike(500), true);
    assertEq(StrikeManager.isValidStrike(501), false);
    
    assertEq(StrikeManager.isValidStrike(1001), false);
    assertEq(StrikeManager.isValidStrike(1500), true);
    assertEq(StrikeManager.isValidStrike(4015), false);
    assertEq(StrikeManager.isValidStrike(5000), true);
  }
}