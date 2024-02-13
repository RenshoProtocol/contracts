// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


library Addresses {
  address constant public WETH = 0x4200000000000000000000000000000000000023;
  // rebasing USD
  address constant public USD = 0x4200000000000000000000000000000000000022;
  
  // USD price fee is useless as used as oracle base asset
  address constant public WETH_USD_CHAINLINK_FEED = 0x602A35fcDFd66C0aCDed7B42f1bDE52021FA756e;

  address constant public TREASURY = 0xC0ffEE0000000000000000000000000000001001;
  address constant public DEADBEEF = 0x00000000000000000000000000000000DeaDBeef;
  address constant public RANDOM   = 0x0000000000000000000010000000000000000101;
  
  address constant public MUCH_WETH = 0x50ED0a15C0aF3CaC9A2c46FbfAAbDD09b737087C;
  address constant public MUCH_USD= 0xA721084c35755015961BDFb1C91B3EFdeDd9987E;
  
  address constant public UNISWAP_ROUTER_V3 = 0xF339F231678e738c4D553e6b60305b852a4C526B;
  address constant public WETH_USD_UNISWAP_005 = 0xE23EE7899C6339e2a1b0a5409c1E7215f7024b8A;
}

