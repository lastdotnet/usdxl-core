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

    (tokens, oracles) = _deployTestnetTokens(deployerAddress);

    // set oracles
    _setUsdxlOracle(tokens, oracles);

    // set reserve config
    _initializeUsdxlReserve(tokens);

    // enable borrowing
    _enableUsdxlBorrowing(tokens);

    // add USDXL as entity
    _addUsdxlATokenAsEntity();

    // add USDXL flashminter as entity
    _addUsdxlFlashMinterAsEntity(tokens);

    // set USDXL addresses
    _setUsdxlAddresses();

    ERC20 nonMintableErc20;

    nonMintableErc20 = new ERC20('Discount Token', 'DSCNT');

    ZeroDiscountRateStrategy discountRateStrategy;

    discountRateStrategy = new ZeroDiscountRateStrategy();

    _setDiscountTokenAndStrategy(address(discountRateStrategy), address(nonMintableErc20));
  }
}
