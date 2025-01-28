// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {HyperTestnetUsdxlConfigs} from 'src/deployments/configs/HyperTestnetUsdxlConfigs.sol';
import {DeployUtils} from 'src/deployments/utils/DeployUtils.sol';

contract Default is HyperTestnetUsdxlConfigs, Script {
  using stdJson for string;

  string instanceId = 'hypurrfi-testnet';
  uint256 instanceIdBlock = 0;
  string rpcUrl;
  uint256 forkBlock;
  uint256 initialReserveCount;

  string config;
  string deployedContracts;

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
    vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));

    config = DeployUtils.readInput(instanceId);
    if (instanceIdBlock > 0) {
      deployedContracts = DeployUtils.readOutput(instanceId, instanceIdBlock);
    } else {
      deployedContracts = DeployUtils.readOutput(instanceId);
    }

    _setDeployRegistry(deployedContracts);

    // call borrow for USDXL
    _borrowUsdxl(1e18, vm.envAddress('PUBLIC_KEY'));
  }
}
