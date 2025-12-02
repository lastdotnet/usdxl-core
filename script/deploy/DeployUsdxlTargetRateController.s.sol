// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {UsdxlTargetRateController} from "../../src/contracts/facilitators/hyfi/interestStrategy/UsdxlTargetRateController.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeployUsdxlTargetRateController
 * @notice Deployment script for USDXL Target Rate Controller
 */
contract DeployUsdxlTargetRateController is Script {
    struct UsdxlTargetRateControllerConfig {
        address addressesProvider;
        address usdxlToken;
        address usdt0Token;
        address wrappedHypeGateway;
        uint256 initialRate;
        uint256 initialETHAmount;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 executorPrivateKey = vm.envUint("EXECUTOR_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address multisig = 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb;
        address executor = vm.addr(executorPrivateKey);
        
        // Configuration
        UsdxlTargetRateControllerConfig memory config = UsdxlTargetRateControllerConfig({
            addressesProvider: 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594,
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645,
            usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address
            wrappedHypeGateway: 0xd1EF87FeFA83154F83541b68BD09185e15463972,
            initialRate: 0.2557e27, // 25.57% in ray
            initialETHAmount: 0.001 ether // 0.001 ETH for initial HYPE supply
        });

        console2.log("Deploying USDXL Target Rate Controller...");
        console2.log("Deployer:", deployer);
        console2.log("Addresses Provider:", config.addressesProvider);
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("USDT0 Token:", config.usdt0Token);
        console2.log("WrappedHypeGateway:", config.wrappedHypeGateway);
        console2.log("Initial Rate:", config.initialRate);
        console2.log("Initial ETH Amount:", config.initialETHAmount);

        vm.startBroadcast(deployerPrivateKey);
        
        UsdxlTargetRateController rateController = new UsdxlTargetRateController{value: config.initialETHAmount}(
            config.addressesProvider,
            config.usdxlToken,
            config.usdt0Token,
            config.initialRate,
            deployer,
            config.wrappedHypeGateway
        );

        rateController.updateExecutor(deployer, true);
        rateController.updateExecutor(executor, true);
        rateController.transferOwnership(multisig);
        
        vm.stopBroadcast();
        
        console2.log("USDXL Target Rate Controller deployed at:", address(rateController));
        console2.log("Initial ETH balance:", address(rateController).balance);
        
        // Export the contract address and config as JSON
        // vm.writeFile("script/output/999/target-rate-controller.json", 
        //     string(abi.encodePacked(
        //         "{\n",
        //         '  "targetRateController": "', vm.toString(address(rateController)), '",\n',
        //         '  "addressesProvider": "', vm.toString(config.addressesProvider), '",\n',
        //         '  "usdxlToken": "', vm.toString(config.usdxlToken), '",\n',
        //         '  "usdt0Token": "', vm.toString(config.usdt0Token), '",\n',
        //         '  "wrappedHypeGateway": "', vm.toString(config.wrappedHypeGateway), '",\n',
        //         '  "initialRate": "', vm.toString(config.initialRate), '",\n',
        //         '  "initialETHAmount": "', vm.toString(config.initialETHAmount), '"\n',
        //         "}\n"
        //     ))
        // );
        
        console2.log("Deployment data saved to: script/output/999/target-rate-controller.json");
    }
}
