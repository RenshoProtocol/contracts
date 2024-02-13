// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "./Deployments.sol";
import "../contracts/vaults/VaultConfigurator.sol";


contract VC is VaultConfigurator {

}

contract Test_VaultConfigurator is Test {

  function test_VC () public {
    VC vc = new VC();
    
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("Ownable: caller is not the owner");
    vc.setAmmPositionShare(50);
    vm.stopPrank();
    
    vm.expectRevert("VC: Invalid FRS");
    vc.setAmmPositionShare(120);
    vc.setAmmPositionShare(50);
    assertEq(vc.ammPositionShareX2(), 50);
    
    vm.expectRevert("VC: Invalid Base Fee");
    vc.setBaseFee(2e4);
    vc.setBaseFee(50);
    assertEq(vc.baseFeeX4(), 50);
    
    vc.setTvlCap(200);
    assertEq(vc.tvlCapX8(), 200);
  }

}