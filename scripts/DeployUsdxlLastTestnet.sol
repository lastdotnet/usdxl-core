// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import {LastTestnetReservesConfig} from 'src/deployments/configs/LastTestnetReservesConfig.sol';

contract DeployUsdxlLastTestnet is LastTestnetReservesConfig, Script {
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

    (tokens, oracles) = _deployTestnetTokens(deployerAddress);

    // set reserve config
    _initReserves(tokens);

    // enable borrowing
    _enableBorrowing(tokens);

    // set oracles
    _setAssetSources(tokens, oracles);
  }
}
