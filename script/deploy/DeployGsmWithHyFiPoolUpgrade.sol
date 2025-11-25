// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {GsmWithHyFiPool} from "src/contracts/facilitators/gsm/GsmWithHyFiPool.sol";
import {Gsm} from "src/contracts/facilitators/gsm/Gsm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployGsmWithHyFiPoolUpgrade
 * @notice Deployment script to upgrade existing GSM to HyFi Pool integrated version
 */
contract DeployGsmWithHyFiPoolUpgrade is Script {
    struct UpgradeConfig {
        address gsmProxy; // Address of the existing GSM proxy
        address proxyAdmin; // Address of the proxy admin
        address hyfiAddressesProvider; // HyFi Pool addresses provider
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
            hyfiAddressesProvider: 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594, // HyFi Pool addresses provider
            usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
            gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb // GSM owner address
        });

        console2.log("=== GSM Upgrade to HyFi Pool Script ===");
        console2.log("Deployer:", deployer);
        console2.log("GSM Proxy:", config.gsmProxy);
        console2.log("Proxy Admin:", config.proxyAdmin);
        console2.log("HyFi Pool Addresses Provider:", config.hyfiAddressesProvider);
        console2.log("USDT0 Token:", config.usdt0Token);
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("Admin:", config.gsmOwner);
        
        // Validate configuration
        require(config.gsmProxy != address(0), "INVALID_GSM_PROXY");
        require(config.proxyAdmin != address(0), "INVALID_PROXY_ADMIN");
        require(config.hyfiAddressesProvider != address(0), "INVALID_HYFI_PROVIDER");
        require(config.usdt0Token != address(0), "INVALID_USDT0_TOKEN");
        require(config.usdxlToken != address(0), "INVALID_USDXL_TOKEN");
        require(config.gsmOwner != address(0), "INVALID_ADMIN");

        vm.startBroadcast(deployerPrivateKey);

        GsmWithHyFiPool newGsmImpl = new GsmWithHyFiPool(
            config.usdxlToken,
            config.usdt0Token,
            Gsm(config.gsmProxy).PRICE_STRATEGY(),
            config.hyfiAddressesProvider
        );

        vm.stopBroadcast();

        console2.log("\n=== Deploy Summary ===");
        console2.log("New GSM Implementation:", address(newGsmImpl));
        console2.log("GSM Proxy (upgraded):", config.gsmProxy);
        console2.log("Proxy Admin:", config.proxyAdmin);
        console2.log("HyFi Pool Addresses Provider:", config.hyfiAddressesProvider);
    }
}
