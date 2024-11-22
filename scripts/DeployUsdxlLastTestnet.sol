// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import {ERC20} from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {ZeroDiscountRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/ZeroDiscountRateStrategy.sol';
import {LastTestnetReservesConfig} from 'src/deployments/configs/LastTestnetReservesConfig.sol';

contract Default is LastTestnetReservesConfig, Script {
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

    // (tokens, oracles) = _deployTestnetTokens(deployerAddress);

    // // set oracles
    // _setGhoOracle(tokens, oracles);

    // // set reserve config
    // _initializeGhoReserve(tokens);

    // // enable borrowing
    // _enableGhoBorrowing(tokens);

    // add GHO as entity
    _addGhoATokenAsEntity();

    // // add GHO flashminter as entity
    // _addGhoFlashMinterAsEntity(tokens);

    // // set GHO addresses
    // _setGhoAddresses(tokens);

    // ERC20 nonMintableErc20;

    // nonMintableErc20 = new ERC20('Discount Token', 'DSCNT');

    // ZeroDiscountRateStrategy discountRateStrategy;

    // discountRateStrategy = new ZeroDiscountRateStrategy();

    // _setDiscountTokenAndStrategy(address(discountRateStrategy), address(nonMintableErc20));
  }
}
