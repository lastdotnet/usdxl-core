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
        address usdxlReserve;
        address usdt0Reserve;
        address usdxlPriceFeed;
        address usdt0PriceFeed;
        address wrappedHypeGateway;
        uint256 initialRate;
        uint256 initialETHAmount;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address multisig = 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb;
        
        // Configuration
        UsdxlTargetRateControllerConfig memory config = UsdxlTargetRateControllerConfig({
            addressesProvider: 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594,
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645,
            usdxlReserve: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645,
            usdt0Reserve: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 reserve address
            usdxlPriceFeed: 0x0000000000000000000000000000000000000000, // TODO: Set actual USDXL price feed address
            usdt0PriceFeed: 0x0000000000000000000000000000000000000000, // TODO: Set actual USDT0 price feed address
            wrappedHypeGateway: 0xd1EF87FeFA83154F83541b68BD09185e15463972,
            initialRate: 0.136e27, // 13.6% in ray
            initialETHAmount: 0.1 ether // 0.1 ETH for initial HYPE supply
        });

        console2.log("Deploying USDXL Target Rate Controller...");
        console2.log("Deployer:", deployer);
        console2.log("Addresses Provider:", config.addressesProvider);
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("USDXL Reserve:", config.usdxlReserve);
        console2.log("USDT0 Reserve:", config.usdt0Reserve);
        console2.log("USDXL Price Feed:", config.usdxlPriceFeed);
        console2.log("USDT0 Price Feed:", config.usdt0PriceFeed);
        console2.log("WrappedHypeGateway:", config.wrappedHypeGateway);
        console2.log("Initial Rate:", config.initialRate);
        console2.log("Initial ETH Amount:", config.initialETHAmount);

        vm.startBroadcast(deployerPrivateKey);
        
        UsdxlTargetRateController rateController = new UsdxlTargetRateController{value: config.initialETHAmount}(
            config.addressesProvider,
            config.usdxlToken,
            config.usdxlReserve,
            config.usdt0Reserve,
            config.usdxlPriceFeed,
            config.usdt0PriceFeed,
            config.initialRate,
            deployer,
            config.wrappedHypeGateway
        );

        rateController.updateExecutor(deployer, true);
        rateController.transferOwnership(multisig);
        
        vm.stopBroadcast();
        
        console2.log("USDXL Target Rate Controller deployed at:", address(rateController));
        console2.log("Initial ETH balance:", address(rateController).balance);
        
        // Export the contract address and config as JSON
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "targetRateController": "', vm.toString(address(rateController)), '",\n',
                '  "addressesProvider": "', vm.toString(config.addressesProvider), '",\n',
                '  "usdxlToken": "', vm.toString(config.usdxlToken), '",\n',
                '  "usdxlReserve": "', vm.toString(config.usdxlReserve), '",\n',
                '  "usdt0Reserve": "', vm.toString(config.usdt0Reserve), '",\n',
                '  "usdxlPriceFeed": "', vm.toString(config.usdxlPriceFeed), '",\n',
                '  "usdt0PriceFeed": "', vm.toString(config.usdt0PriceFeed), '",\n',
                '  "wrappedHypeGateway": "', vm.toString(config.wrappedHypeGateway), '",\n',
                '  "initialRate": "', vm.toString(config.initialRate), '",\n',
                '  "initialETHAmount": "', vm.toString(config.initialETHAmount), '"\n',
                "}\n"
            )
        );
        vm.writeFile("script/output/999/target-rate-controller.json", json);
        
        console2.log("Deployment data saved to: script/output/999/target-rate-controller.json");
    }
}
