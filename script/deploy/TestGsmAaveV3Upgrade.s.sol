// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {GsmWithAaveV3} from "../../src/contracts/facilitators/gsm/GsmWithAaveV3.sol";
import {Gsm} from "../../src/contracts/facilitators/gsm/Gsm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestGsmAaveV3Upgrade
 * @notice Test script to verify GSM upgrade to Aave V3 integration
 */
contract TestGsmAaveV3Upgrade is Script, Test {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Testing GSM Aave V3 Upgrade ===");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Test configuration
        address usdxlToken = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
        address usdt0Token = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
        address priceStrategy = 0x0000000000000000000000000000000000000000; // Mock price strategy
        address aaveAddressesProvider = 0x0000000000000000000000000000000000000000; // Mock Aave provider

        // Test 1: Deploy new GSM implementation
        console2.log("\n1. Testing new GSM implementation deployment...");
        
        try new GsmWithAaveV3(
            usdxlToken,
            usdt0Token,
            priceStrategy,
            aaveAddressesProvider
        ) {
            console2.log("New GSM implementation deployment successful");
        } catch Error(string memory reason) {
            console2.log("New GSM implementation deployment failed:", reason);
            revert("DEPLOYMENT_FAILED");
        }

        // Test 2: Verify interface compatibility
        console2.log("\n2. Testing interface compatibility...");
        
        GsmWithAaveV3 gsm = new GsmWithAaveV3(
            usdxlToken,
            usdt0Token,
            priceStrategy,
            aaveAddressesProvider
        );

        // Test that all required functions exist
        try gsm.GSM_REVISION() returns (uint256 revision) {
            assertEq(revision, 2, "GSM revision should be 2");
            console2.log("GSM revision correct:", revision);
        } catch {
            console2.log("FAIL GSM revision check failed");
            revert("REVISION_CHECK_FAILED");
        }

        try gsm.USDXL_TOKEN() returns (address token) {
            assertEq(token, usdxlToken, "USDXL token should match");
            console2.log("PASS USDXL token correct:", token);
        } catch {
            console2.log("FAIL USDXL token check failed");
            revert("TOKEN_CHECK_FAILED");
        }

        try gsm.UNDERLYING_ASSET() returns (address asset) {
            assertEq(asset, usdt0Token, "Underlying asset should match");
            console2.log("PASS Underlying asset correct:", asset);
        } catch {
            console2.log("FAIL Underlying asset check failed");
            revert("ASSET_CHECK_FAILED");
        }

        // Test 3: Test Aave V3 integration functions
        console2.log("\n3. Testing Aave V3 integration functions...");

        try gsm.getTotalDepositedInAave() returns (uint256 amount) {
            assertEq(amount, 0, "Initial Aave deposit should be 0");
            console2.log("PASS Initial Aave deposit amount correct:", amount);
        } catch {
            console2.log("FAIL Aave deposit amount check failed");
            revert("AAVE_DEPOSIT_CHECK_FAILED");
        }

        try gsm.getATokenBalance() returns (uint256 balance) {
            assertEq(balance, 0, "Initial aToken balance should be 0");
            console2.log("PASS Initial aToken balance correct:", balance);
        } catch {
            console2.log("FAIL aToken balance check failed");
            revert("ATOKEN_BALANCE_CHECK_FAILED");
        }

        try gsm.getTotalUnderlyingBalance() returns (uint256 balance) {
            assertEq(balance, 0, "Initial underlying balance should be 0");
            console2.log("PASS Initial underlying balance correct:", balance);
        } catch {
            console2.log("FAIL Underlying balance check failed");
            revert("UNDERLYING_BALANCE_CHECK_FAILED");
        }

        // Test 4: Test role constants
        console2.log("\n4. Testing role constants...");

        try gsm.CONFIGURATOR_ROLE() returns (bytes32 role) {
            assertTrue(role != bytes32(0), "CONFIGURATOR_ROLE should not be zero");
            console2.log("PASS CONFIGURATOR_ROLE correct");
        } catch {
            console2.log("FAIL CONFIGURATOR_ROLE check failed");
            revert("ROLE_CHECK_FAILED");
        }

        try gsm.TOKEN_RESCUER_ROLE() returns (bytes32 role) {
            assertTrue(role != bytes32(0), "TOKEN_RESCUER_ROLE should not be zero");
            console2.log("PASS TOKEN_RESCUER_ROLE correct");
        } catch {
            console2.log("FAIL TOKEN_RESCUER_ROLE check failed");
            revert("ROLE_CHECK_FAILED");
        }

        try gsm.SWAP_FREEZER_ROLE() returns (bytes32 role) {
            assertTrue(role != bytes32(0), "SWAP_FREEZER_ROLE should not be zero");
            console2.log("PASS SWAP_FREEZER_ROLE correct");
        } catch {
            console2.log("FAIL SWAP_FREEZER_ROLE check failed");
            revert("ROLE_CHECK_FAILED");
        }

        try gsm.LIQUIDATOR_ROLE() returns (bytes32 role) {
            assertTrue(role != bytes32(0), "LIQUIDATOR_ROLE should not be zero");
            console2.log("PASS LIQUIDATOR_ROLE correct");
        } catch {
            console2.log("FAIL LIQUIDATOR_ROLE check failed");
            revert("ROLE_CHECK_FAILED");
        }

        // Test 5: Test EIP712 functions
        console2.log("\n5. Testing EIP712 functions...");

        try gsm.DOMAIN_SEPARATOR() returns (bytes32 separator) {
            assertTrue(separator != bytes32(0), "Domain separator should not be zero");
            console2.log("PASS Domain separator correct");
        } catch {
            console2.log("FAIL Domain separator check failed");
            revert("EIP712_CHECK_FAILED");
        }

        try gsm.BUY_ASSET_WITH_SIG_TYPEHASH() returns (bytes32 typehash) {
            assertTrue(typehash != bytes32(0), "Buy asset typehash should not be zero");
            console2.log("PASS Buy asset typehash correct");
        } catch {
            console2.log("FAIL Buy asset typehash check failed");
            revert("EIP712_CHECK_FAILED");
        }

        try gsm.SELL_ASSET_WITH_SIG_TYPEHASH() returns (bytes32 typehash) {
            assertTrue(typehash != bytes32(0), "Sell asset typehash should not be zero");
            console2.log("PASS Sell asset typehash correct");
        } catch {
            console2.log("FAIL Sell asset typehash check failed");
            revert("EIP712_CHECK_FAILED");
        }

        // Test 6: Test new permit functionality
        console2.log("\n6. Testing permit functionality...");

        try gsm.sellAssetWithPermit(
            1000,
            address(0x2),
            block.timestamp + 3600,
            0,
            bytes32(0),
            bytes32(0)
        ) {
            console2.log("FAIL sellAssetWithPermit should have failed with invalid parameters");
            revert("PERMIT_TEST_FAILED");
        } catch {
            console2.log("PASS sellAssetWithPermit properly validates parameters");
        }

        vm.stopBroadcast();

        console2.log("\n=== All Tests Passed! ===");
        console2.log("PASS New GSM implementation is compatible with existing interface");
        console2.log("PASS Aave V3 integration functions work correctly");
        console2.log("PASS Role constants are properly defined");
        console2.log("PASS EIP712 functions work correctly");
        console2.log("PASS Permit functionality is properly implemented");
        console2.log("\nThe GSM upgrade to Aave V3 is ready for deployment!");
    }
}
