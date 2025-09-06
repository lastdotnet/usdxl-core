// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoBuyFixedFeeStrategy} from "../../src/contracts/facilitators/gsm/feeStrategy/NoBuyFixedFeeStrategy.sol";
import {DeployUsdxlFileUtils} from "../../src/deployments/utils/DeployUsdxlFileUtils.sol";

/**
 * @title DeployFixedFeeStrategy
 * @notice Deployment script for a new Fixed Fee Strategy
 */
contract DeployFixedFeeStrategy is Script {
    struct FeeStrategyConfig {
        uint256 buyFee; // Buy fee in basis points (e.g., 0.02e4 = 2%)
        uint256 sellFee; // Sell fee in basis points (e.g., 0 = 0%)
        string instanceId; // Instance ID for file naming
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));

        console2.log("=== Fixed Fee Strategy Deployment Script ===");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Fixed Fee Strategy
        console2.log("\n1. Deploying Fixed Fee Strategy...");
        NoBuyFixedFeeStrategy feeStrategy = new NoBuyFixedFeeStrategy();
        console2.log("Fixed Fee Strategy deployed at:", address(feeStrategy));

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("Fixed Fee Strategy:", address(feeStrategy));
    }

    /**
     * @notice Export contract addresses to JSON files
     * @param feeStrategy The fee strategy contract address
     * @param buyFee The buy fee value
     * @param sellFee The sell fee value
     * @param instanceId The instance ID for file naming
     */
    function _exportContracts(
        address feeStrategy,
        uint256 buyFee,
        uint256 sellFee,
        string memory instanceId
    ) internal {
        // Export all contract addresses
        DeployUsdxlFileUtils.exportContract(instanceId, "feeStrategy", feeStrategy);
        
        // Export configuration values
        DeployUsdxlFileUtils.exportContract(instanceId, "buyFee", address(uint160(buyFee)));
        DeployUsdxlFileUtils.exportContract(instanceId, "sellFee", address(uint160(sellFee)));
        
        console2.log("\n=== Contract Addresses Exported ===");
        console2.log("Fee Strategy:", feeStrategy);
        console2.log("Buy Fee:", buyFee, "bps");
        console2.log("Sell Fee:", sellFee, "bps");
        console2.log("Instance ID:", instanceId);
        console2.log("Files saved to: script/output/{chainId}/fixed-fee-strategy-{timestamp}.json");
        console2.log("Files saved to: script/output/{chainId}/fixed-fee-strategy-latest.json");
    }
}
