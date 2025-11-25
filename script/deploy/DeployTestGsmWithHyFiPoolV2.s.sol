// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GsmWithHyFiPoolV2} from "src/contracts/facilitators/gsm/GsmWithHyFiPoolV2.sol";
import {Gsm} from "src/contracts/facilitators/gsm/Gsm.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployTestGsmWithHyFiPoolV2 is Script {
    struct UpgradeConfig {
        address gsmProxy; // Address of the existing GSM proxy
        address proxyAdmin; // Address of the proxy admin
        address hyfiAddressesProvider; // HyFi Pool addresses provider
        address usdt0Token; // USDT0 token address
        address usdxlToken; // USDXL token address
        address gsmOwner; // GSM owner address for the upgrade
        address balancerRouter; // Balancer router address
        address permit2; // Permit2 address
        address balancerPool; // Balancer pool address
        address gluexRouter; // GlueX router address
    }

    function run() public {
        deployGsmWithHyFiPoolV2();
    }

    function deployGsmWithHyFiPoolV2() public {
        // Configuration - UPDATE THESE ADDRESSES FOR YOUR DEPLOYMENT
        UpgradeConfig memory config = UpgradeConfig({
            gsmProxy: 0xcb17105F6A7A75D1F1C91317a4621d9AaAfe96Fd, // Existing GSM proxy address
            proxyAdmin: 0x582668B6AA564Bdb6380d5c4f80A59C49C65cA83, // Proxy admin address
            hyfiAddressesProvider: 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594, // HyFi Pool addresses provider
            usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
            gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // GSM owner address
            balancerRouter: 0xA8920455934Da4D853faac1f94Fe7bEf72943eF1, // Balancer router address
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3, // Permit2 address
            balancerPool: 0x7029f8637a9DcF42f7aEEB1461f059e3cad0A119, // Balancer pool address
            gluexRouter: 0xe95F6EAeaE1E4d650576Af600b33D9F7e5f9f7fd // GlueX router address
        });

        address deployer = vm.addr(vm.envUint("EXECUTOR_PRIVATE_KEY"));

        vm.startBroadcast(vm.envUint("EXECUTOR_PRIVATE_KEY"));

        GsmWithHyFiPoolV2 newGsmImpl = new GsmWithHyFiPoolV2(
            config.usdxlToken,
            config.usdt0Token,
            Gsm(config.gsmProxy).PRICE_STRATEGY(),
            config.hyfiAddressesProvider,
            config.balancerRouter,
            config.permit2,
            config.gluexRouter
        );

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint128,address)",
            deployer,
            Gsm(config.gsmProxy).getUsdxlTreasury(),
            Gsm(config.gsmProxy).getExposureCap(),
            config.balancerPool
        );
        
        TransparentUpgradeableProxy newGsmProxy = new TransparentUpgradeableProxy(
            address(newGsmImpl),
            address(proxyAdmin), // Use ProxyAdmin as admin
            initData
        );

        Gsm(address(newGsmProxy)).updateFeeStrategy(Gsm(config.gsmProxy).getFeeStrategy());

        IAccessControl(address(newGsmProxy)).grantRole(GsmWithHyFiPoolV2(address(newGsmProxy)).HARVESTER_ROLE(), deployer);

        vm.stopBroadcast();

        console2.log("New GSM Proxy deployed at:", address(newGsmProxy));
    }
}