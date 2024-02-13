// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "./Deployments.sol";


contract Test_Bug is Test {

  function test_Bug() public {
    VaultAlgebra19  vault = VaultAlgebra19(payable(0xd5fE1A54fA642400ef559d866247cCE66049141B));
    PositionManager  pm = PositionManager(0x8D905e2F41430795293aca990b83798a91aF1D53);
    
    uint toital = pm.totalSupply();
    console.log("Supp", toital);
    
    
    (uint baseAmount, uint quoteAmount, uint valueX8) = vault.getReserves();
    console.log('res', baseAmount, quoteAmount);
    
  }
  
  function test_BugE() public {
    VaultUniV3 vault = VaultUniV3(payable(0x1ba92C53BFe8FD1D81d84B8968422192B73F4475));
    
    (uint baseAmount, uint quoteAmount, uint valueX8) = vault.getReserves();
    console.log('res', baseAmount, quoteAmount);
    
  }

}