// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {ERC20} from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {ZeroDiscountRateStrategy} from 'src/contracts/facilitators/hyfi/interestStrategy/ZeroDiscountRateStrategy.sol';
import {HyperTestnetUsdxlConfigs} from 'src/deployments/configs/HyperTestnetUsdxlConfigs.sol';
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
    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    deployer = vm.envAddress('PUBLIC_KEY');
    console2.log('Deployer Address: ', deployer);
    console2.log('Deployer Balance: ', address(deployer).balance);
    console2.log('Block Number: ', block.number);
    vm.startBroadcast(deployerPrivateKey);
    _deploy();
    vm.stopBroadcast();
  }

  function _deploy() internal {
    vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));

    instanceId = 'hypurrfi-testnet';

    config = DeployUsdxlFileUtils.readInput(instanceId);
    usdxlConfig = DeployUsdxlFileUtils.readUsdxlInput(instanceId);
    if (instanceIdBlock > 0) {
      deployedContracts = DeployUsdxlFileUtils.readOutput(instanceId, instanceIdBlock);
    } else {
      deployedContracts = DeployUsdxlFileUtils.readOutput(instanceId);
    }

    _setDeployRegistry(deployedContracts);

    _deployUsdxl(usdxlConfig.readAddress('.usdxlAdmin'), deployRegistry);
  }
}
