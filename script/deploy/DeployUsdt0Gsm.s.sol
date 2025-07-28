// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Gsm} from "../../src/contracts/facilitators/gsm/Gsm.sol";
import {FixedPriceStrategy} from "../../src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "../../src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {AdminUpgradeabilityProxy} from "@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol";
import {IUsdxlToken} from "../../src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title DeployUsdt0Gsm
 * @notice Deployment script for USDT0 GSM module for USDXL
 */
contract DeployUsdt0Gsm is Script {
    struct Usdt0GsmConfig {
        address usdxlToken;
        address usdt0Token;
        address usdxlAdmin;
        address gsmOwner;
        address treasury;
        uint256 priceRatio; // Price ratio from USDT0 to USDXL (in WAD)
        uint256 buyFee; // Buy fee in basis points (e.g., 0.02e4 = 2%)
        uint256 sellFee; // Sell fee in basis points (e.g., 0 = 0%)
        uint128 exposureCap; // Maximum exposure cap in USDT0 terms
        uint256 gsmCapacity; // GSM facilitator capacity in USDXL terms
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Configuration
        Usdt0GsmConfig memory config = Usdt0GsmConfig({
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
            usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address - UPDATE THIS
            usdxlAdmin: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // USDXL admin address
            gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // GSM owner address
            treasury: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // Treasury address
            priceRatio: 1e18, // 1:1 price ratio (1 USDT0 = 1 USDXL)
            buyFee: 0.02e4, // 2% buy fee
            sellFee: 0, // 0% sell fee
            exposureCap: 1000000e6, // 1M USDT0 exposure cap (assuming 6 decimals)
            gsmCapacity: 1000000e18 // 1M USDXL capacity
        });

        console2.log("=== USDT0 GSM Deployment Script ===");
        console2.log("Deployer:", deployer);
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("USDT0 Token:", config.usdt0Token);
        console2.log("USDXL Admin:", config.usdxlAdmin);
        console2.log("GSM Owner:", config.gsmOwner);
        console2.log("Treasury:", config.treasury);
        console2.log("Price Ratio:", config.priceRatio);
        console2.log("Buy Fee:", config.buyFee, "bps");
        console2.log("Sell Fee:", config.sellFee, "bps");
        console2.log("Exposure Cap:", config.exposureCap, "USDT0");
        console2.log("GSM Capacity:", config.gsmCapacity, "USDXL");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Fixed Price Strategy
        console2.log("\n1. Deploying Fixed Price Strategy...");
        FixedPriceStrategy priceStrategy = new FixedPriceStrategy(
            config.priceRatio,
            config.usdt0Token,
            IERC20Metadata(config.usdt0Token).decimals()
        );
        console2.log("Fixed Price Strategy deployed at:", address(priceStrategy));

        // 2. Deploy Fixed Fee Strategy
        console2.log("\n2. Deploying Fixed Fee Strategy...");
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(
            config.buyFee,
            config.sellFee
        );
        console2.log("Fixed Fee Strategy deployed at:", address(feeStrategy));

        // 3. Deploy GSM Implementation
        console2.log("\n3. Deploying GSM Implementation...");
        Gsm gsmImpl = new Gsm(
            config.usdxlToken,
            config.usdt0Token,
            address(priceStrategy)
        );
        console2.log("GSM Implementation deployed at:", address(gsmImpl));

        // 4. Deploy GSM Proxy
        console2.log("\n4. Deploying GSM Proxy...");
        AdminUpgradeabilityProxy gsmProxy = new AdminUpgradeabilityProxy(
            address(gsmImpl),
            config.usdxlAdmin,
            ""
        );
        console2.log("GSM Proxy deployed at:", address(gsmProxy));

        // 5. Initialize GSM
        console2.log("\n5. Initializing GSM...");
        Gsm(address(gsmProxy)).initialize(
            config.gsmOwner,
            config.treasury,
            config.exposureCap
        );
        console2.log("GSM initialized successfully");

        // 6. Set Fee Strategy
        console2.log("\n6. Setting Fee Strategy...");
        Gsm(address(gsmProxy)).updateFeeStrategy(address(feeStrategy));
        console2.log("Fee strategy set successfully");

        // 7. Add GSM as USDXL Facilitator
        console2.log("\n7. Adding GSM as USDXL Facilitator...");
        IUsdxlToken(config.usdxlToken).addFacilitator(
            address(gsmProxy),
            "USDT0 GSM Facilitator",
            uint128(config.gsmCapacity)
        );
        console2.log("GSM added as USDXL facilitator successfully");

        vm.stopBroadcast();

        // Export deployment results
        console2.log("\n=== Deployment Summary ===");
        console2.log("Fixed Price Strategy:", address(priceStrategy));
        console2.log("Fixed Fee Strategy:", address(feeStrategy));
        console2.log("GSM Implementation:", address(gsmImpl));
        console2.log("GSM Proxy:", address(gsmProxy));
        console2.log("GSM Owner:", config.gsmOwner);
        console2.log("Treasury:", config.treasury);
        console2.log("Exposure Cap:", config.exposureCap);
        console2.log("GSM Capacity:", config.gsmCapacity);

        // Export to JSON for verification
        string memory deploymentData = vm.toString(address(priceStrategy));
        deploymentData = string(abi.encodePacked(deploymentData, "\n"));
        deploymentData = string(abi.encodePacked(deploymentData, "Fixed Fee Strategy: ", vm.toString(address(feeStrategy)), "\n"));
        deploymentData = string(abi.encodePacked(deploymentData, "GSM Implementation: ", vm.toString(address(gsmImpl)), "\n"));
        deploymentData = string(abi.encodePacked(deploymentData, "GSM Proxy: ", vm.toString(address(gsmProxy)), "\n"));
        
        vm.writeFile("deployments/usdt0-gsm-deployment.json", deploymentData);
        console2.log("\nDeployment data exported to: deployments/usdt0-gsm-deployment.json");
    }
} 