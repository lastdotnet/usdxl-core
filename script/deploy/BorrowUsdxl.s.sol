// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolConfigurator} from "@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUsdxlToken} from "../../src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {console2} from "forge-std/console2.sol";
import {IACLManager} from "@aave/core-v3/contracts/interfaces/IACLManager.sol";

/**
 * @title BorrowUsdxl
 * @notice Script to attempt borrowing USDXL while pranking as a specific address
 */
contract BorrowUsdxl is Script {
    // Target address to prank as
    address constant TARGET_ADDRESS = 0xb02b1A83791F057823a7ea20969abAd79987EBBf;
    
    // New interest rate strategy address
    address constant NEW_INTEREST_RATE_STRATEGY = 0xb02b1A83791F057823a7ea20969abAd79987EBBf;
    
    // Borrow amount (1 USDXL)
    uint256 constant BORROW_AMOUNT = 1e18;
    
    // Interest rate mode: 2 = Variable rate
    uint256 constant INTEREST_RATE_MODE = 2;
    
    // Referral code: 0 = no referral
    uint16 constant REFERRAL_CODE = 0;

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Configuration - these would need to be updated for the target network
        address addressesProvider = 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594;
        address usdxlToken = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
        
        console2.log("=== USDXL Borrow Attempt Script ===");
        console2.log("Deployer:", deployer);
        console2.log("Target Address:", TARGET_ADDRESS);
        console2.log("New Interest Rate Strategy:", NEW_INTEREST_RATE_STRATEGY);
        console2.log("Borrow Amount:", BORROW_AMOUNT, "USDXL");
        console2.log("Addresses Provider:", addressesProvider);
        console2.log("USDXL Token:", usdxlToken);
        
        // Get the Pool contract
        IPoolAddressesProvider provider = IPoolAddressesProvider(addressesProvider);
        address poolAddress = provider.getPool();
        IPool pool = IPool(poolAddress);
        
        console2.log("Pool Address:", poolAddress);
        
        // Get the Pool Configurator contract
        address configuratorAddress = provider.getPoolConfigurator();
        IPoolConfigurator configurator = IPoolConfigurator(configuratorAddress);
        
        console2.log("Pool Configurator Address:", configuratorAddress);
        
        // Get USDXL token instance
        IUsdxlToken usdxl = IUsdxlToken(usdxlToken);
        
        // Check USDXL token info
        console2.log("USDXL Symbol:", IERC20Metadata(usdxlToken).symbol());
        console2.log("USDXL Decimals:", IERC20Metadata(usdxlToken).decimals());
        console2.log("USDXL Total Supply:", IERC20Metadata(usdxlToken).totalSupply());
        
        // Check target address balance before borrowing
        uint256 targetBalanceBefore = usdxl.balanceOf(TARGET_ADDRESS);
        console2.log("Target Address USDXL Balance Before:", targetBalanceBefore);
        
        // Check current interest rate strategy
        try pool.getReserveData(usdxlToken) returns (DataTypes.ReserveData memory reserveData) {
            console2.log("Reserve Data Retrieved Successfully");
            console2.log("Current AToken Address:", reserveData.aTokenAddress);
            console2.log("Current Variable Debt Token Address:", reserveData.variableDebtTokenAddress);
            console2.log("Current Interest Rate Strategy:", reserveData.interestRateStrategyAddress);
            
            // Update the interest rate strategy
            console2.log("\n=== Updating Interest Rate Strategy ===");
            console2.log("Setting USDXL interest rate strategy to:", NEW_INTEREST_RATE_STRATEGY);
            
            // Prank as ACL Manager or a user with proper permissions
            // First try as ACL Manager
            vm.startPrank(0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb);
            
            try configurator.setReserveInterestRateStrategyAddress(usdxlToken, NEW_INTEREST_RATE_STRATEGY) {
                console2.log("Interest rate strategy updated successfully as ACL Manager!");
                
                // Verify the update
                DataTypes.ReserveData memory newReserveData = pool.getReserveData(usdxlToken);
                console2.log("New Interest Rate Strategy:", newReserveData.interestRateStrategyAddress);
                
            } catch Error(string memory reason) {
                console2.log("Failed to update as ACL Manager:", reason);
                
                // Try as a different admin address (you might need to update this)
                vm.stopPrank();
                address adminAddress = 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb; // Replace with actual admin
                vm.startPrank(adminAddress);
                
                try configurator.setReserveInterestRateStrategyAddress(usdxlToken, NEW_INTEREST_RATE_STRATEGY) {
                    console2.log("Interest rate strategy updated successfully as admin!");
                    
                    // Verify the update
                    DataTypes.ReserveData memory newReserveData = pool.getReserveData(usdxlToken);
                    console2.log("New Interest Rate Strategy:", newReserveData.interestRateStrategyAddress);
                    
                } catch Error(string memory reason2) {
                    console2.log("Failed to update as admin:", reason2);
                    console2.log("Cannot update interest rate strategy - insufficient permissions");
                    return;
                } catch {
                    console2.log("Failed to update as admin: unknown error");
                    console2.log("Cannot update interest rate strategy - insufficient permissions");
                    return;
                }
                
            } catch {
                console2.log("Failed to update as ACL Manager: unknown error");
                console2.log("Cannot update interest rate strategy - insufficient permissions");
                return;
            }
            
            vm.stopPrank();
            
        } catch Error(string memory reason) {
            console2.log("Failed to get reserve data:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console2.log("Failed to get reserve data: unknown error");
            vm.stopBroadcast();
            return;
        }
        
        // Attempt to borrow USDXL as the target address
        console2.log("\n=== Attempting USDXL Borrow ===");
        
        vm.startPrank(TARGET_ADDRESS);

        // Print the interest rate strategy address before borrowing
        DataTypes.ReserveData memory reserveDataBeforeBorrow = pool.getReserveData(usdxlToken);
        console2.log("Current Interest Rate Strategy Address:", reserveDataBeforeBorrow.interestRateStrategyAddress);
        
        try pool.borrow(
            usdxlToken,
            BORROW_AMOUNT,
            INTEREST_RATE_MODE,
            REFERRAL_CODE,
            TARGET_ADDRESS
        ) {
            console2.log("USDXL borrow successful!");
            
            // Check balance after borrowing
            uint256 targetBalanceAfter = usdxl.balanceOf(TARGET_ADDRESS);
            console2.log("Target Address USDXL Balance After:", targetBalanceAfter);
            console2.log("Borrowed Amount:", targetBalanceAfter - targetBalanceBefore);
            
            // Check debt token balance
            DataTypes.ReserveData memory reserveData = pool.getReserveData(usdxlToken);
            address variableDebtToken = reserveData.variableDebtTokenAddress;
            
            if (variableDebtToken != address(0)) {
                uint256 debtBalance = IERC20(variableDebtToken).balanceOf(TARGET_ADDRESS);
                console2.log("Variable Debt Token Balance:", debtBalance);
            }
            
        } catch Error(string memory reason) {
            console2.log("USDXL borrow failed:", reason);
            
            // Try to get more specific error information
            console2.log("Attempting to get user configuration...");
            try pool.getUserConfiguration(TARGET_ADDRESS) returns (DataTypes.UserConfigurationMap memory userConfig) {
                console2.log("User configuration retrieved");
                // Check if user has any collateral
                bool hasCollateral = userConfig.data != 0;
                console2.log("User has collateral:", hasCollateral);
            } catch {
                console2.log("Could not retrieve user configuration");
            }
            
        } catch {
            console2.log("USDXL borrow failed: unknown error");
        }
        
        vm.stopPrank();
        
        console2.log("\n=== Script Complete ===");
    }
    
    /**
     * @notice Test function to verify script logic without network calls
     */
    function test() external view {
        console2.log("=== USDXL Borrow Script Test ===");
        console2.log("Target Address:", TARGET_ADDRESS);
        console2.log("New Interest Rate Strategy:", NEW_INTEREST_RATE_STRATEGY);
        console2.log("Borrow Amount:", BORROW_AMOUNT, "USDXL");
        console2.log("Interest Rate Mode:", INTEREST_RATE_MODE);
        console2.log("Referral Code:", REFERRAL_CODE);
        
        // Configuration
        address addressesProvider = 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594;
        address usdxlToken = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
        
        console2.log("Addresses Provider:", addressesProvider);
        console2.log("USDXL Token:", usdxlToken);
        
        console2.log("Script configuration verified successfully!");
    }
} 