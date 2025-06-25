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
        address multisig = 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb;
        
        // Configuration
        address addressesProvider = 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594;
        address usdxlToken = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
        address usdxlOracle = 0xe52085B9BBc0beF8294ecD0546f8cb5158BB2eAA;
        address usdxlReserve = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
        address wrappedHypeGateway = 0xd1EF87FeFA83154F83541b68BD09185e15463972; // WrappedHypeGateway address
        uint256 initialRate = 0.1485e27; // 14.85% in ray
        uint256 initialPerpetualLoanAmount = 0.01e18; // 0.01 USDXL
        uint256 initialETHAmount = 0.1 ether; // 0.1 ETH for perpetual loan

        console2.log("Deploying USDXL Interest Rate Controller...");
        console2.log("Deployer:", deployer);
        console2.log("Addresses Provider:", addressesProvider);
        console2.log("USDXL Token:", usdxlToken);
        console2.log("USDXL Oracle:", usdxlOracle);
        console2.log("USDXL Reserve:", usdxlReserve);
        console2.log("WrappedHypeGateway:", wrappedHypeGateway);
        console2.log("Initial Rate:", initialRate);
        console2.log("Initial Perpetual Loan Amount:", initialPerpetualLoanAmount);
        console2.log("Initial ETH Amount:", initialETHAmount);

        vm.startBroadcast(deployerPrivateKey);
        
        UsdxlInterestRateController rateController = new UsdxlInterestRateController{value: initialETHAmount}(
            addressesProvider,
            usdxlToken,
            usdxlOracle,
            usdxlReserve,
            initialRate,
            deployer,
            initialPerpetualLoanAmount,
            wrappedHypeGateway
        );

        UsdxlInterestRateController rateController = UsdxlInterestRateController(payable(0xb02b1A83791F057823a7ea20969abAd79987EBBf));

        rateController.updateExecutor(deployer, true);
        rateController.transferOwnership(multisig);
        
        vm.stopBroadcast();
        
        console2.log("USDXL Interest Rate Controller deployed at:", address(rateController));
        console2.log("Initial ETH balance:", address(rateController).balance);
        
        // Export the contract address and config as JSON
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "rateController": "', vm.toString(address(rateController)), '"\n',
                "}\n"
            )
        );
        vm.writeFile("script/output/999/interest-rate-controller.json", json);
        
        console2.log("Deployment data saved to: script/output/999/interest-rate-controller.json");
    }
} 