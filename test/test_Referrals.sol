// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "./Addresses.sol";
import "../contracts/referrals/Referrals.sol";


contract Test_Ref is Test {
  Referrals private referrals;
  
  function test_Referrals() public {
    referrals = new Referrals();
    
    // Test register name
    bytes32 name = "Pepe";
    bytes32 name2 = "";
    vm.expectRevert("Empty name");
    referrals.registerName(name2);
    
    referrals.registerName(name);
    vm.expectRevert("Already registered");
    referrals.registerName(name);
    (bytes32 _name,,,,) = referrals.getReferralParameters(address(this));
    assertEq(_name, name);
    
    // User tries to register referrer
    vm.startPrank(Addresses.RANDOM);
    vm.expectRevert("Already registered");
    referrals.registerName(name);
    referrals.registerName("Frog");
    
    vm.expectRevert("No such referrer");
    referrals.registerReferrer("Noone");
    referrals.registerReferrer(name);
    vm.expectRevert("Referrer already set");
    referrals.registerReferrer(name);
    vm.expectRevert("Ownable: caller is not the owner");
    referrals.setVip(Addresses.RANDOM, true);
    vm.stopPrank();
    assertEq(address(this), referrals.getReferrer(Addresses.RANDOM));
    assertEq(referrals.isVip(Addresses.RANDOM), false);
    // Referee is set and can be queried
    assertEq(referrals.getRefereesLength(address(this)), 1);
    assertEq(referrals.getReferee(address(this), 0), Addresses.RANDOM);
    
    // set/unset Vip
    referrals.setVip(Addresses.RANDOM, true);
    assertEq(referrals.isVip(Addresses.RANDOM), true);
    referrals.setVip(Addresses.RANDOM, false);
    assertEq(referrals.isVip(Addresses.RANDOM), false);
    
    // VIP NFT test: Blueberry at 0x17f4BAa9D35Ee54fFbCb2608e20786473c7aa49f
    address nft = 0x17f4BAa9D35Ee54fFbCb2608e20786473c7aa49f;
    address nftuser = 0xF7CB4Ec8118B55FbF3ca80DA392B8cf2634830DD;
    assertEq(referrals.isVip(nftuser), false);
    assertEq(referrals.isVip(Addresses.RANDOM), false);
    vm.expectRevert("Ref: Invalid NFT");
    referrals.addVipNft(address(0x0));
    referrals.addVipNft(nft);
    vm.expectRevert("Ref: Already NFT");
    referrals.addVipNft(nft);
    assertEq(referrals.isVip(nftuser), true);
    assertEq(referrals.isVip(Addresses.RANDOM), false);
    referrals.removeVipNft(nft);
    assertEq(referrals.isVip(nftuser), false);
    assertEq(referrals.isVip(Addresses.RANDOM), false);
    // Multiple NFT, remove one in the middle
    referrals.addVipNft(0x9baDE4013a7601aA1f3e9f1361a4ebE60D91B1B5); // Dopex NFT
    referrals.addVipNft(nft);
    referrals.addVipNft(0xfAe39eC09730CA0F14262A636D2d7C5539353752); // Arbitrum odyssey NFT
    assertEq(referrals.isVip(nftuser), true);
    assertEq(referrals.isVip(0x5a49b01F72E4AF5109e1D2856485e71985A696Fb), true); // arbitrum odyssey whale
    referrals.removeVipNft(0xfAe39eC09730CA0F14262A636D2d7C5539353752);
    assertEq(referrals.isVip(nftuser), true);
    assertEq(referrals.isVip(0x5a49b01F72E4AF5109e1D2856485e71985A696Fb), false); // arbitrum odyssey whale
    referrals.addVipNft(0xfAe39eC09730CA0F14262A636D2d7C5539353752);  // Arbitrum odyssey NFT
    referrals.removeVipNft(nft);
    assertEq(referrals.isVip(nftuser), false);
    assertEq(referrals.isVip(0x5a49b01F72E4AF5109e1D2856485e71985A696Fb), true); // arbitrum odyssey whale
    
    
    // Set rebates/discounts
    vm.expectRevert("GEC: Invalid Discount");
    referrals.setReferralDiscounts(10000, 300, 400, 500);
    vm.expectRevert("GEC: Invalid Discount");
    referrals.setReferralDiscounts(200, 10000, 400, 500);
    vm.expectRevert("GEC: Invalid Discount");
    referrals.setReferralDiscounts(200, 300, 10000, 500);
    vm.expectRevert("GEC: Invalid Discount");
    referrals.setReferralDiscounts(200, 300, 400, 10000);
    
    referrals.setReferralDiscounts(200, 300, 400, 500);
    assertEq(referrals.rebateReferrer(), 200);
    assertEq(referrals.rebateReferrerVip(), 300);
    assertEq(referrals.discountReferee(), 400);
    assertEq(referrals.discountRefereeVip(), 500);
    
    address ref;
    uint16 rebateRef;
    uint16 discountRef;
    // Random user doesnt have discounts
    (,,ref, rebateRef, discountRef) = referrals.getReferralParameters(Addresses.DEADBEEF);
    assertEq(address(0), ref);
    assertEq(rebateRef, 0);
    assertEq(discountRef, 0);
    // Regular user, regular referrer
    (,,ref, rebateRef, discountRef) = referrals.getReferralParameters(Addresses.RANDOM);
    assertEq(address(this), ref);
    assertEq(rebateRef, referrals.rebateReferrer());
    assertEq(discountRef, referrals.discountReferee());
    // Vip user, regular referrer
    referrals.setVip(Addresses.RANDOM, true);
    (,,ref, rebateRef, discountRef) = referrals.getReferralParameters(Addresses.RANDOM);
    assertEq(address(this), ref);
    assertEq(rebateRef, referrals.rebateReferrer());
    assertEq(discountRef, referrals.discountRefereeVip());
    // Vip user, Vip referrer
    referrals.setVip(address(this), true);
    (,,ref, rebateRef, discountRef) = referrals.getReferralParameters(Addresses.RANDOM);
    assertEq(address(this), ref);
    assertEq(rebateRef, referrals.rebateReferrerVip());
    assertEq(discountRef, referrals.discountRefereeVip());
    // Regular user, Vip referrer
    referrals.setVip(Addresses.RANDOM, false);
    (,,ref, rebateRef, discountRef) = referrals.getReferralParameters(Addresses.RANDOM);
    assertEq(address(this), ref);
    assertEq(rebateRef, referrals.rebateReferrerVip());
    assertEq(discountRef, referrals.discountReferee());
    
  }

}