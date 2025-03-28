// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {DeployUsdxlUtils} from 'src/deployments/utils/DeployUsdxlUtils.sol';
import {DeployUsdxlFileUtils} from 'src/deployments/utils/DeployUsdxlFileUtils.sol';

contract Default is DeployUsdxlUtils, Script {
  using stdJson for string;

  uint256 instanceIdBlock = 0;
  string rpcUrl;
  uint256 forkBlock;
  uint256 initialReserveCount;

  function run() external {
    _deploy();
  }

  function _deploy() internal {
    vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));

    instanceId = vm.envString('INSTANCE_ID');

    config = DeployUsdxlFileUtils.readInput(instanceId);
    usdxlConfig = DeployUsdxlFileUtils.readUsdxlInput(instanceId);

    admin = config.readAddress('.admin');
    deployer = vm.envAddress('PUBLIC_KEY');

    if (instanceIdBlock > 0) {
      deployedContracts = DeployUsdxlFileUtils.readOutput(instanceId, instanceIdBlock);
    } else {
      deployedContracts = DeployUsdxlFileUtils.readOutput(instanceId);
    }

    console2.log('Deployer Address: ', deployer);
    console2.log('Deployer Balance: ', address(deployer).balance);
    console2.log('Block Number: ', block.number);

    _setDeployRegistry(deployedContracts);

    vm.startBroadcast(vm.envUint('PRIVATE_KEY'));
    _deployUsdxl();
    vm.stopBroadcast();
  }
}
