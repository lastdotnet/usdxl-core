// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {GsmWithAaveV3} from "../../src/contracts/facilitators/gsm/GsmWithAaveV3.sol";
import {FixedPriceStrategy} from "../../src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "../../src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IUsdxlToken} from "../../src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeployUsdxlFileUtils} from "../../src/deployments/utils/DeployUsdxlFileUtils.sol";

/**
 * @title DeployGsmWithAaveV3
 * @notice Deployment script for GSM with Aave V3 integration
 */
contract DeployGsmWithAaveV3 is Script {
    struct GsmWithAaveV3Config {
        address usdxlToken;
        address underlyingAsset;
        address usdxlAdmin;
        address gsmOwner;
        address treasury;
        uint256 priceRatio; // Price ratio from underlying asset to USDXL (in WAD)
        uint256 buyFee; // Buy fee in basis points (e.g., 0.02e4 = 2%)
        uint256 sellFee; // Sell fee in basis points (e.g., 0 = 0%)
        uint128 exposureCap; // Maximum exposure cap in underlying asset terms
        uint256 gsmCapacity; // GSM facilitator capacity in USDXL terms
        address aaveAddressesProvider; // Aave V3 addresses provider
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.setEnv('FOUNDRY_ROOT_CHAINID', vm.toString(block.chainid));
        
        // Configuration - Update these addresses for your deployment
        GsmWithAaveV3Config memory config = GsmWithAaveV3Config({
            usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
            underlyingAsset: 0xA0b86a33E6441b8C4c8c0E4A8C0c4f0e4A8c0c4f, // Real USDC on Ethereum
            usdxlAdmin: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // USDXL admin address
            gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // Final GSM owner address
            treasury: 0xdC6E5b7aA6fCbDECC1Fda2b1E337ED8569730288, // Collector address
            priceRatio: 1e18, // 1:1 price ratio (1 underlying asset = 1 USDXL)
            buyFee: 0.01e4, // 1% buy fee
            sellFee: 0, // 0% sell fee
            exposureCap: 10000000e6, // 10M underlying asset exposure cap (assuming 6 decimals)
            gsmCapacity: 10000000e18, // 10M USDXL capacity
            aaveAddressesProvider: 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e // Aave V3 addresses provider on Ethereum
        });

        vm.startBroadcast(deployerPrivateKey);

        console2.log("Deploying GSM with Aave V3 integration...");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);

        // Deploy price strategy
        console2.log("Deploying FixedPriceStrategy...");
        FixedPriceStrategy priceStrategy = new FixedPriceStrategy(
            config.priceRatio,
            config.underlyingAsset,
            6 // Assuming 6 decimals for underlying asset
        );
        console2.log("FixedPriceStrategy deployed at:", address(priceStrategy));

        // Deploy fee strategy
        console2.log("Deploying FixedFeeStrategy...");
        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(
            config.buyFee,
            config.sellFee
        );
        console2.log("FixedFeeStrategy deployed at:", address(feeStrategy));

        // Deploy GSM implementation
        console2.log("Deploying GsmWithAaveV3 implementation...");
        GsmWithAaveV3 gsmImplementation = new GsmWithAaveV3(
            config.usdxlToken,
            config.underlyingAsset,
            address(priceStrategy),
            config.aaveAddressesProvider
        );
        console2.log("GsmWithAaveV3 implementation deployed at:", address(gsmImplementation));

        // Deploy proxy admin
        console2.log("Deploying ProxyAdmin...");
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console2.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // Deploy GSM proxy
        console2.log("Deploying GSM proxy...");
        TransparentUpgradeableProxy gsmProxy = new TransparentUpgradeableProxy(
            address(gsmImplementation),
            address(proxyAdmin),
            abi.encodeWithSelector(
                GsmWithAaveV3.initialize.selector,
                config.gsmOwner,
                config.treasury,
                config.exposureCap
            )
        );
        console2.log("GSM proxy deployed at:", address(gsmProxy));

        // Cast proxy to GSM interface
        GsmWithAaveV3 gsm = GsmWithAaveV3(address(gsmProxy));

        // Update fee strategy
        console2.log("Setting fee strategy...");
        gsm.updateFeeStrategy(address(feeStrategy));

        // Add GSM as facilitator to USDXL token
        console2.log("Adding GSM as facilitator to USDXL token...");
        IUsdxlToken usdxlToken = IUsdxlToken(config.usdxlToken);
        usdxlToken.addFacilitator(
            address(gsm),
            "GSM with Aave V3",
            config.gsmCapacity
        );

        // Transfer proxy admin ownership
        console2.log("Transferring proxy admin ownership...");
        proxyAdmin.transferOwnership(config.gsmOwner);

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("GSM Proxy:", address(gsm));
        console2.log("GSM Implementation:", address(gsmImplementation));
        console2.log("Proxy Admin:", address(proxyAdmin));
        console2.log("Price Strategy:", address(priceStrategy));
        console2.log("Fee Strategy:", address(feeStrategy));
        console2.log("USDXL Token:", config.usdxlToken);
        console2.log("Underlying Asset:", config.underlyingAsset);
        console2.log("Aave Addresses Provider:", config.aaveAddressesProvider);
        console2.log("Aave Pool:", gsm.AAVE_POOL());
        console2.log("aToken:", gsm.ATOKEN());
        console2.log("Treasury:", gsm.getUsdxlTreasury());
        console2.log("Exposure Cap:", gsm.getExposureCap());
        console2.log("GSM Capacity:", config.gsmCapacity);
        console2.log("GSM Revision:", gsm.GSM_REVISION());

        // Save deployment info
        _saveDeploymentInfo(address(gsm), address(gsmImplementation), address(proxyAdmin));

        console2.log("\nDeployment completed successfully!");
    }

    function _saveDeploymentInfo(
        address gsmProxy,
        address gsmImplementation,
        address proxyAdmin
    ) internal {
        string memory deploymentInfo = string(
            abi.encodePacked(
                '{"gsmProxy":"', vm.toString(gsmProxy), '",',
                '"gsmImplementation":"', vm.toString(gsmImplementation), '",',
                '"proxyAdmin":"', vm.toString(proxyAdmin), '",',
                '"chainId":', vm.toString(block.chainid), ',',
                '"timestamp":', vm.toString(block.timestamp), '}'
            )
        );

        string memory fileName = string(
            abi.encodePacked(
                "deployments/gsm-with-aave-v3-",
                vm.toString(block.chainid),
                ".json"
            )
        );

        vm.writeFile(fileName, deploymentInfo);
        console2.log("Deployment info saved to:", fileName);
    }
}
