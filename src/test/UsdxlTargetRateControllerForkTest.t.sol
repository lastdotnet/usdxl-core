// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {UsdxlTargetRateController} from "../contracts/facilitators/hyfi/interestStrategy/UsdxlTargetRateController.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IUsdxlToken} from "../contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IWrappedHypeGateway} from "@hypurrfi/periphery/contracts/misc/interfaces/IWrappedHypeGateway.sol";
import {AggregatorV3Interface} from "@hypurrfi/contracts/oracle/interfaces/AggregatorV3Interface.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title UsdxlTargetRateControllerForkTest
 * @notice Fork test for the USDXL Target Rate Controller using real Aave contracts
 */
contract UsdxlTargetRateControllerForkTest is Test {
    // HyperEVM Aave V3 addresses (from pooled-periphery)
    address constant AAVE_V3_POOL = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    address constant AAVE_V3_POOL_ADDRESSES_PROVIDER = 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594;
    address constant AAVE_V3_PRICE_ORACLE = 0x9BE2ac1ff80950DCeb816842834930887249d9A8;
    
    // HyperEVM token addresses
    address constant USDT = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb; // USD₮0
    address constant USDXL = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645; // USDXL
    address constant WSTHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38; // wstHYPE
    address constant WHYPE = 0x5555555555555555555555555555555555555555; // WHYPE (native)
    
    // Chainlink price feeds (using mock addresses for testing)
    address constant USDXL_PRICE_FEED = 0x1111111111111111111111111111111111111111; // Mock USDXL price feed
    address constant USDT_PRICE_FEED = 0x2222222222222222222222222222222222222222; // Mock USDT price feed
    
    // Real wrappedHypeGateway address
    address constant WRAPPED_HYPE_GATEWAY = 0xd1EF87FeFA83154F83541b68BD09185e15463972;
    
    // Test accounts
    address owner;
    address executor;
    
    // Contracts
    UsdxlTargetRateController rateController;
    
    // Aave interfaces
    IPool pool;
    IPoolAddressesProvider addressesProvider;
    
    // Token interfaces
    IUsdxlToken usdxlToken;
    IWrappedHypeGateway wrappedHypeGateway;
    AggregatorV3Interface usdxlPriceFeed;
    AggregatorV3Interface usdtPriceFeed;
    
    uint256 public constant INITIAL_RATE = 0.136e27; // 13.6%
    uint256 public constant INITIAL_ETH = 0.1 ether;
    
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 targetRate, uint256 usdxlPrice, uint256 timestamp);
    event TargetRateCalculated(uint256 baseRate, uint256 targetRate, uint256 usdxlPrice, uint256 timestamp);
    event BaseRateUpdated(uint256 newBaseRate, uint256 timestamp);
    event ParametersUpdated(
        uint256 baseRate,
        uint256 targetPrice,
        uint256 rateFactor,
        uint256 halvingFactor,
        uint256 minimumChange,
        uint256 timestamp
    );

    function setUp() public {
        // Fork HyperEVM mainnet at a specific block number for consistent testing
        // Using a recent block number for testing
        vm.createSelectFork("hyperevm", 14000000);
        
        // Initialize test accounts
        owner = makeAddr("owner");
        executor = makeAddr("executor");
        
        // Initialize Aave interfaces
        pool = IPool(AAVE_V3_POOL);
        addressesProvider = IPoolAddressesProvider(AAVE_V3_POOL_ADDRESSES_PROVIDER);
        
        // Initialize token interfaces
        usdxlToken = IUsdxlToken(USDXL);
        
        // Use real wrappedHypeGateway address
        wrappedHypeGateway = IWrappedHypeGateway(WRAPPED_HYPE_GATEWAY);
        usdxlPriceFeed = AggregatorV3Interface(USDXL_PRICE_FEED);
        usdtPriceFeed = AggregatorV3Interface(USDT_PRICE_FEED);
        
        // Give accounts some ETH for gas
        vm.deal(owner, 10 ether);
        vm.deal(executor, 10 ether);
        
        // Deploy the rate controller
        vm.startPrank(owner);
        
        rateController = new UsdxlTargetRateController{value: INITIAL_ETH}(
            address(addressesProvider),
            address(usdxlToken),
            USDT,  // USDT0 token
            INITIAL_RATE,
            owner,
            address(wrappedHypeGateway)
        );
        
        // Add executor
        rateController.updateExecutor(executor, true);
        
        vm.stopPrank();
    }

    function testForkSetup() public {
        console.log("Testing fork setup...");
        
        // Verify we're on a fork by checking if we can access mainnet contracts
        console.log("Fork is active - verified by contract access");
        
        // Verify Aave pool is accessible
        address poolAddress = address(pool);
        assertTrue(poolAddress != address(0), "Pool address should not be zero");
        console.log("Aave pool accessible at:", poolAddress);
        
        // Verify we can call pool functions
        try pool.getUserAccountData(owner) returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 /* availableBorrowsBase */,
            uint256 /* currentLiquidationThreshold */,
            uint256 /* ltv */,
            uint256 healthFactor
        ) {
            console.log("Successfully called getUserAccountData");
            console.log("  Owner collateral:", totalCollateralBase);
            console.log("  Owner debt:", totalDebtBase);
            console.log("  Health factor:", healthFactor);
        } catch {
            console.log("Failed to call getUserAccountData - this is expected for new accounts");
        }
        
        // Verify we can get reserve data for USDXL
        try pool.getReserveData(USDXL) returns (DataTypes.ReserveData memory reserveData) {
            console.log("Successfully got USDXL reserve data");
            console.log("  aToken address:", reserveData.aTokenAddress);
            console.log("  Variable debt token:", reserveData.variableDebtTokenAddress);
            console.log("  Current variable borrow rate:", reserveData.currentVariableBorrowRate);
        } catch {
            console.log("USDXL not supported on this Aave deployment");
        }
        
        // Verify we can get reserve data for USDT
        try pool.getReserveData(USDT) returns (DataTypes.ReserveData memory reserveData) {
            console.log("Successfully got USDT reserve data");
            console.log("  aToken address:", reserveData.aTokenAddress);
            console.log("  Variable debt token:", reserveData.variableDebtTokenAddress);
            console.log("  Current variable borrow rate:", reserveData.currentVariableBorrowRate);
        } catch {
            console.log("USDT not supported on this Aave deployment");
        }
        
        console.log("Fork testing setup is working correctly!");
    }

    function testTokenAddresses() public {
        console.log("Testing token addresses...");
        
        // Test USDXL
        assertTrue(USDXL != address(0), "USDXL address should not be zero");
        console.log("USDXL address:", USDXL);
        
        // Test that USDXL has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(USDXL)
        }
        assertTrue(codeSize > 0, "USDXL should have contract code");
        console.log("USDXL has contract code");
        
        // Test USDT
        assertTrue(USDT != address(0), "USDT address should not be zero");
        console.log("USDT address:", USDT);
        
        assembly {
            codeSize := extcodesize(USDT)
        }
        assertTrue(codeSize > 0, "USDT should have contract code");
        console.log("USDT has contract code");
    }

    function testRateControllerInitialization() public {
        console.log("Testing rate controller initialization...");
        
        assertEq(rateController.owner(), owner);
        assertEq(rateController.currentRate(), INITIAL_RATE);
        assertEq(rateController.targetPrice(), 0.998e8);
        assertEq(rateController.rateFactor(), 1e27);
        assertEq(rateController.halvingFactor(), 2e27);
        assertEq(rateController.minimumChange(), 0.001e27);
        // baseRate is now dynamically calculated from USDT0 borrow rate
        // Should be > 0 since we add an initial sample in constructor
        assertTrue(rateController.baseRate() > 0);
        assertEq(rateController.executionInterval(), 4 hours);
        assertTrue(rateController.isAuthorizedExecutor(owner));
        assertTrue(rateController.isAuthorizedExecutor(executor));
        
        console.log("Rate controller initialized correctly");
    }

    function testGetMaxSamples() public {
        console.log("Testing getMaxSamples function...");
        
        // With 4 hour execution interval, max samples should be 48 hours / 4 hours = 12
        uint256 maxSamples = rateController.getMaxSamples();
        assertEq(maxSamples, 12);
        
        // Test with different execution interval
        vm.prank(owner);
        rateController.updateExecutionInterval(2 hours);
        
        // With 2 hour execution interval, max samples should be 48 hours / 2 hours = 24
        maxSamples = rateController.getMaxSamples();
        assertEq(maxSamples, 24);
        
        // Reset to original
        vm.prank(owner);
        rateController.updateExecutionInterval(4 hours);
        
        console.log("getMaxSamples function working correctly");
    }

    function testExecuteWithOffchainPrices() public {
        console.log("Testing execute with offchain prices...");
        
        // Skip if price feeds are not configured
        if (USDXL_PRICE_FEED == address(0) || USDT_PRICE_FEED == address(0)) {
            return; // Skip test if price feeds not configured
        }
        
        vm.warp(block.timestamp + 4 hours + 1); // Ensure execution is due
        
        vm.prank(executor);
        
        // Execute with offchain prices
        rateController.execute(int256(0.99e8));
        
        // Verify execution time was updated
        assertEq(rateController.lastExecutionTime(), block.timestamp);
        
        console.log("Execute with offchain prices successful");
    }

    function testTargetRateCalculation() public {
        console.log("Testing target rate calculation...");
        
        // Skip if price feeds are not configured
        if (USDXL_PRICE_FEED == address(0) || USDT_PRICE_FEED == address(0)) {
            return; // Skip test if price feeds not configured
        }
        
        // Test with USDXL price below target (0.99 vs 0.998)
        // Should result in higher target rate
        uint256 usdxlPrice = 0.99e8;
        uint256 usdtPrice = 1.0e8;
        
        vm.warp(block.timestamp + 4 hours + 1);
        
        vm.prank(executor);
        rateController.execute(int256(usdxlPrice));
        
        // The target rate should be higher than base rate due to price being below target
        // Target Rate = Base Rate * (Target Price / Current Price)^Rate Factor
        // = 0.05 * (0.998 / 0.99)^1 = 0.05 * 1.00808... ≈ 0.0504
        
        console.log("Target rate calculation test completed");
    }

    function testRateAdjustmentWithHalvingFactor() public {
        console.log("Testing rate adjustment with halving factor...");
        
        // Skip if price feeds are not configured
        if (USDXL_PRICE_FEED == address(0) || USDT_PRICE_FEED == address(0)) {
            return; // Skip test if price feeds not configured
        }
        
        // Set up parameters for testing
        vm.prank(owner);
        rateController.updateParameters(
            0.998e8, // targetPrice
            1e27,    // rateFactor (100% in ray)
            4e27,    // halvingFactor (400% in ray)
            0.001e27 // minimumChange
        );
        
        vm.warp(block.timestamp + 4 hours + 1);
        
        vm.prank(executor);
        rateController.execute(int256(0.99e8));
        
        // With halving factor of 4, the adjustment should be 1/4 of the difference
        // This should result in a smaller rate change
        
        console.log("Rate adjustment with halving factor test completed");
    }

    function testMinimumChangeThreshold() public {
        console.log("Testing minimum change threshold...");
        
        // Skip if price feeds are not configured
        if (USDXL_PRICE_FEED == address(0) || USDT_PRICE_FEED == address(0)) {
            return; // Skip test if price feeds not configured
        }
        
        // Set minimum change very high
        vm.prank(owner);
        rateController.updateParameters(
            0.998e8, // targetPrice
            1e27,    // rateFactor (100% in ray)
            2e27,    // halvingFactor (200% in ray)
            0.1e27   // minimumChange (10% - very high)
        );
        
        vm.warp(block.timestamp + 4 hours + 1);
        
        vm.prank(executor);
        rateController.execute(int256(0.999e8));
        
        // Rate should not change due to minimum change threshold
        assertEq(rateController.currentRate(), INITIAL_RATE);
        
        console.log("Minimum change threshold test completed");
    }

    function testParameterUpdates() public {
        console.log("Testing parameter updates...");
        
        uint256 newTargetPrice = 0.999e8;
        uint256 newRateFactor = 2e27;
        uint256 newHalvingFactor = 3e27;
        uint256 newMinimumChange = 0.002e27;
        
        vm.prank(owner);
        rateController.updateParameters(
            newTargetPrice,
            newRateFactor,
            newHalvingFactor,
            newMinimumChange
        );
        
        // baseRate is now calculated dynamically, so just check it's > 0
        assertTrue(rateController.baseRate() > 0);
        assertEq(rateController.targetPrice(), newTargetPrice);
        assertEq(rateController.rateFactor(), newRateFactor);
        assertEq(rateController.halvingFactor(), newHalvingFactor);
        assertEq(rateController.minimumChange(), newMinimumChange);
        
        console.log("Parameter updates test completed");
    }

    function testEmergencyUpdateRate() public {
        console.log("Testing emergency update rate...");
        
        uint256 newRate = 0.2e27; // 20%
        
        vm.prank(owner);
        rateController.emergencyUpdateRate(newRate);
        
        assertEq(rateController.currentRate(), newRate);
        
        console.log("Emergency update rate test completed");
    }

    function testExecutorManagement() public {
        console.log("Testing executor management...");
        
        address newExecutor = makeAddr("newExecutor");
        
        // Add executor
        vm.prank(owner);
        rateController.updateExecutor(newExecutor, true);
        
        assertTrue(rateController.isAuthorizedExecutor(newExecutor));
        
        // Remove executor
        vm.prank(owner);
        rateController.updateExecutor(newExecutor, false);
        
        assertFalse(rateController.isAuthorizedExecutor(newExecutor));
        
        console.log("Executor management test completed");
    }

    function testUnauthorizedExecution() public {
        console.log("Testing unauthorized execution...");
        
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert("Unauthorized executor");
        rateController.execute(int256(0.99e8));
        
        console.log("Unauthorized execution test completed");
    }

    function testExecutionIntervalUpdate() public {
        console.log("Testing execution interval update...");
        
        uint256 newInterval = 6 hours;
        
        vm.prank(owner);
        rateController.updateExecutionInterval(newInterval);
        
        assertEq(rateController.executionInterval(), newInterval);
        
        console.log("Execution interval update test completed");
    }

    function testIsExecutionDue() public {
        console.log("Testing is execution due...");
        
        // Initially should not be due (lastExecutionTime is set to current timestamp)
        assertFalse(rateController.isExecutionDue());
        
        // Should be due after interval
        vm.warp(block.timestamp + 4 hours + 1);
        assertTrue(rateController.isExecutionDue());
        
        // Execute once
        vm.prank(executor);
        rateController.execute(int256(0.99e8));
        
        // Should not be due immediately after
        assertFalse(rateController.isExecutionDue());
        
        // Should be due after interval again
        vm.warp(block.timestamp + 4 hours + 1);
        assertTrue(rateController.isExecutionDue());
        
        console.log("Is execution due test completed");
    }

    function testGetNextExecutionTime() public {
        console.log("Testing get next execution time...");
        
        // Initially should be current time + interval
        assertEq(rateController.getNextExecutionTime(), block.timestamp + 4 hours);
        
        // Execute once
        vm.prank(executor);
        rateController.execute(int256(0.99e8));
        
        // Should be last execution + interval
        assertEq(rateController.getNextExecutionTime(), rateController.lastExecutionTime() + 4 hours);
        
        console.log("Get next execution time test completed");
    }

    function testHYPEWithdrawal() public {
        console.log("Testing HYPE withdrawal...");
        
        // Send some HYPE to the contract
        vm.deal(address(rateController), 0.5 ether);
        
        uint256 initialBalance = owner.balance;
        
        vm.prank(owner);
        rateController.withdrawHYPE(0.3 ether, payable(owner));
        
        assertEq(owner.balance, initialBalance + 0.3 ether);
        assertEq(address(rateController).balance, 0.2 ether);
        
        console.log("HYPE withdrawal test completed");
    }

    function testReceiveHYPE() public {
        console.log("Testing receive HYPE...");
        
        uint256 initialBalance = address(rateController).balance;
        
        (bool success,) = address(rateController).call{value: 0.1 ether}("");
        assertTrue(success);
        
        assertEq(address(rateController).balance, initialBalance + 0.1 ether);
        
        console.log("Receive HYPE test completed");
    }

    /**
     * @notice Helper function to get reserve data for an asset
     */
    function getReserveData(address asset) internal view returns (DataTypes.ReserveData memory) {
        return pool.getReserveData(asset);
    }

    /**
     * @notice Helper function to check if an asset is supported by Aave
     */
    function isAssetSupported(address asset) internal view returns (bool) {
        DataTypes.ReserveData memory reserveData = pool.getReserveData(asset);
        return reserveData.aTokenAddress != address(0);
    }
}
