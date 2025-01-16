// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import {ERC20} from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {ZeroDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/ZeroDiscountRateStrategy.sol';
import {HyperTestnetReservesConfig} from 'src/deployments/configs/HyperTestnetReservesConfig.sol';

contract Default is HyperTestnetReservesConfig, Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    address deployerAddress = vm.addr(deployerPrivateKey);
    console2.log('Deployer Address: ', deployerAddress);
    console2.log('Deployer Balance: ', address(deployerAddress).balance);
    console2.log('Block Number: ', block.number);
    vm.startBroadcast(deployerPrivateKey);
    _deploy(deployerAddress);
    vm.stopBroadcast();
  }

  function _deploy(address deployerAddress) internal {
    // launch USDXL token and oracle
    address[] memory tokens;
    address[] memory oracles;

    tokens = new address[](2);

    tokens[0] = address(0x6fDbAF3102eFC67ceE53EeFA4197BE36c8E1A094); // USDC
    tokens[1] = address(0x2222C34A8dd4Ea29743bf8eC4fF165E059839782); // sUSDe

    _launchGsm(
      0x6fDbAF3102eFC67ceE53EeFA4197BE36c8E1A094, // USDC
      vm.envAddress('PUBLIC_KEY') // GSM owner
    );
  }
}
