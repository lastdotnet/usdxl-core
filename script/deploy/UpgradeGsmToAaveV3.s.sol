// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {GsmWithAaveV3} from "../../src/contracts/facilitators/gsm/GsmWithAaveV3.sol";
import {Gsm} from "../../src/contracts/facilitators/gsm/Gsm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title UpgradeGsmToAaveV3
 * @notice Deployment script to upgrade existing GSM to Aave V3 integrated version
 */
contract UpgradeGsmToAaveV3 is Script {
    struct UpgradeConfig {
        address gsmProxy; // Address of the existing GSM proxy
        address proxyAdmin; // Address of the proxy admin
        address aaveAddressesProvider; // Aave V3 addresses provider
        address usdt0Token; // USDT0 token address
        address usdxlToken; // USDXL token address
        address gsmOwner; // GSM owner address for the upgrade
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));
        
        // Configuration - UPDATE THESE ADDRESSES FOR YOUR DEPLOYMENT
        UpgradeConfig memory config = UpgradeConfig({
            gsmProxy: 0xcb17105F6A7A75D1F1C91317a4621d9AaAfe96Fd, // Existing GSM proxy address
            proxyAdmin: 0x582668B6AA564Bdb6380d5c4f80A59C49C65cA83, // Proxy admin address
            aaveAddressesProvider: 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594, // Aave V3 addresses provider
            usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
            gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb // GSM owner address
        });

        console2.log("=== GSM Upgrade to Aave V3 Script ===");
        console2.log("Deployer:", deployer);
        console2.log("GSM Proxy:", config.gsmProxy);
        console2.log("Proxy Admin:", config.proxyAdmin);
        console2.log("Aave Addresses Provider:", config.aaveAddressesProvider);
        console2.log("USDT0 Token:", config.usdt0Token);
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("Admin:", config.gsmOwner);
        
        // Validate configuration
        require(config.gsmProxy != address(0), "INVALID_GSM_PROXY");
        require(config.proxyAdmin != address(0), "INVALID_PROXY_ADMIN");
        require(config.aaveAddressesProvider != address(0), "INVALID_AAVE_PROVIDER");
        require(config.usdt0Token != address(0), "INVALID_USDT0_TOKEN");
        require(config.usdxlToken != address(0), "INVALID_USDXL_TOKEN");
        require(config.gsmOwner != address(0), "INVALID_ADMIN");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Get current GSM state before upgrade
        console2.log("\n1. Checking current GSM state...");
        Gsm currentGsm = Gsm(config.gsmProxy);
        
        address currentUnderlyingAsset = currentGsm.UNDERLYING_ASSET();
        address currentPriceStrategy = currentGsm.PRICE_STRATEGY();
        uint128 currentExposureCap = currentGsm.getExposureCap();
        uint256 currentBalance = IERC20(currentUnderlyingAsset).balanceOf(config.gsmProxy);
        
        console2.log("Current Underlying Asset:", currentUnderlyingAsset);
        console2.log("Current Price Strategy:", currentPriceStrategy);
        console2.log("Current Exposure Cap:", currentExposureCap);
        console2.log("Current USDT0 Balance:", currentBalance);

        // Verify the underlying asset matches USDT0
        require(currentUnderlyingAsset == config.usdt0Token, "UNDERLYING_ASSET_MISMATCH");

        // 2. Deploy new GSM implementation with Aave V3 integration
        console2.log("\n2. Deploying new GSM implementation with Aave V3 integration...");
        GsmWithAaveV3 newGsmImpl = new GsmWithAaveV3(
            config.usdxlToken,
            config.usdt0Token,
            currentPriceStrategy,
            config.aaveAddressesProvider
        );
        console2.log("New GSM Implementation deployed at:", address(newGsmImpl));

        // 3. Upgrade the proxy to new implementation
        console2.log("\n3. Upgrading GSM proxy to new implementation...");
        ProxyAdmin proxyAdmin = ProxyAdmin(config.proxyAdmin);
        
        // Check if deployer has admin rights
        require(proxyAdmin.owner() == deployer || deployer == config.gsmOwner, "INSUFFICIENT_PERMISSIONS");
        
        // Perform the upgrade
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(config.gsmProxy)), address(newGsmImpl));
        console2.log("GSM proxy upgraded successfully");

        // 4. Initialize the new implementation (if needed)
        console2.log("\n4. Initializing new GSM implementation...");
        GsmWithAaveV3 upgradedGsm = GsmWithAaveV3(config.gsmProxy);
        
        // Check if already initialized
        try upgradedGsm.GSM_REVISION() returns (uint256 revision) {
            console2.log("GSM revision:", revision);
            if (revision == 2) {
                console2.log("New implementation already initialized");
            }
        } catch {
            // If not initialized, initialize it
            console2.log("Initializing new GSM implementation...");
            upgradedGsm.initialize(config.gsmOwner, currentGsm.getUsdxlTreasury(), currentExposureCap);
            console2.log("New GSM implementation initialized");
        }

        // 5. Verify Aave V3 migration (happens automatically during initialization)
        console2.log("\n5. Verifying Aave V3 migration...");
        uint256 balanceAfterMigration = IERC20(config.usdt0Token).balanceOf(config.gsmProxy);
        uint256 aTokenBalance = upgradedGsm.getATokenBalance();
        uint256 totalDepositedInAave = upgradedGsm.getTotalDepositedInAave();
        
        console2.log("USDT0 balance after migration:", balanceAfterMigration);
        console2.log("aToken balance after migration:", aTokenBalance);
        console2.log("Total deposited in Aave V3:", totalDepositedInAave);
        
        if (totalDepositedInAave > 0) {
            console2.log("Migration completed successfully during initialization");
        } else {
            console2.log("No USDT0 balance was migrated (contract had no balance)");
        }

        // 6. Verify the upgrade
        console2.log("\n6. Verifying the upgrade...");
        
        // Check that the new implementation is working
        require(upgradedGsm.GSM_REVISION() == 2, "UPGRADE_VERIFICATION_FAILED");
        require(upgradedGsm.UNDERLYING_ASSET() == config.usdt0Token, "UNDERLYING_ASSET_VERIFICATION_FAILED");
        require(upgradedGsm.USDXL_TOKEN() == config.usdxlToken, "USDXL_TOKEN_VERIFICATION_FAILED");
        
        // Check Aave V3 integration
        uint256 totalUnderlyingBalance = upgradedGsm.getTotalUnderlyingBalance();
        
        console2.log("Total deposited in Aave V3:", totalDepositedInAave);
        console2.log("Current aToken balance:", aTokenBalance);
        console2.log("Total underlying balance:", totalUnderlyingBalance);

        vm.stopBroadcast();

        // 7. Export upgrade information to JSON
        console2.log("\n7. Exporting upgrade information...");
        _exportUpgradeInfo(address(newGsmImpl), config, totalDepositedInAave, aTokenBalance, totalUnderlyingBalance);

        console2.log("\n=== Upgrade Summary ===");
        console2.log("New GSM Implementation:", address(newGsmImpl));
        console2.log("GSM Proxy (upgraded):", config.gsmProxy);
        console2.log("Proxy Admin:", config.proxyAdmin);
        console2.log("Aave Addresses Provider:", config.aaveAddressesProvider);
        console2.log("Total deposited in Aave V3:", totalDepositedInAave);
        console2.log("Current aToken balance:", aTokenBalance);
        console2.log("Total underlying balance:", totalUnderlyingBalance);
        console2.log("\nUpgrade completed successfully!");
        console2.log("The GSM now integrates with Aave V3 for yield generation.");
        console2.log("Existing USDT0 balance was automatically migrated to Aave V3 during initialization.");
        console2.log("All new deposits and withdrawals will go through Aave V3.");
        console2.log("Interest earned will be kept by the GSM for admin withdrawal.");
    }

    /**
     * @notice Export upgrade information to JSON files using the same pattern as DeployUsdxlFileUtils
     * @param newGsmImpl The new GSM implementation address
     * @param config The upgrade configuration
     * @param totalDepositedInAave The total amount deposited in Aave V3
     * @param aTokenBalance The current aToken balance
     * @param totalUnderlyingBalance The total underlying balance
     */
    function _exportUpgradeInfo(
        address newGsmImpl,
        UpgradeConfig memory config,
        uint256 totalDepositedInAave,
        uint256 aTokenBalance,
        uint256 totalUnderlyingBalance
    ) internal {
        string memory name = vm.envOr("FOUNDRY_EXPORTS_NAME", string("gsm-aave-v3-upgrade"));
        
        // Serialize addresses
        string memory json = vm.serializeAddress("upgrade", "newGsmImplementation", newGsmImpl);
        json = vm.serializeAddress("upgrade", "gsmProxy", config.gsmProxy);
        json = vm.serializeAddress("upgrade", "proxyAdmin", config.proxyAdmin);
        json = vm.serializeAddress("upgrade", "aaveAddressesProvider", config.aaveAddressesProvider);
        json = vm.serializeAddress("upgrade", "usdt0Token", config.usdt0Token);
        json = vm.serializeAddress("upgrade", "usdxlToken", config.usdxlToken);
        json = vm.serializeAddress("upgrade", "admin", config.gsmOwner);
        
        // Serialize numbers
        json = vm.serializeUint("upgrade", "totalDepositedInAave", totalDepositedInAave);
        json = vm.serializeUint("upgrade", "aTokenBalance", aTokenBalance);
        json = vm.serializeUint("upgrade", "totalUnderlyingBalance", totalUnderlyingBalance);
        json = vm.serializeUint("upgrade", "upgradeTimestamp", block.timestamp);
        json = vm.serializeUint("upgrade", "upgradeBlock", block.number);
        
        // Serialize strings
        json = vm.serializeString("upgrade", "upgradeType", "GSM_TO_AAVE_V3");
        
        // Write JSON files
        string memory root = vm.projectRoot();
        string memory chainOutputFolder = string(abi.encodePacked("/script/output/", vm.toString(block.chainid), "/"));
        
        // Write timestamped file
        vm.writeJson(json, string(abi.encodePacked(root, chainOutputFolder, name, "-", vm.toString(block.timestamp), ".json")));
        
        // Write latest file
        vm.writeJson(json, string(abi.encodePacked(root, chainOutputFolder, name, "-latest.json")));
        
        console2.log("Upgrade information exported to:", string(abi.encodePacked(name, "-", vm.toString(block.timestamp), ".json")));
        console2.log("Latest upgrade info available at:", string(abi.encodePacked(name, "-latest.json")));
    }

}
