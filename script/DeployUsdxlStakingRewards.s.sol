// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {UsdxlStakingRewards} from 'src/contracts/staking/UsdxlStakingRewards.sol';

contract Default is Script {
  using stdJson for string;

  function run() external {
    _deploy();
  }

  function _deploy() internal {
    vm.startBroadcast(vm.envUint('PRIVATE_KEY'));
    new UsdxlStakingRewards();
    vm.stopBroadcast();
  }
}
