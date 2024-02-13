# Rensho

## Tests with Foundry

> forge test -vv --fork-url https://sepolia.blast.io

> forge coverage --ir-minimum --report summary --report lcov --fork-url https://sepolia.blast.io

> metrics contracts/Oracle/* contracts/ammPositions/* contracts/referrals/Referrals.sol  contracts/vaults/* contracts/*.sol contracts/PositionManager/*


|Files|                      Language|       SLOC|Comment|McCabe|
|-----|------------------------------|-----------|-------|------|
|   14|                      Solidity|       1181|  15437|   100|


## Deployment

> forge script script/Deploy.sol:DeployScript --fork-url http://localhost:8545 --broadcast
> forge script script/Deploy.sol:DeployScript --fork-url https://sepolia.blast.io --broadcast --legacy


## Verifications

Dumb Oracle
> forge verify-contract 0x602A35fcDFd66C0aCDed7B42f1bDE52021FA756e contracts/Oracle/DumbOracle.sol:DumbOracle --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' --etherscan-api-key "verifyContract" --num-of-optimizations 200 --compiler-version 0.8.19  --watch

Referrals
> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0xA0E3C6E332225ACC151A17cEb835123843Af3f27 Referrals --etherscan-api-key "verifyContract" --watch --compiler-version 0.8.19 

StrikeManager
> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0x5B7F7684C5A3222C4732FA12eD46A0b2a6Ba5B67 StrikeManager --etherscan-api-key "verifyContract" --watch --compiler-version 0.8.19 

PositionManager: link lib StrikeManager
> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0x2CEAB8c03E557d9e9E2976eFAa802606Ec134c31 PositionManager --etherscan-api-key "verifyContract" --watch --compiler-version 0.8.19 --libraries contracts/PositionManager/StrikeManager.sol:StrikeManager:0x5B7F7684C5A3222C4732FA12eD46A0b2a6Ba5B67

> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0xBFD31f052d1dD207Bc4FfD9DD60EF2E00b9b531E TransparentUpgradeableProxy --etherscan-api-key "verifyContract" --constructor-args $(cast abi-encode "constructor(address,address,bytes)" 0x490235Cf06168326570b7d02AEc388A3c4a8e497 0x0928c1F7a7EAe94Cac6f333D83F0768aaa836d05 "") --watch --compiler-version 0.8.19

> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0x41Ad9DA4e62d3E6943c2e30E89B4ECb97E1780EA Oracle --etherscan-api-key "verifyContract" --constructor-args $(cast abi-encode "constructor(address[],address[],address,address,uint256,int256)" [] [] 0x0000000000000000000000000000000000000000 0x4200000000000000000000000000000000000022 100000000 4500000) --watch --compiler-version 0.8.19 --libraries contracts/lib/Lyra/BlackScholes.sol:BlackScholes:0xfFC6828EbA06168C8Adec4110F51bf8f66dE6078

Vaults
> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0xC5a715dF47c247798CB9a1E10F8728560199CE3E VaultUniV2 --etherscan-api-key "verifyContract" --watch --compiler-version 0.8.19 
> forge verify-contract --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/168587773/etherscan' 0xE7A0992827C979a7083F5664806a834B62243a0B VaultUniV3 --etherscan-api-key "verifyContract" --watch --compiler-version 0.8.19 
