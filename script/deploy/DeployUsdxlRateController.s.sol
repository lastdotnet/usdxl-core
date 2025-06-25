// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {UsdxlInterestRateController} from "../../src/contracts/facilitators/hyfi/interestStrategy/UsdxlInterestRateController.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeployUsdxlInterestRateController
 * @notice Deployment script for USDXL Interest Rate Controller
 */
contract DeployUsdxlInterestRateController is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Configuration - these should be set as environment variables
        address addressesProvider = vm.envAddress("ADDRESSES_PROVIDER");
        address usdxlToken = vm.envAddress("USDXL_TOKEN");
        address usdxlOracle = vm.envAddress("USDXL_ORACLE");
        address usdxlReserve = vm.envAddress("USDXL_RESERVE");
        uint256 initialRate = vm.envUint("INITIAL_RATE"); // Should be in ray (e.g., 0.08e27 for 8%)
        
        console2.log("Deploying USDXL Interest Rate Controller...");
        console2.log("Deployer:", deployer);
        console2.log("Addresses Provider:", addressesProvider);
        console2.log("USDXL Token:", usdxlToken);
        console2.log("USDXL Oracle:", usdxlOracle);
        console2.log("USDXL Reserve:", usdxlReserve);
        console2.log("Initial Rate:", initialRate);
        
        vm.startBroadcast(deployerPrivateKey);
        
        UsdxlInterestRateController rateController = new UsdxlInterestRateController(
            addressesProvider,
            usdxlToken,
            usdxlOracle,
            usdxlReserve,
            initialRate
        );
        
        vm.stopBroadcast();
        
        console2.log("USDXL Interest Rate Controller deployed at:", address(rateController));
        
        // Export the contract address
        string memory deploymentData = vm.toString(address(rateController));
        vm.writeFile("deployments/usdxl-interest-rate-controller.txt", deploymentData);
        
        console2.log("Deployment data saved to: deployments/usdxl-interest-rate-controller.txt");
    }
} 