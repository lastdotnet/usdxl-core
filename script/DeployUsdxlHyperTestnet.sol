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

  string deployedContracts;

  function run() external {
    // console2.log('Deployer Address: ', deployer);
    // console2.log('Deployer Balance: ', address(deployer).balance);
    // console2.log('Block Number: ', block.number);
    vm.startBroadcast(vm.envUint('PRIVATE_KEY'));
    _deploy();
    vm.stopBroadcast();
  }

  function _deploy() internal {
    vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));

    instanceId = 'hypurrfi-testnet';

    config = DeployUsdxlFileUtils.readInput(instanceId);
    usdxlConfig = DeployUsdxlFileUtils.readUsdxlInput(instanceId);

    admin = config.readAddress('.admin');
    deployer = msg.sender;

    if (instanceIdBlock > 0) {
      deployedContracts = DeployUsdxlFileUtils.readOutput(instanceId, instanceIdBlock);
    } else {
      deployedContracts = DeployUsdxlFileUtils.readOutput(instanceId);
    }

    _setDeployRegistry(deployedContracts);

    _deployUsdxl(usdxlConfig.readAddress('.usdxlAdmin'));
  }
}
