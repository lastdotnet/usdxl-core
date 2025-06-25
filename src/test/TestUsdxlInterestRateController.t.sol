// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {UsdxlInterestRateController} from "src/contracts/facilitators/hyfi/interestStrategy/UsdxlInterestRateController.sol";
import {UsdxlMutableInterestRateStrategy} from "src/contracts/facilitators/hyfi/interestStrategy/UsdxlMutableInterestRateStrategy.sol";
import {IUsdxlToken} from "src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {console2 as console} from 'forge-std/console2.sol';

contract MockUsdxlOracle {
    int256 public price;
    
    constructor(int256 _price) {
        price = _price;
    }
    
    function latestAnswer() external view returns (int256) {
        return price;
    }
    
    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract MockPool {
    mapping(address => address) public variableDebtTokens;
    mapping(address => address) public interestRateStrategies;
    mapping(address => mapping(address => uint256)) public userDebt;
    
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        DataTypes.ReserveData memory reserveData;
        reserveData.variableDebtTokenAddress = variableDebtTokens[asset];
        reserveData.interestRateStrategyAddress = interestRateStrategies[asset];
        return reserveData;
    }
    
    function setReserveData(address asset, address debtToken, address interestRateStrategy) external {
        variableDebtTokens[asset] = debtToken;
        interestRateStrategies[asset] = interestRateStrategy;
    }
    
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external returns (uint256) {
        userDebt[asset][onBehalfOf] += amount;
        // Also update the mock debt token balance
        MockVariableDebtToken(variableDebtTokens[asset]).mint(onBehalfOf, amount);
        return amount;
    }
    
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256) {
        require(userDebt[asset][onBehalfOf] >= amount, "Insufficient debt");
        userDebt[asset][onBehalfOf] -= amount;
        // Also update the mock debt token balance
        MockVariableDebtToken(variableDebtTokens[asset]).burn(onBehalfOf, amount);
        return amount;
    }
}

contract MockPoolConfigurator {
    function setReserveInterestRateStrategyAddress(
        address asset,
        address rateStrategyAddress
    ) external {
        // Mock implementation
    }
}

contract MockPoolAddressesProvider {
    address public pool;
    address public configurator;
    
    constructor(address _pool, address _configurator) {
        pool = _pool;
        configurator = _configurator;
    }
    
    function getPool() external view returns (address) {
        return pool;
    }
    
    function getPoolConfigurator() external view returns (address) {
        return configurator;
    }
}

contract MockUsdxlToken {
    mapping(address => uint256) public balanceOf;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function burn(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }
}

contract MockVariableDebtToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
    }
    
    // IERC20 interface
    function totalSupply() external view returns (uint256) {
        return 0; // Not needed for tests
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract TestUsdxlInterestRateController is Test {
    UsdxlInterestRateController public rateController;
    MockUsdxlOracle public oracle;
    MockPool public pool;
    MockPoolConfigurator public configurator;
    MockPoolAddressesProvider public addressesProvider;
    MockUsdxlToken public usdxlToken;
    MockVariableDebtToken public variableDebtToken;
    
    address public usdxlReserve = address(0x123);
    uint256 public initialRate = 0.08e27; // 8% (above minimum)
    
    address public owner = address(0x1);
    address public user = address(0x2);
    
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 usdxlPrice, uint256 timestamp);
    event PerpetualLoanCreated(uint256 amount, uint256 timestamp);
    event PerpetualLoanRefreshed(uint256 amount, uint256 timestamp);
    event ExecutionSkipped(uint256 reason, uint256 timestamp);
    event InterestRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);
    event ParametersUpdated(
        uint256 oldMinRate, 
        uint256 newMinRate,
        uint256 oldRateAdjustment, 
        uint256 newRateAdjustment,
        uint256 oldPriceThreshold, 
        uint256 newPriceThreshold,
        uint256 oldTargetPrice, 
        uint256 newTargetPrice,
        uint256 timestamp
    );
    
    function setUp() public {
        // Deploy mocks
        oracle = new MockUsdxlOracle(1e8); // $1 price
        pool = new MockPool();
        configurator = new MockPoolConfigurator();
        addressesProvider = new MockPoolAddressesProvider(address(pool), address(configurator));
        usdxlToken = new MockUsdxlToken();
        variableDebtToken = new MockVariableDebtToken();
        
        // Setup reserve data
        pool.setReserveData(usdxlReserve, address(variableDebtToken), address(0x456));
        
        // Deploy rate controller
        vm.prank(owner);
        rateController = new UsdxlInterestRateController(
            address(addressesProvider),
            address(usdxlToken),
            address(oracle),
            usdxlReserve,
            initialRate
        );
        
        // Give some USDXL to the controller for perpetual loan
        usdxlToken.mint(address(rateController), 10000e18);
    }
    
    function testConstructor() public {
        assertEq(rateController.owner(), address(rateController)); // Controller is its own owner
        assertEq(address(rateController.ADDRESSES_PROVIDER()), address(addressesProvider));
        assertEq(address(rateController.USDXL_TOKEN()), address(usdxlToken));
        assertEq(address(rateController.USDXL_ORACLE()), address(oracle));
        assertEq(address(rateController.USDXL_RESERVE()), usdxlReserve);
        assertEq(rateController.currentRate(), initialRate);
        assertEq(rateController.lastExecutionTime(), block.timestamp);
        assertEq(rateController.getBaseVariableBorrowRate(), initialRate);
        
        // Check initial parameters
        assertEq(rateController.minRate(), 0.06e27); // 6%
        assertEq(rateController.rateAdjustment(), 0.0015e27); // 0.15%
        assertEq(rateController.priceThreshold(), 0.995e8); // 0.995
        assertEq(rateController.targetPrice(), 1e8); // 1.00
    }
    
    function testUpdateParameters() public {
        uint256 newMinRate = 0.08e27; // 8%
        uint256 newRateAdjustment = 0.002e27; // 0.2%
        uint256 newPriceThreshold = 0.99e8; // 0.99
        uint256 newTargetPrice = 1.01e8; // 1.01
        
        vm.prank(address(rateController));
        rateController.updateParameters(
            newMinRate,
            newRateAdjustment,
            newPriceThreshold,
            newTargetPrice
        );
        
        assertEq(rateController.minRate(), newMinRate);
        assertEq(rateController.rateAdjustment(), newRateAdjustment);
        assertEq(rateController.priceThreshold(), newPriceThreshold);
        assertEq(rateController.targetPrice(), newTargetPrice);
    }
    
    function testUpdateParametersRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.updateParameters(0.08e27, 0.002e27, 0.99e8, 1.01e8);
    }
    
    function testUpdateParametersRevertsIfInvalidMinRate() public {
        vm.prank(address(rateController));
        vm.expectRevert("Min rate must be positive");
        rateController.updateParameters(0, 0.002e27, 0.99e8, 1.01e8);
    }
    
    function testUpdateParametersRevertsIfInvalidRateAdjustment() public {
        vm.prank(address(rateController));
        vm.expectRevert("Rate adjustment must be positive");
        rateController.updateParameters(0.08e27, 0, 0.99e8, 1.01e8);
    }
    
    function testUpdateParametersRevertsIfInvalidPriceThreshold() public {
        vm.prank(address(rateController));
        vm.expectRevert("Price threshold must be positive");
        rateController.updateParameters(0.08e27, 0.002e27, 0, 1.01e8);
    }
    
    function testUpdateParametersRevertsIfInvalidTargetPrice() public {
        vm.prank(address(rateController));
        vm.expectRevert("Target price must be positive");
        rateController.updateParameters(0.08e27, 0.002e27, 0.99e8, 0);
    }
    
    function testUpdateParametersRevertsIfThresholdExceedsTarget() public {
        vm.prank(address(rateController));
        vm.expectRevert("Threshold cannot exceed target");
        rateController.updateParameters(0.08e27, 0.002e27, 1.02e8, 1.01e8);
    }
    
    function testUpdateParametersRevertsIfCurrentRateBelowNewMin() public {
        // Set current rate to 6%
        vm.prank(address(rateController));
        rateController.emergencyUpdateRate(0.06e27);
        
        // Try to set minimum to 8%
        vm.prank(address(rateController));
        vm.expectRevert("Current rate below new minimum");
        rateController.updateParameters(0.08e27, 0.002e27, 0.99e8, 1.01e8);
    }
    
    function testUpdateMinRate() public {
        uint256 newMinRate = 0.08e27; // 8%
        
        vm.prank(address(rateController));
        rateController.updateMinRate(newMinRate);
        
        assertEq(rateController.minRate(), newMinRate);
        // Other parameters should remain unchanged
        assertEq(rateController.rateAdjustment(), 0.0015e27);
        assertEq(rateController.priceThreshold(), 0.995e8);
        assertEq(rateController.targetPrice(), 1e8);
    }
    
    function testUpdateRateAdjustment() public {
        uint256 newRateAdjustment = 0.002e27; // 0.2%
        
        vm.prank(address(rateController));
        rateController.updateRateAdjustment(newRateAdjustment);
        
        assertEq(rateController.rateAdjustment(), newRateAdjustment);
        // Other parameters should remain unchanged
        assertEq(rateController.minRate(), 0.06e27);
        assertEq(rateController.priceThreshold(), 0.995e8);
        assertEq(rateController.targetPrice(), 1e8);
    }
    
    function testUpdatePriceThreshold() public {
        uint256 newPriceThreshold = 0.99e8; // 0.99
        
        vm.prank(address(rateController));
        rateController.updatePriceThreshold(newPriceThreshold);
        
        assertEq(rateController.priceThreshold(), newPriceThreshold);
        // Other parameters should remain unchanged
        assertEq(rateController.minRate(), 0.06e27);
        assertEq(rateController.rateAdjustment(), 0.0015e27);
        assertEq(rateController.targetPrice(), 1e8);
    }
    
    function testUpdateTargetPrice() public {
        uint256 newTargetPrice = 1.01e8; // 1.01
        
        vm.prank(address(rateController));
        rateController.updateTargetPrice(newTargetPrice);
        
        assertEq(rateController.targetPrice(), newTargetPrice);
        // Other parameters should remain unchanged
        assertEq(rateController.minRate(), 0.06e27);
        assertEq(rateController.rateAdjustment(), 0.0015e27);
        assertEq(rateController.priceThreshold(), 0.995e8);
    }
    
    function testGetParameters() public {
        (
            uint256 minRate_,
            uint256 rateAdjustment_,
            uint256 priceThreshold_,
            uint256 targetPrice_
        ) = rateController.getParameters();
        
        assertEq(minRate_, 0.06e27);
        assertEq(rateAdjustment_, 0.0015e27);
        assertEq(priceThreshold_, 0.995e8);
        assertEq(targetPrice_, 1e8);
    }
    
    function testExecuteTooEarly() public {
        // Expect the ExecutionSkipped event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ExecutionSkipped(1, block.timestamp);
        
        // Try to execute immediately after deployment
        rateController.execute();
    }
    
    function testExecuteWithValidPrice() public {
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Execute rate control
        rateController.execute();
        
        // Should create perpetual loan
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
    }
    
    function testRateIncreaseBelowThreshold() public {
        // Set price below threshold (0.995)
        oracle.setPrice(0.99e8); // $0.99
        
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        uint256 oldRate = rateController.currentRate();
        
        // Execute rate control
        rateController.execute();
        
        uint256 newRate = rateController.currentRate();
        assertGt(newRate, oldRate);
        assertEq(newRate, oldRate + rateController.rateAdjustment());
        
        // Check that the inherited strategy rate was also updated
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    
    function testRateDecreaseAboveThreshold() public {
        // Set price at threshold (0.995)
        oracle.setPrice(0.995e8);
        
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        uint256 oldRate = rateController.currentRate();
        
        // Execute rate control
        rateController.execute();
        
        uint256 newRate = rateController.currentRate();
        assertLt(newRate, oldRate);
        assertEq(newRate, oldRate - rateController.rateAdjustment());
        
        // Check that the inherited strategy rate was also updated
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    
    function testRateDecreaseAbovePeg() public {
        // Set price above peg ($1.00)
        oracle.setPrice(1e8);
        
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        uint256 oldRate = rateController.currentRate();
        
        // Execute rate control
        rateController.execute();
        
        uint256 newRate = rateController.currentRate();
        assertLt(newRate, oldRate);
        assertEq(newRate, oldRate - rateController.rateAdjustment());
        
        // Check that the inherited strategy rate was also updated
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    
    function testRateDoesNotGoBelowMinimum() public {
        // Set price above threshold (0.995)
        oracle.setPrice(1e8);
        
        // Fast forward multiple times to decrease rate
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 8 hours);
            rateController.execute();
        }
        
        // Rate should not go below minimum
        assertGe(rateController.currentRate(), rateController.minRate());
        assertGe(rateController.getBaseVariableBorrowRate(), rateController.minRate());
    }
    
    function testNoChangeWhenAtMinimumAndPriceAboveThreshold() public {
        // First, decrease rate to minimum by running multiple iterations
        oracle.setPrice(1e8); // Price above threshold to decrease rate
        
        // Calculate how many iterations needed to reach minimum
        uint256 currentRate = rateController.currentRate(); // 8%
        uint256 minRate = rateController.minRate(); // 6%
        uint256 rateAdjustment = rateController.rateAdjustment(); // 0.15%
        
        // Calculate iterations needed: (currentRate - minRate) / rateAdjustment
        uint256 iterationsNeeded = (currentRate - minRate) / rateAdjustment;
        
        // Execute enough times to reach minimum
        for (uint i = 0; i < iterationsNeeded + 1; i++) {
            vm.warp(block.timestamp + 8 hours);
            rateController.execute();
        }
        
        // Ensure we're at minimum rate
        assertEq(rateController.currentRate(), rateController.minRate());
        
        // Set price above threshold and execute again
        oracle.setPrice(1e8);
        vm.warp(block.timestamp + 8 hours);
        
        uint256 rateBefore = rateController.currentRate();
        rateController.execute();
        uint256 rateAfter = rateController.currentRate();
        
        // Rate should not change when at minimum and price above threshold
        assertEq(rateAfter, rateBefore);
        assertEq(rateAfter, rateController.minRate());
    }
    
    function testRateAdjustmentWithUpdatedParameters() public {
        // Update parameters
        vm.prank(address(rateController));
        rateController.updateParameters(0.05e27, 0.002e27, 0.99e8, 1.01e8);
        
        // Set price below new threshold
        oracle.setPrice(0.98e8); // $0.98
        
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        uint256 oldRate = rateController.currentRate();
        rateController.execute();
        uint256 newRate = rateController.currentRate();
        
        // Should use new rate adjustment
        assertEq(newRate, oldRate + 0.002e27);
    }
    
    function testEmergencyUpdateRate() public {
        uint256 newRate = 0.12e27; // 12%
        
        vm.prank(address(rateController)); // Controller is its own owner
        rateController.emergencyUpdateRate(newRate);
        
        assertEq(rateController.currentRate(), newRate);
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    
    function testEmergencyUpdateRateRevertsIfNotOwner() public {
        uint256 newRate = 0.12e27; // 12%
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.emergencyUpdateRate(newRate);
    }
    
    function testEmergencyUpdateRateRevertsIfBelowMinimum() public {
        uint256 newRate = 0.05e27; // 5% (below 6% minimum)
        
        vm.prank(address(rateController));
        vm.expectRevert("Rate below minimum");
        rateController.emergencyUpdateRate(newRate);
    }
    
    function testWithdrawUsdxl() public {
        uint256 amount = 1000e18;
        address recipient = address(0x999);
        
        vm.prank(address(rateController));
        rateController.withdrawUsdxl(amount, recipient);
        
        assertEq(usdxlToken.balanceOf(recipient), amount);
    }
    
    function testWithdrawUsdxlRevertsIfNotOwner() public {
        uint256 amount = 1000e18;
        address recipient = address(0x999);
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.withdrawUsdxl(amount, recipient);
    }
    
    function testGetUsdxlPrice() public {
        uint256 price = rateController.getUsdxlPrice();
        assertEq(price, 1e8); // $1.00
    }
    
    function testGetNextExecutionTime() public {
        uint256 nextTime = rateController.getNextExecutionTime();
        assertEq(nextTime, block.timestamp + 8 hours);
    }
    
    function testIsExecutionDue() public {
        // Should be false initially
        assertFalse(rateController.isExecutionDue());
        
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Should be true
        assertTrue(rateController.isExecutionDue());
    }
    
    function testPerpetualLoanRefresh() public {
        // Create initial perpetual loan
        vm.warp(block.timestamp + 8 hours);
        rateController.execute();
        
        // Fast forward another 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Should refresh the loan
        rateController.execute();
        
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
    }
    
    function testEmergencyRepayAll() public {
        // First, create a perpetual loan by executing the rate controller
        vm.warp(block.timestamp + 8 hours);
        rateController.execute();
        
        // Check that perpetual loan was created
        (bool activeBefore, uint256 debtBefore) = rateController.getPerpetualLoanStatus();
        assertTrue(activeBefore);
        assertGt(debtBefore, 0);
        
        // Emergency repay all
        vm.prank(address(rateController));
        rateController.emergencyRepayAll();
        
        // Check that perpetual loan is cleared
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertFalse(active);
        assertEq(debt, 0);
        
        // Verify debt token balance is also cleared
        assertEq(variableDebtToken.balanceOf(address(rateController)), 0);
    }
    
    function testConstants() public {
        assertEq(rateController.EXECUTION_INTERVAL(), 8 hours);
        assertEq(rateController.PERPETUAL_LOAN_AMOUNT(), 1000e18);
    }
    
    function testInheritance() public {
        // Test that the controller properly inherits from the mutable strategy
        assertEq(rateController.getBaseVariableBorrowRate(), initialRate);
        
        // Test that we can call the inherited update function
        uint256 newRate = 0.10e27; // 10%
        vm.prank(address(rateController));
        rateController.updateBaseVariableBorrowRate(newRate);
        
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
} 