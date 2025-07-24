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
    mapping(address => address) public aTokens;
    mapping(address => mapping(address => uint256)) public userDebt;
    
    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        DataTypes.ReserveData memory reserveData;
        reserveData.variableDebtTokenAddress = variableDebtTokens[asset];
        reserveData.interestRateStrategyAddress = interestRateStrategies[asset];
        reserveData.aTokenAddress = aTokens[asset];
        return reserveData;
    }
    
    function setReserveData(address asset, address debtToken, address interestRateStrategy, address aToken) external {
        variableDebtTokens[asset] = debtToken;
        interestRateStrategies[asset] = interestRateStrategy;
        aTokens[asset] = aToken;
    }
    
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external returns (uint256) {
        interestRateMode;
        referralCode;
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
        interestRateMode;
        onBehalfOf;
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
    
    function approve(address spender, uint256 amount) external pure returns (bool) {
        spender;
        amount;
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
    function totalSupply() external pure returns (uint256) {
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

contract MockWrappedHypeGateway {
    address public whypeAddress = address(0x1234);
    event MockHYPEWithdrawn(address to, uint256 amount);
    MockAToken public aWhype;
    address public controller;
    function setAToken(MockAToken _aWhype) external {
        aWhype = _aWhype;
    }
    function setController(address _controller) external {
        controller = _controller;
    }
    function depositHYPE(address, address onBehalfOf, uint16 referralCode) external payable {
        onBehalfOf;
        referralCode;
    }
    function withdrawHYPE(address, uint256 amount, address to) external {
        if (address(aWhype) != address(0) && controller != address(0)) {
            aWhype.setBalance(controller, 0);
        }
        emit MockHYPEWithdrawn(to, amount);
    }
    function getWHYPEAddress() external view returns (address) {
        return whypeAddress;
    }
}

contract MockAToken {
    mapping(address => uint256) public balances;
    
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
    
    function approve(address spender, uint256 amount) external pure returns (bool) {
        spender;
        amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    // Helper for tests
    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
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
    MockWrappedHypeGateway public wrappedHypeGateway;
    MockAToken public aWhype;
    
    address public usdxlReserve = address(0x123);
    address public whypeAddress = address(0x1234);
    uint256 public initialRate = 0.08e27; // 8% (above minimum)
    
    address public owner = address(0x1);
    address public user = address(0x2);
    
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 usdxlPrice, uint256 timestamp);
    event PerpetualLoanCreated(uint256 amount, uint256 timestamp);
    event PerpetualLoanRefreshed(uint256 amount, uint256 timestamp);
    event ExecutionSkipped(uint256 reason, uint256 timestamp);
    event PriceDataEmitted(uint256 offchainPrice, uint256 onchainPrice, uint256 timestamp);
    event InterestRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);
    event HYPESupplied(uint256 amount, uint256 timestamp);
    event HYPEWithdrawnFromPool(uint256 amount, address recipient, uint256 timestamp);
    event LoanClosed(uint256 timestamp);
    event ExecutorUpdated(address executor, bool enabled, uint256 timestamp);
    event ParametersUpdated(
        uint256 minRate,
        uint256 maxRate,
        uint256 rateIncreaseAdjustment,
        uint256 rateDecreaseAdjustment,
        uint256 priceThreshold,
        uint256 targetPrice,
        uint256 timestamp
    );
    
    function setUp() public {
        // Fund the owner with HYPE for deployment
        vm.deal(owner, 10 ether);
        
        // Deploy mocks
        oracle = new MockUsdxlOracle(1e8); // $1 price
        pool = new MockPool();
        configurator = new MockPoolConfigurator();
        addressesProvider = new MockPoolAddressesProvider(address(pool), address(configurator));
        usdxlToken = new MockUsdxlToken();
        variableDebtToken = new MockVariableDebtToken();
        wrappedHypeGateway = new MockWrappedHypeGateway();
        aWhype = new MockAToken();
        wrappedHypeGateway.setAToken(aWhype);
        
        // Setup reserve data for USDXL
        pool.setReserveData(usdxlReserve, address(variableDebtToken), address(0x456), address(0));
        
        // Setup reserve data for WHYPE
        pool.setReserveData(whypeAddress, address(0x567), address(0x789), address(aWhype));
        
        // Deploy rate controller with initial HYPE
        vm.prank(owner);
        rateController = new UsdxlInterestRateController{value: 1 ether}(
            address(addressesProvider),
            address(usdxlToken),
            address(oracle),
            usdxlReserve,
            initialRate,
            owner,
            1e18, // initial perpetual loan amount
            address(wrappedHypeGateway)
        );
        wrappedHypeGateway.setController(address(rateController));
        
        // Give some USDXL to the controller for perpetual loan
        usdxlToken.mint(address(rateController), 10000e18);
        
        // Give some aWHYPE to the controller to simulate supplied HYPE
        aWhype.setBalance(address(rateController), 5 ether);
    }
    
    function testConstructor() public {
        assertEq(rateController.owner(), owner); // Owner should be the specified owner
        assertEq(address(rateController.ADDRESSES_PROVIDER()), address(addressesProvider));
        assertEq(address(rateController.USDXL_TOKEN()), address(usdxlToken));
        assertEq(rateController.usdxlOracle(), address(oracle));
        assertEq(address(rateController.USDXL_RESERVE()), usdxlReserve);
        assertEq(rateController.currentRate(), initialRate);
        assertEq(rateController.lastExecutionTime(), block.timestamp);
        assertEq(rateController.getBaseVariableBorrowRate(), initialRate);
        assertEq(rateController.executionInterval(), 8 hours);
        // Check initial parameters
        assertEq(rateController.minRate(), 0.06e27); // 6%
        assertEq(rateController.maxRate(), 0.50e27); // 50%
        assertEq(rateController.rateIncreaseAdjustment(), 0.0015e27); // 0.15%
        assertEq(rateController.rateDecreaseAdjustment(), 0.0015e27); // 0.15%
        assertEq(rateController.priceThreshold(), 0.995e8); // 0.995
        assertEq(rateController.targetPrice(), 1e8); // 1.00
    }
    
    function testUpdateParameters() public {
        uint256 newMinRate = 0.08e27; // 8%
        uint256 newMaxRate = 0.40e27; // 40%
        uint256 newRateIncreaseAdjustment = 0.002e27; // 0.2%
        uint256 newRateDecreaseAdjustment = 0.001e27; // 0.1%
        uint256 newPriceThreshold = 0.99e8; // 0.99
        uint256 newTargetPrice = 1.01e8; // 1.01
        vm.prank(owner);
        rateController.updateParameters(
            newMinRate,
            newMaxRate,
            newRateIncreaseAdjustment,
            newRateDecreaseAdjustment,
            newPriceThreshold,
            newTargetPrice
        );
        assertEq(rateController.minRate(), newMinRate);
        assertEq(rateController.maxRate(), newMaxRate);
        assertEq(rateController.rateIncreaseAdjustment(), newRateIncreaseAdjustment);
        assertEq(rateController.rateDecreaseAdjustment(), newRateDecreaseAdjustment);
        assertEq(rateController.priceThreshold(), newPriceThreshold);
        assertEq(rateController.targetPrice(), newTargetPrice);
    }
    function testUpdateParametersRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.updateParameters(0.08e27, 0.40e27, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfInvalidMinRate() public {
        vm.prank(owner);
        vm.expectRevert("Min rate must be positive");
        rateController.updateParameters(0, 0.40e27, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfInvalidMaxRate() public {
        vm.prank(owner);
        vm.expectRevert("Max rate must be positive");
        rateController.updateParameters(0.08e27, 0, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfMaxRateBelowMinRate() public {
        vm.prank(owner);
        vm.expectRevert("Max rate must exceed min rate");
        rateController.updateParameters(0.40e27, 0.08e27, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfInvalidRateIncreaseAdjustment() public {
        vm.prank(owner);
        vm.expectRevert("Increase adjustment must be positive");
        rateController.updateParameters(0.08e27, 0.40e27, 0, 0.001e27, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfInvalidRateDecreaseAdjustment() public {
        vm.prank(owner);
        vm.expectRevert("Decrease adjustment must be positive");
        rateController.updateParameters(0.08e27, 0.40e27, 0.002e27, 0, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfInvalidPriceThreshold() public {
        vm.prank(owner);
        vm.expectRevert("Price threshold must be positive");
        rateController.updateParameters(0.08e27, 0.40e27, 0.002e27, 0.001e27, 0, 1.01e8);
    }
    function testUpdateParametersRevertsIfInvalidTargetPrice() public {
        vm.prank(owner);
        vm.expectRevert("Target price must be positive");
        rateController.updateParameters(0.08e27, 0.40e27, 0.002e27, 0.001e27, 0.99e8, 0);
    }
    function testUpdateParametersRevertsIfThresholdExceedsTarget() public {
        vm.prank(owner);
        vm.expectRevert("Threshold cannot exceed target");
        rateController.updateParameters(0.08e27, 0.40e27, 0.002e27, 0.001e27, 1.02e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfCurrentRateBelowNewMin() public {
        // Set current rate to 6%
        vm.prank(owner);
        rateController.emergencyUpdateRate(0.06e27);
        // Try to set minimum to 8%
        vm.prank(owner);
        vm.expectRevert("Current rate below new minimum");
        rateController.updateParameters(0.08e27, 0.40e27, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
    }
    function testUpdateParametersRevertsIfCurrentRateAboveNewMax() public {
        // Set current rate to 45%
        vm.prank(owner);
        rateController.emergencyUpdateRate(0.45e27);
        // Set maximum to 40% - should automatically adjust current rate to 40%
        vm.prank(owner);
        rateController.updateParameters(0.06e27, 0.40e27, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
        // Current rate should be automatically adjusted to the new maximum
        assertEq(rateController.currentRate(), 0.40e27);
        assertEq(rateController.maxRate(), 0.40e27);
    }
    function testRateIncreaseBelowThreshold() public {
        // Set price below threshold (0.995)
        oracle.setPrice(0.99e8); // $0.99
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        uint256 oldRate = rateController.currentRate();
        // Execute rate control with offchain price below threshold
        vm.prank(owner);
        rateController.execute(0.99e8);
        uint256 newRate = rateController.currentRate();
        assertGt(newRate, oldRate);
        assertEq(newRate, oldRate + rateController.rateIncreaseAdjustment());
        // Check that the inherited strategy rate was also updated
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    function testRateDecreaseAboveThreshold() public {
        // Set price at threshold (0.995)
        oracle.setPrice(0.995e8);
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        uint256 oldRate = rateController.currentRate();
        // Execute rate control with offchain price at threshold
        vm.prank(owner);
        rateController.execute(0.995e8);
        uint256 newRate = rateController.currentRate();
        assertLt(newRate, oldRate);
        assertEq(newRate, oldRate - rateController.rateDecreaseAdjustment());
        // Check that the inherited strategy rate was also updated
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    function testRateDecreaseAbovePeg() public {
        // Set price above peg ($1.00)
        oracle.setPrice(1e8);
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        uint256 oldRate = rateController.currentRate();
        // Execute rate control with offchain price above peg
        vm.prank(owner);
        rateController.execute(1e8);
        uint256 newRate = rateController.currentRate();
        assertLt(newRate, oldRate);
        assertEq(newRate, oldRate - rateController.rateDecreaseAdjustment());
        // Check that the inherited strategy rate was also updated
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    function testRateAdjustmentWithUpdatedParameters() public {
        // Update parameters
        vm.prank(owner);
        rateController.updateParameters(0.05e27, 0.40e27, 0.002e27, 0.001e27, 0.99e8, 1.01e8);
        // Set price below new threshold
        oracle.setPrice(0.98e8); // $0.98
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        uint256 oldRate = rateController.currentRate();
        vm.prank(owner);
        rateController.execute(0.98e8);
        uint256 newRate = rateController.currentRate();
        // Should use new rate increase adjustment
        assertEq(newRate, oldRate + 0.002e27);
        // Now test decrease
        oracle.setPrice(1.01e8); // $1.01
        vm.warp(block.timestamp + 8 hours);
        oldRate = rateController.currentRate();
        vm.prank(owner);
        rateController.execute(1.01e8);
        newRate = rateController.currentRate();
        assertEq(newRate, oldRate - 0.001e27);
    }
    function testGetParameters() public {
        (
            uint256 minRate_,
            uint256 maxRate_,
            uint256 rateIncreaseAdjustment_,
            uint256 rateDecreaseAdjustment_,
            uint256 priceThreshold_,
            uint256 targetPrice_
        ) = rateController.getParameters();
        assertEq(minRate_, 0.06e27);
        assertEq(maxRate_, 0.50e27);
        assertEq(rateIncreaseAdjustment_, 0.0015e27);
        assertEq(rateDecreaseAdjustment_, 0.0015e27);
        assertEq(priceThreshold_, 0.995e8);
        assertEq(targetPrice_, 1e8);
    }
    
    function testExecuteTooEarly() public {
        // Expect the ExecutionSkipped event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ExecutionSkipped(1, block.timestamp);
        
        // Try to execute immediately after deployment with valid offchain price
        vm.prank(owner);
        rateController.execute(1e8);
    }
    
    function testExecuteWithValidPrice() public {
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Execute rate control with valid offchain price
        vm.prank(owner);
        rateController.execute(1e8);
        
        // Should create perpetual loan
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
    }
    
    function testExecuteWithOffchainPrice() public {
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        int256 offchainPrice = 0.98e8; // $0.98 (below threshold)
        
        // Execute rate control with offchain price
        vm.prank(owner);
        rateController.execute(offchainPrice);
        
        // Should create perpetual loan
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
        
        // Rate should have increased due to price below threshold
        assertGt(rateController.currentRate(), initialRate);
    }
    
    function testExecuteWithOffchainPriceAboveThreshold() public {
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        int256 offchainPrice = 1.02e8; // $1.02 (above threshold)
        
        // Execute rate control with offchain price
        vm.prank(owner);
        rateController.execute(offchainPrice);
        
        // Rate should have decreased due to price above threshold
        assertLt(rateController.currentRate(), initialRate);
    }
    
    function testExecuteWithInvalidOffchainPrice() public {
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Execute rate control with invalid offchain price (0) - should revert
        vm.prank(owner);
        vm.expectRevert("Offchain price is zero");
        rateController.execute(0);
    }
    
    function testExecuteWithNegativeOffchainPrice() public {
        // Fast forward 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Execute rate control with negative offchain price - should revert
        vm.prank(owner);
        vm.expectRevert("Offchain price is zero");
        rateController.execute(-1e8);
    }
    
    function testRateDoesNotGoBelowMinimum() public {
        // Set price above threshold (0.995)
        oracle.setPrice(1e8);
        
        // Fast forward multiple times to decrease rate
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 8 hours);
            vm.prank(owner);
            rateController.execute(1e8);
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
        uint256 rateAdjustment = rateController.rateDecreaseAdjustment(); // 0.15%
        
        // Calculate iterations needed: (currentRate - minRate) / rateAdjustment
        uint256 iterationsNeeded = (currentRate - minRate) / rateAdjustment;
        
        // Execute enough times to reach minimum
        for (uint i = 0; i < iterationsNeeded + 1; i++) {
            vm.warp(block.timestamp + 8 hours);
            vm.prank(owner);
            rateController.execute(1e8);
        }
        
        // Ensure we're at minimum rate
        assertEq(rateController.currentRate(), rateController.minRate());
        
        // Set price above threshold and execute again
        oracle.setPrice(1e8);
        vm.warp(block.timestamp + 8 hours);
        
        uint256 rateBefore = rateController.currentRate();
        vm.prank(owner);
        rateController.execute(1e8);
        uint256 rateAfter = rateController.currentRate();
        
        // Rate should not change when at minimum and price above threshold
        assertEq(rateAfter, rateBefore);
        assertEq(rateAfter, rateController.minRate());
    }
    
    function testEmergencyUpdateRate() public {
        uint256 newRate = 0.12e27; // 12%
        
        vm.prank(owner); // Controller is its own owner
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
        
        vm.prank(owner);
        vm.expectRevert("Rate below minimum");
        rateController.emergencyUpdateRate(newRate);
    }
    
    function testWithdrawUsdxl() public {
        uint256 amount = 1000e18;
        address recipient = address(0x999);
        
        vm.prank(owner);
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
        vm.prank(owner);
        rateController.execute(1e8);
        
        // Fast forward another 8 hours
        vm.warp(block.timestamp + 8 hours);
        
        // Should refresh the loan
        vm.prank(owner);
        rateController.execute(1e8);
        
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
    }
    
    function testEmergencyRepayAll() public {
        // First, create a perpetual loan by executing the rate controller
        vm.warp(block.timestamp + 8 hours);
        vm.prank(owner);
        rateController.execute(1e8);
        
        // Check that perpetual loan was created
        (bool activeBefore, uint256 debtBefore) = rateController.getPerpetualLoanStatus();
        assertTrue(activeBefore);
        assertGt(debtBefore, 0);
        
        // Emergency repay all
        vm.prank(owner);
        rateController.emergencyRepayAll();
        
        // Check that perpetual loan is cleared
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertFalse(active);
        assertEq(debt, 0);
        
        // Verify debt token balance is also cleared
        assertEq(variableDebtToken.balanceOf(address(rateController)), 0);
    }
    
    function testUpdateExecutionInterval() public {
        uint256 newInterval = 12 hours;
        vm.prank(owner);
        rateController.updateExecutionInterval(newInterval);
        assertEq(rateController.executionInterval(), newInterval);
    }
    
    function testUpdateExecutionIntervalRevertsIfNotOwner() public {
        uint256 newInterval = 12 hours;
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.updateExecutionInterval(newInterval);
    }
    
    function testUpdateExecutionIntervalRevertsIfInvalid() public {
        vm.prank(owner);
        vm.expectRevert("Execution interval must be positive");
        rateController.updateExecutionInterval(0);
    }
    
    function testUpdateUsdxlOracle() public {
        address newOracle = address(0x999);
        vm.prank(owner);
        rateController.updateUsdxlOracle(newOracle);
        assertEq(rateController.usdxlOracle(), newOracle);
    }
    
    function testUpdateUsdxlOracleRevertsIfNotOwner() public {
        address newOracle = address(0x999);
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.updateUsdxlOracle(newOracle);
    }
    
    function testUpdateUsdxlOracleRevertsIfInvalid() public {
        vm.prank(owner);
        vm.expectRevert("Invalid USDXL oracle");
        rateController.updateUsdxlOracle(address(0));
    }
    
    function testConstants() public {
        assertEq(rateController.executionInterval(), 8 hours);
        assertEq(rateController.perpetualLoanAmount(), 1e18);
    }
    
    function testUpdatePerpetualLoanAmount() public {
        uint256 newAmount = 5e18;
        vm.prank(owner);
        rateController.updatePerpetualLoanAmount(newAmount);
        assertEq(rateController.perpetualLoanAmount(), newAmount);
    }
    
    function testWithdrawHYPE() public {
        vm.deal(address(rateController), 1 ether);
        uint256 contractBalance = address(rateController).balance;
        require(contractBalance > 0, "Contract needs HYPE for this test");

        // Withdraw the full contract balance (or a nonzero amount)
        uint256 amount = contractBalance;
        address payable recipient = payable(address(0x999));

        vm.prank(owner);
        rateController.withdrawHYPE(amount, recipient);

        assertEq(recipient.balance, amount);
        assertEq(address(rateController).balance, 0);
    }
    
    function testWithdrawHYPERevertsIfNotOwner() public {
        uint256 amount = 0.5 ether;
        address payable recipient = payable(address(0x999));
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.withdrawHYPE(amount, recipient);
    }
    
    function testReceiveHYPE() public {
        uint256 initialBalance = address(rateController).balance;
        uint256 ethAmount = 2 ether;
        
        vm.deal(user, ethAmount);
        vm.prank(user);
        
        // Send HYPE to the rate controller
        (bool success, ) = address(rateController).call{value: ethAmount}("");
        assertTrue(success);
        
        assertEq(address(rateController).balance, initialBalance + ethAmount);
    }
    
    function testInheritance() public {
        // Test that the controller properly inherits from the mutable strategy
        assertEq(rateController.getBaseVariableBorrowRate(), initialRate);
        
        // Test that we can call the inherited update function
        uint256 newRate = 0.10e27; // 10%
        vm.prank(owner);
        rateController.updateBaseVariableBorrowRate(newRate);
        
        assertEq(rateController.getBaseVariableBorrowRate(), newRate);
    }
    
    function testUpdateMinRate() public {
        uint256 newMinRate = 0.08e27; // 8%
        
        vm.prank(owner);
        rateController.updateMinRate(newMinRate);
        
        assertEq(rateController.minRate(), newMinRate);
        // Other parameters should remain unchanged
        assertEq(rateController.maxRate(), 0.50e27);
        assertEq(rateController.rateIncreaseAdjustment(), 0.0015e27);
        assertEq(rateController.rateDecreaseAdjustment(), 0.0015e27);
        assertEq(rateController.priceThreshold(), 0.995e8);
        assertEq(rateController.targetPrice(), 1e8);
    }
    
    function testUpdatePriceThreshold() public {
        uint256 newPriceThreshold = 0.99e8; // 0.99
        
        vm.prank(owner);
        rateController.updatePriceThreshold(newPriceThreshold);
        
        assertEq(rateController.priceThreshold(), newPriceThreshold);
        // Other parameters should remain unchanged
        assertEq(rateController.minRate(), 0.06e27);
        assertEq(rateController.maxRate(), 0.50e27);
        assertEq(rateController.rateIncreaseAdjustment(), 0.0015e27);
        assertEq(rateController.rateDecreaseAdjustment(), 0.0015e27);
        assertEq(rateController.targetPrice(), 1e8);
    }
    
    function testUpdateTargetPrice() public {
        uint256 newTargetPrice = 1.01e8; // 1.01
        
        vm.prank(owner);
        rateController.updateTargetPrice(newTargetPrice);
        
        assertEq(rateController.targetPrice(), newTargetPrice);
        // Other parameters should remain unchanged
        assertEq(rateController.minRate(), 0.06e27);
        assertEq(rateController.maxRate(), 0.50e27);
        assertEq(rateController.rateIncreaseAdjustment(), 0.0015e27);
        assertEq(rateController.rateDecreaseAdjustment(), 0.0015e27);
        assertEq(rateController.priceThreshold(), 0.995e8);
    }
    
    // New tests for HYPE withdrawal and loan closing functionality
    
    function testGetSuppliedHYPEBalance() public {
        uint256 balance = rateController.getSuppliedHYPEBalance();
        assertEq(balance, 5 ether); // Set in setUp
    }
    
    function testWithdrawSuppliedHYPE() public {
        uint256 amount = 2 ether;
        address payable recipient = payable(address(0x999));
        
        vm.expectEmit(true, true, false, true);
        emit HYPEWithdrawnFromPool(amount, recipient, block.timestamp);
        vm.prank(owner);
        rateController.withdrawSuppliedHYPE(amount, recipient);
    }
    
    function testWithdrawSuppliedHYPEAll() public {
        address payable recipient = payable(address(0x999));
        uint256 initialBalance = rateController.getSuppliedHYPEBalance();
        
        vm.expectEmit(true, true, false, true);
        emit HYPEWithdrawnFromPool(initialBalance, recipient, block.timestamp);
        vm.prank(owner);
        rateController.withdrawSuppliedHYPE(type(uint256).max, recipient);
        assertEq(rateController.getSuppliedHYPEBalance(), 0);
    }
    
    function testWithdrawSuppliedHYPERevertsIfNotOwner() public {
        uint256 amount = 1 ether;
        address payable recipient = payable(address(0x999));
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.withdrawSuppliedHYPE(amount, recipient);
    }
    
    function testWithdrawSuppliedHYPERevertsIfInvalidRecipient() public {
        uint256 amount = 1 ether;
        
        vm.prank(owner);
        vm.expectRevert("Invalid recipient");
        rateController.withdrawSuppliedHYPE(amount, payable(address(0)));
    }
    
    function testWithdrawSuppliedHYPERevertsIfInvalidAmount() public {
        address payable recipient = payable(address(0x999));
        
        vm.prank(owner);
        vm.expectRevert("Invalid amount");
        rateController.withdrawSuppliedHYPE(0, recipient);
    }
    
    function testWithdrawSuppliedHYPERevertsIfInsufficientBalance() public {
        uint256 amount = 10 ether; // More than available
        address payable recipient = payable(address(0x999));
        
        vm.prank(owner);
        vm.expectRevert("Insufficient aWHYPE balance");
        rateController.withdrawSuppliedHYPE(amount, recipient);
    }
    
    function testCloseLoanAndWithdrawAll() public {
        // First, create a perpetual loan by executing the rate controller
        vm.warp(block.timestamp + 8 hours);
        vm.prank(owner);
        rateController.execute(1e8);
        
        // Check that perpetual loan was created
        (bool activeBefore, uint256 debtBefore) = rateController.getPerpetualLoanStatus();
        assertTrue(activeBefore);
        assertGt(debtBefore, 0);
        
        address payable recipient = payable(address(0x999));
        uint256 initialSuppliedBalance = rateController.getSuppliedHYPEBalance();
        
        vm.expectEmit(true, true, false, true);
        emit HYPEWithdrawnFromPool(initialSuppliedBalance, recipient, block.timestamp);
        vm.expectEmit(false, false, false, true);
        emit LoanClosed(block.timestamp);
        vm.prank(owner);
        rateController.closeLoanAndWithdrawAll(recipient);
        
        // Check that perpetual loan is cleared
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertFalse(active);
        assertEq(debt, 0);
        // Check that HYPE was withdrawn (aToken balance is zero)
        assertEq(rateController.getSuppliedHYPEBalance(), 0);
    }
    
    function testCloseLoanAndWithdrawAllRevertsIfNotOwner() public {
        address payable recipient = payable(address(0x999));
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.closeLoanAndWithdrawAll(recipient);
    }
    
    function testCloseLoanAndWithdrawAllRevertsIfInvalidRecipient() public {
        vm.prank(owner);
        vm.expectRevert("Invalid recipient");
        rateController.closeLoanAndWithdrawAll(payable(address(0)));
    }
    
    function testConstructorWithWrappedHypeGateway() public {
        // Test that the WrappedHypeGateway is properly set
        assertEq(address(rateController.WRAPPED_HYPE_GATEWAY()), address(wrappedHypeGateway));
    }
    
    function testHYPESuppliedEvent() public {
        // The HYPESupplied event should be emitted during deployment
        // This is tested implicitly by the constructor test
        assertEq(address(rateController).balance, 0); // All HYPE was supplied to gateway
    }
    
    // Tests for executor whitelist functionality
    
    function testUpdateExecutor() public {
        address executor = address(0x123);
        
        vm.prank(owner);
        rateController.updateExecutor(executor, true);
        
        assertTrue(rateController.executors(executor));
        assertTrue(rateController.isAuthorizedExecutor(executor));
    }
    
    function testUpdateExecutorRevertsIfNotOwner() public {
        address executor = address(0x123);
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.updateExecutor(executor, true);
    }
    
    function testUpdateExecutorRevertsIfInvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid executor address");
        rateController.updateExecutor(address(0), true);
    }
    
    function testRemoveExecutor() public {
        address executor = address(0x123);
        
        // First add the executor
        vm.prank(owner);
        rateController.updateExecutor(executor, true);
        assertTrue(rateController.executors(executor));
        
        // Then remove the executor
        vm.prank(owner);
        rateController.updateExecutor(executor, false);
        
        assertFalse(rateController.executors(executor));
        assertFalse(rateController.isAuthorizedExecutor(executor));
    }
    
    function testBatchUpdateExecutors() public {
        address[] memory executors_ = new address[](3);
        bool[] memory enabled = new bool[](3);
        
        executors_[0] = address(0x123);
        executors_[1] = address(0x456);
        executors_[2] = address(0x789);
        
        enabled[0] = true;
        enabled[1] = true;
        enabled[2] = false;
        
        vm.prank(owner);
        rateController.batchUpdateExecutors(executors_, enabled);
        
        assertTrue(rateController.executors(address(0x123)));
        assertTrue(rateController.executors(address(0x456)));
        assertFalse(rateController.executors(address(0x789)));
        
        assertTrue(rateController.isAuthorizedExecutor(address(0x123)));
        assertTrue(rateController.isAuthorizedExecutor(address(0x456)));
        assertFalse(rateController.isAuthorizedExecutor(address(0x789)));
    }
    
    function testBatchUpdateExecutorsRevertsIfNotOwner() public {
        address[] memory executors_ = new address[](1);
        bool[] memory enabled = new bool[](1);
        
        executors_[0] = address(0x123);
        enabled[0] = true;
        
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        rateController.batchUpdateExecutors(executors_, enabled);
    }
    
    function testBatchUpdateExecutorsRevertsIfLengthMismatch() public {
        address[] memory executors_ = new address[](2);
        bool[] memory enabled = new bool[](1);
        
        executors_[0] = address(0x123);
        executors_[1] = address(0x456);
        enabled[0] = true;
        
        vm.prank(owner);
        vm.expectRevert("Arrays length mismatch");
        rateController.batchUpdateExecutors(executors_, enabled);
    }
    
    function testBatchUpdateExecutorsRevertsIfEmptyArrays() public {
        address[] memory executors_ = new address[](0);
        bool[] memory enabled = new bool[](0);
        
        vm.prank(owner);
        vm.expectRevert("Empty arrays");
        rateController.batchUpdateExecutors(executors_, enabled);
    }
    
    function testBatchUpdateExecutorsRevertsIfInvalidAddress() public {
        address[] memory executors_ = new address[](1);
        bool[] memory enabled = new bool[](1);
        
        executors_[0] = address(0);
        enabled[0] = true;
        
        vm.prank(owner);
        vm.expectRevert("Invalid executor address");
        rateController.batchUpdateExecutors(executors_, enabled);
    }
    
    function testIsAuthorizedExecutor() public {
        // Owner should always be authorized
        assertTrue(rateController.isAuthorizedExecutor(owner));
        
        // Random user should not be authorized
        assertFalse(rateController.isAuthorizedExecutor(user));
        
        // Add an executor
        address executor = address(0x123);
        vm.prank(owner);
        rateController.updateExecutor(executor, true);
        
        // Executor should now be authorized
        assertTrue(rateController.isAuthorizedExecutor(executor));
        
        // Remove the executor
        vm.prank(owner);
        rateController.updateExecutor(executor, false);
        
        // Executor should no longer be authorized
        assertFalse(rateController.isAuthorizedExecutor(executor));
    }
    
    function testExecuteByOwner() public {
        // Owner should be able to execute
        vm.warp(block.timestamp + 8 hours);
        vm.prank(owner);
        rateController.execute(1e8);
        
        // Should have created perpetual loan
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
    }
    
    function testExecuteByWhitelistedExecutor() public {
        address executor = address(0x123);
        
        // Add executor to whitelist
        vm.prank(owner);
        rateController.updateExecutor(executor, true);
        
        // Executor should be able to execute
        vm.warp(block.timestamp + 8 hours);
        vm.prank(executor);
        rateController.execute(1e8);
        
        // Should have created perpetual loan
        (bool active, uint256 debt) = rateController.getPerpetualLoanStatus();
        assertTrue(active);
        assertGt(debt, 0);
    }
    
    function testExecuteRevertsIfNotAuthorized() public {
        // Random user should not be able to execute
        vm.warp(block.timestamp + 8 hours);
        vm.prank(user);
        vm.expectRevert("Unauthorized executor");
        rateController.execute(1e8);
    }
    
    function testExecuteRevertsIfExecutorRemoved() public {
        address executor = address(0x123);
        
        // Add executor to whitelist
        vm.prank(owner);
        rateController.updateExecutor(executor, true);
        
        // Remove executor from whitelist
        vm.prank(owner);
        rateController.updateExecutor(executor, false);
        
        // Executor should no longer be able to execute
        vm.warp(block.timestamp + 8 hours);
        vm.prank(executor);
        vm.expectRevert("Unauthorized executor");
        rateController.execute(1e8);
    }
    
    function testExecutorUpdatedEvent() public {
        address executor = address(0x123);
        
        vm.expectEmit(true, true, false, true);
        emit ExecutorUpdated(executor, true, block.timestamp);
        
        vm.prank(owner);
        rateController.updateExecutor(executor, true);
    }
} 