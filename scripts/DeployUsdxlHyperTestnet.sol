// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from 'forge-std/Script.sol';
import 'forge-std/StdJson.sol';
import {ERC20} from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {ZeroDiscountRateStrategy} from 'src/contracts/facilitators/hyfi/interestStrategy/ZeroDiscountRateStrategy.sol';
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
    // launch USDXL token and oracle
    address[] memory tokens;
    address[] memory oracles;

    (tokens, oracles) = _deployTestnetTokens(
      deployerAddress,
      0x11EaaaEB22d837D10E5955920aF605B6D309548e
    );

    _grantFacilitatorManagerRole(deployerAddress);

    // set oracles
    _setUsdxlOracle(tokens, oracles);

    // set reserve config
    _initializeUsdxlReserve(tokens[0]);

    // update interest rate strategy
    _updateUsdxlInterestRateStrategy();

    // enable borrowing
    _enableUsdxlBorrowing(tokens);

    // add USDXL as entity
    _addUsdxlATokenAsEntity();

    // add USDXL flashminter as entity
    _addUsdxlFlashMinterAsEntity(tokens);

    _revokeFacilitatorManagerRole(deployerAddress);

    // set USDXL addresses
    _setUsdxlAddresses();

    ERC20 nonMintableErc20;

    nonMintableErc20 = new ERC20('Discount Token', 'DSCNT');

    ZeroDiscountRateStrategy discountRateStrategy;

    discountRateStrategy = new ZeroDiscountRateStrategy();

    _setDiscountTokenAndStrategy(address(discountRateStrategy), address(nonMintableErc20));
  }
}
