// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Gsm} from "../../src/contracts/facilitators/gsm/Gsm.sol";
import {FixedPriceStrategy} from "../../src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "../../src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IUsdxlToken} from "../../src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeployUsdxlFileUtils} from "../../src/deployments/utils/DeployUsdxlFileUtils.sol";

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

        vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));
        
        // Configuration
        Usdt0GsmConfig memory config = Usdt0GsmConfig({
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
            usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address - UPDATE THIS
            usdxlAdmin: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // USDXL admin address
            gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // Final GSM owner address
            treasury: 0xdC6E5b7aA6fCbDECC1Fda2b1E337ED8569730288, // Collector address
            priceRatio: 1e18, // 1:1 price ratio (1 USDT0 = 1 USDXL)
            buyFee: 0.01e4, // 1% buy fee
            sellFee: 0, // 0% sell fee
            exposureCap: 10000000e6, // 10M USDT0 exposure cap (assuming 6 decimals)
            gsmCapacity: 10000000e18 // 10M USDXL capacity
        });

        console2.log("=== USDT0 GSM Deployment Script ===");
        console2.log("Deployer:", deployer);
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("USDT0 Token:", config.usdt0Token);
        console2.log("USDXL Admin:", config.usdxlAdmin);
        console2.log("Final GSM Owner:", config.gsmOwner);
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

        // 4. Deploy ProxyAdmin
        console2.log("\n4. Deploying ProxyAdmin...");
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console2.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // 5. Deploy GSM Proxy
        console2.log("\n5. Deploying GSM Proxy...");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint128)",
            deployer,
            config.treasury,
            config.exposureCap
        );
        TransparentUpgradeableProxy gsmProxy = new TransparentUpgradeableProxy(
            address(gsmImpl),
            address(proxyAdmin), // Use ProxyAdmin as admin
            initData
        );
        console2.log("GSM Proxy deployed at:", address(gsmProxy));

        // 6. Set Fee Strategy through ProxyAdmin
        console2.log("\n6. Setting Fee Strategy...");
        Gsm(address(gsmProxy)).updateFeeStrategy(address(feeStrategy));
        console2.log("Fee strategy set successfully");

        // 7. Add GSM as USDXL Facilitator (using deployer if they are USDXL admin)
        if (deployer == config.usdxlAdmin) {
            console2.log("\n7. Adding GSM as USDXL Facilitator...");
            IUsdxlToken(config.usdxlToken).addFacilitator(
                address(gsmProxy),
                "USDT0 GSM Facilitator",
                uint128(config.gsmCapacity)
            );
            console2.log("GSM added as USDXL facilitator successfully");
        } else {
            console2.log("Skipping GSM capacity setting as non USDXL admin");
        }

        // 8. Transfer GSM DEFAULT_ADMIN_ROLE to final owner
        console2.log("\n8. Transferring GSM DEFAULT_ADMIN_ROLE to final owner...");
        Gsm(address(gsmProxy)).grantRole(Gsm(address(gsmProxy)).DEFAULT_ADMIN_ROLE(), config.gsmOwner);
        Gsm(address(gsmProxy)).revokeRole(Gsm(address(gsmProxy)).DEFAULT_ADMIN_ROLE(), deployer);
        console2.log("GSM DEFAULT_ADMIN_ROLE transferred to:", config.gsmOwner);

        // 9. Transfer proxy admin to final owner
        console2.log("\n9. Transferring ownership to final owner...");
        proxyAdmin.transferOwnership(config.gsmOwner);
        console2.log("Proxy admin transferred to:", config.gsmOwner);s

        vm.stopBroadcast();

        // Export deployment addresses
        _exportContracts(
            address(priceStrategy),
            address(feeStrategy),
            address(gsmImpl),
            address(gsmProxy),
            address(proxyAdmin),
            config.gsmOwner,
            config.treasury,
            config.exposureCap,
            config.gsmCapacity
        );

        console2.log("\n=== Deployment Summary ===");
        console2.log("Fixed Price Strategy:", address(priceStrategy));
        console2.log("Fixed Fee Strategy:", address(feeStrategy));
        console2.log("GSM Implementation:", address(gsmImpl));
        console2.log("GSM Proxy:", address(gsmProxy));
        console2.log("GSM Owner:", config.gsmOwner);
        console2.log("Treasury:", config.treasury);
        console2.log("Exposure Cap:", config.exposureCap);
        console2.log("Initial GSM Capacity: 0 (to be set after ownership transfer)");
        console2.log("Target GSM Capacity:", config.gsmCapacity);
    }

    /**
     * @notice Export contract addresses to JSON files
     * @param priceStrategy The price strategy contract address
     * @param feeStrategy The fee strategy contract address
     * @param gsmImpl The GSM implementation contract address
     * @param gsmProxy The GSM proxy contract address
     * @param proxyAdmin The proxy admin contract address
     * @param gsmOwner The GSM owner address
     * @param treasury The treasury address
     * @param exposureCap The exposure cap value
     * @param gsmCapacity The GSM capacity value
     */
    function _exportContracts(
        address priceStrategy,
        address feeStrategy,
        address gsmImpl,
        address gsmProxy,
        address proxyAdmin,
        address gsmOwner,
        address treasury,
        uint256 exposureCap,
        uint256 gsmCapacity
    ) internal {
        // Get instance ID from environment or use default
        string memory instanceId = "usdt0-gsm";
        
        // Export all contract addresses
        DeployUsdxlFileUtils.exportContract(instanceId, "priceStrategy", priceStrategy);
        DeployUsdxlFileUtils.exportContract(instanceId, "feeStrategy", feeStrategy);
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmImpl", gsmImpl);
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmProxy", gsmProxy);
        DeployUsdxlFileUtils.exportContract(instanceId, "proxyAdmin", proxyAdmin);
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmOwner", gsmOwner);
        DeployUsdxlFileUtils.exportContract(instanceId, "treasury", treasury);
        
        // Export configuration values
        DeployUsdxlFileUtils.exportContract(instanceId, "exposureCap", address(uint160(exposureCap)));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmCapacity", address(uint160(gsmCapacity)));
        
        console2.log("\n=== Contract Addresses Exported ===");
        console2.log("Price Strategy:", priceStrategy);
        console2.log("Fee Strategy:", feeStrategy);
        console2.log("GSM Implementation:", gsmImpl);
        console2.log("GSM Proxy:", gsmProxy);
        console2.log("ProxyAdmin:", proxyAdmin);
        console2.log("GSM Owner:", gsmOwner);
        console2.log("Treasury:", treasury);
        console2.log("Exposure Cap:", exposureCap);
        console2.log("GSM Capacity:", gsmCapacity);
        console2.log("Instance ID:", instanceId);
        console2.log("Files saved to: script/output/{chainId}/usdt0-gsm-{timestamp}.json");
        console2.log("Files saved to: script/output/{chainId}/usdt0-gsm-latest.json");
    }
} 