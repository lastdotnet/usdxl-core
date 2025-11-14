// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IUsdxlToken} from '../../../usdxl/interfaces/IUsdxlToken.sol';
import {UsdxlMutableInterestRateStrategy} from './UsdxlMutableInterestRateStrategy.sol';
import {IWrappedHypeGateway} from '@hypurrfi/periphery/contracts/misc/interfaces/IWrappedHypeGateway.sol';
import {IAToken} from '@aave/core-v3/contracts/interfaces/IAToken.sol';
import {AggregatorV3Interface} from '@hypurrfi/contracts/oracle/interfaces/AggregatorV3Interface.sol';

/**
 * @title UsdxlTargetRateController
 * @author Last Labs
 * @notice Controller for USDXL interest rates based on target rate calculation
 * @dev Implements a two-step process: Calculate Target Rate, then adjust Current Rate
 *      Target Rate = Base Rate * (Target Price / Current Price)^Rate Factor
 *      New Rate = Current Rate + adjustment based on halving factor and minimum change
 */
contract UsdxlTargetRateController is UsdxlMutableInterestRateStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Rate Update Parameters
    uint256 public targetPrice = 0.995e8; // USDXL price at which USDXL Rate = USDT0 Rate
    uint256 public rateFactor = 100; // Fixed input for target rate calculation
    uint256 public halvingFactor = 10e27; // Fixed input for rate adjustment
    uint256 public minimumChange = 0.0005e27; // Minimum change threshold (0.05%)
    uint256 public maxRate = 0.50e27; // 50% maximum rate (in ray) - prevents excessive rates
    uint256 public executionInterval = 4 hours;
    uint256 public baseRateWindow = 48 hours;

    // Perpetual Loan Storage
    uint256 public perpetualLoanAmount = 0.000001e18; // Perpetual loan amount (in USDXL)
    bool public perpetualLoanActive = false;
    uint256 public perpetualLoanDebt = 0;
    
    // State variables
    IUsdxlToken public immutable USDXL_TOKEN;
    address public immutable USDT0_TOKEN;
    IWrappedHypeGateway public immutable WRAPPED_HYPE_GATEWAY;
    
    uint256 public lastExecutionTime;
    uint256 public currentRate;
    
    // Circular buffer for storing USDT0 borrow rate samples
    uint256[] public usdt0RateSamples;
    uint256 public sampleIndex;
    uint256 public totalSamples;
    uint256 public lastSampleTime;
    
    // Executor whitelist
    mapping(address => bool) public executors;

    // Events
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 targetRate, uint256 usdxlPrice, uint256 timestamp);
    event TargetRateCalculated(uint256 baseRate, uint256 targetRate, uint256 usdxlPrice, uint256 timestamp);
    event BaseRateUpdated(uint256 newBaseRate, uint256 timestamp);
    event ExecutionSkipped(uint256 reason, uint256 timestamp, int256 offchainUsdxlPrice);
    event PriceDataEmitted(uint256 usdxlPrice, uint256 timestamp);
    event ParametersUpdated(
        uint256 targetPrice,
        uint256 rateFactor,
        uint256 halvingFactor,
        uint256 minimumChange,
        uint256 maxRate,
        uint256 timestamp
    );
    event HYPEReceived(address sender, uint256 amount);
    event HYPEWithdrawn(address recipient, uint256 amount);
    event HYPESupplied(uint256 amount, uint256 timestamp);
    event HYPEWithdrawnFromPool(uint256 amount, address recipient, uint256 timestamp);
    event ExecutorUpdated(address executor, bool enabled, uint256 timestamp);
    event ExecutionIntervalUpdated(uint256 newInterval, uint256 timestamp);
    event BaseRateWindowUpdated(uint256 newBaseRateWindow, uint256 timestamp);
    event LoanClosed(uint256 timestamp);
    event PerpetualLoanCreated(uint256 amount, uint256 timestamp);
    event PerpetualLoanRefreshed(uint256 repayAmount, uint256 borrowAmount, uint256 timestamp);

    // Errors
    error ExecutionTooEarly();
    error InvalidPrice();
    error InvalidBaseRate();
    error InvalidParameter();
    error UnauthorizedExecutor();
    error OraclePriceStale();
    error OraclePriceInvalid();

    // Modifiers
    modifier onlyOwnerOrExecutor() {
        require(msg.sender == owner() || executors[msg.sender], "Unauthorized executor");
        _;
    }

    /**
     * @dev Constructor
     * @param addressesProvider The Aave V3 Pool Addresses Provider
     * @param usdxlToken The USDXL token address
     * @param usdt0Token The USDT0 token address
     * @param initialRate The initial interest rate (in ray)
     * @param owner The owner address
     * @param wrappedHypeGateway The WrappedHypeGateway address
     */
    constructor(
        address addressesProvider,
        address usdxlToken,
        address usdt0Token,
        uint256 initialRate,
        address owner,
        address wrappedHypeGateway
    ) UsdxlMutableInterestRateStrategy(addressesProvider, initialRate, owner) payable {
        require(usdxlToken != address(0), "Invalid USDXL token");
        require(wrappedHypeGateway != address(0), "Invalid WrappedHypeGateway");

        USDXL_TOKEN = IUsdxlToken(usdxlToken);
        USDT0_TOKEN = usdt0Token;
        WRAPPED_HYPE_GATEWAY = IWrappedHypeGateway(wrappedHypeGateway);
        
        currentRate = initialRate;
        lastExecutionTime = block.timestamp;
        executionInterval = 4 hours; // Default execution interval
        
        // Initialize circular buffer for USDT0 rate samples
        // Calculate max samples based on BASE_RATE_WINDOW / executionInterval
        uint256 maxSamples = baseRateWindow / executionInterval;
        usdt0RateSamples = new uint256[](maxSamples);
        sampleIndex = 0;
        totalSamples = 0;
        lastSampleTime = block.timestamp;
        
        // Add initial USDT0 rate sample to the circular buffer
        uint256 initialUsdt0Rate = _sampleUsdt0Rate();
        _addUsdt0RateSample(initialUsdt0Rate);

        // If HYPE is sent on deployment, supply it to the WrappedHypeGateway
        if (msg.value > 0) {
            WRAPPED_HYPE_GATEWAY.depositHYPE{value: msg.value}(
                address(0),
                address(this),
                0
            );
            emit HYPESupplied(msg.value, block.timestamp);
        }
    }

    /**
     * @notice Execute rate control logic
     * @dev Implements two-step process: Calculate Target Rate, then adjust Current Rate
     * @param offchainUsdxlPrice Optional offchain-calculated USDXL price (8 decimals)
     */
    function execute(int256 offchainUsdxlPrice) external nonReentrant onlyOwnerOrExecutor {
        // Check if enough time has passed since last execution
        if (block.timestamp < lastExecutionTime + executionInterval) {
            emit ExecutionSkipped(1, block.timestamp, offchainUsdxlPrice); // Reason 1: Too early
            return;
        }
        
        if (offchainUsdxlPrice <= 0) {
            emit ExecutionSkipped(2, block.timestamp, offchainUsdxlPrice); // Reason 2: Invalid price
            return;
        }

        // Convert offchain price to uint256
        uint256 usdxlPrice = uint256(offchainUsdxlPrice);
        
        // Emit price data for transparency
        emit PriceDataEmitted(usdxlPrice, block.timestamp);

        // Step 1: Calculate Target Rate
        uint256 targetRate = _calculateTargetRate(usdxlPrice);
        uint256 currentBaseRate = _calculateTrailingAverage(); // Get current base rate for event
        emit TargetRateCalculated(currentBaseRate, targetRate, usdxlPrice, block.timestamp);

        // Step 2: Adjust Current Rate to New Rate
        uint256 newRate = _calculateNewRate(targetRate);
        
        // Update rate if it has changed
        if (newRate != currentRate) {
            _updateInterestRate(newRate);
            emit RateUpdated(currentRate, newRate, targetRate, usdxlPrice, block.timestamp);
            currentRate = newRate;
        }

        // Maintain perpetual loan to ensure rate updates
        _maintainPerpetualLoan();

        lastExecutionTime = block.timestamp;
    }

    /**
     * @notice Calculate target rate based on the formula
     * @param usdxlPrice Current USDXL price from oracle
     * @return targetRate The calculated target rate
     */
    function _calculateTargetRate(uint256 usdxlPrice) internal returns (uint256) {
        // Update base rate if needed
        uint256 currentBaseRate = _getCurrentBaseRate();
        
        // Target Rate = Base Rate * (Target Price / Current Price)^Rate Factor
        // Using fixed-point arithmetic for precision
        
        // Calculate (Target Price / Current Price)
        uint256 priceRatio = (targetPrice * 1e27) / usdxlPrice; // 27 decimals precision (ray)
        
        // Apply rate factor using simple multiplication/division
        // For rateFactor = 1e27, no change; for rateFactor > 1e27, amplify; for rateFactor < 1e27, dampen
        uint256 adjustedRatio = _applyRateFactor(priceRatio);
        
        // Calculate final target rate
        uint256 targetRate = (currentBaseRate * adjustedRatio) / 1e27;
        
        return targetRate;
    }

    /**
     * @notice Calculate new rate based on target rate, halving factor, and minimum change
     * @param targetRate The calculated target rate
     * @return newRate The new rate to set
     */
    function _calculateNewRate(uint256 targetRate) internal view returns (uint256) {
        // Calculate the difference between target and current rate
        uint256 rateDifference = targetRate > currentRate ? 
            (targetRate - currentRate) : 
            (currentRate - targetRate);
        
        // Apply halving factor using loop-based approach
        // This is more gas-efficient than using the _power function
        uint256 adjustment = _applyHalvingFactor(rateDifference);
        
        // Check if adjustment is greater than minimum change
        if (adjustment > minimumChange) {
            if (targetRate > currentRate) {
                return currentRate + adjustment;
            } else {
                return currentRate > adjustment ? currentRate - adjustment : 0;
            }
        }
        
        // No change if adjustment is below minimum threshold
        return currentRate;
    }

    /**
     * @notice Apply halving factor using efficient loop-based calculation
     * @param value The value to apply halving factor to
     * @return The result after applying halving factor
     */
    function _applyHalvingFactor(uint256 value) internal view returns (uint256) {
        if (halvingFactor == 1e27) {
            return value; // No change if halving factor is 1 (100% in ray)
        }
        
        // halvingFactor is in 27 decimals (ray), so we need to handle it properly
        uint256 result = value;
        
        // For halving factor > 1, we divide by it
        // For halving factor < 1, we multiply by (1/halvingFactor)
        if (halvingFactor > 1e27) {
            // Divide by halving factor
            result = (result * 1e27) / halvingFactor;
        } else if (halvingFactor < 1e27 && halvingFactor > 0) {
            // Multiply by (1e27 / halvingFactor) to get (1/halvingFactor)
            result = (result * 1e27) / halvingFactor;
        }
        
        return result;
    }

    /**
     * @notice Apply rate factor to price ratio using loop-based power calculation
     * @param priceRatio The price ratio (Target Price / Current Price)
     * @return result The adjusted ratio after applying rate factor
     * @dev Implements (priceRatio)^rateFactor by multiplying priceRatio by itself rateFactor times
     */
    function _applyRateFactor(uint256 priceRatio) internal view returns (uint256 result) {
        if (rateFactor == 1) {
            return priceRatio; // No change if rate factor is 1
        }
        
        if (rateFactor == 0) {
            return 1e27; // Return 1 in ray if rate factor is 0
        }
        
        // Apply power operation: multiply priceRatio by itself 'rateFactor' times
        // Each multiplication is followed by division by 1e27 to maintain precision
        result = priceRatio;
        
        for (uint256 i = 0; i < rateFactor; i++) {
            result = (result * priceRatio) / 1e27;
        }
        
        return result;
    }

    /**
     * @notice Sample current USDT0 borrow rate from Aave V3 pool
     * @return The current USDT0 variable borrow rate in ray
     */
    function _sampleUsdt0Rate() internal view returns (uint256) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        DataTypes.ReserveData memory reserveData = pool.getReserveData(address(USDT0_TOKEN));
        return reserveData.currentVariableBorrowRate;
    }

    /**
     * @notice Add a new USDT0 rate sample to the circular buffer
     * @param rate The USDT0 borrow rate to add
     */
    function _addUsdt0RateSample(uint256 rate) internal {
        // Calculate max samples based on current execution interval
        uint256 maxSamples = baseRateWindow / executionInterval;
        
        // Add the new sample to the circular buffer
        usdt0RateSamples[sampleIndex] = rate;
        
        // Update indices
        sampleIndex = (sampleIndex + 1) % maxSamples;
        if (totalSamples < maxSamples) {
            totalSamples++;
        }
        
        lastSampleTime = block.timestamp;
    }

    /**
     * @notice Calculate the trailing average of USDT0 borrow rates
     * @return The average USDT0 borrow rate in ray
     * @dev Uses all available samples if less than 48 hours worth of data
     */
    function _calculateTrailingAverage() internal view returns (uint256) {
        if (totalSamples == 0) {
            return 0;
        }
        
        uint256 sum = 0;
        for (uint256 i = 0; i < totalSamples; i++) {
            sum += usdt0RateSamples[i];
        }
        
        return sum / totalSamples;
    }

    /**
     * @notice Get current base rate (48-hour trailing average of USDT0 borrow rate)
     * @return The current base rate in ray
     */
    function _getCurrentBaseRate() internal returns (uint256) {
        // Sample current USDT0 borrow rate
        uint256 currentUsdt0Rate = _sampleUsdt0Rate();
        
        // Add to circular buffer
        _addUsdt0RateSample(currentUsdt0Rate);
        
        // Calculate trailing average
        uint256 currentBaseRate = _calculateTrailingAverage();
        
        emit BaseRateUpdated(currentBaseRate, block.timestamp);
        
        return currentBaseRate;
    }

    /**
     * @notice Get the current base rate (48-hour trailing average USDT0 borrow rate)
     * @return The current base rate in ray
     */
    function baseRate() external view returns (uint256) {
        return _calculateTrailingAverage();
    }

    /**
     * @notice Get the current maximum number of samples based on execution interval
     * @return The maximum number of samples that can be stored
     */
    function getMaxSamples() external view returns (uint256) {
        return baseRateWindow / executionInterval;
    }

    /**
     * @notice Get the current USDT0 rate samples for debugging
     * @return samples Array of stored USDT0 rate samples
     * @return currentIndex Current sample index
     * @return total Total number of samples stored
     * @return maxSamples Maximum number of samples that can be stored
     */
    function getUsdt0RateSamples() external view returns (uint256[] memory samples, uint256 currentIndex, uint256 total, uint256 maxSamples) {
        maxSamples = baseRateWindow / executionInterval;
        samples = new uint256[](totalSamples);
        for (uint256 i = 0; i < totalSamples; i++) {
            samples[i] = usdt0RateSamples[i];
        }
        return (samples, sampleIndex, totalSamples, maxSamples);
    }

    /**
     * @notice Get the current trailing average without updating samples
     * @return The current 48-hour trailing average in ray
     */
    function getCurrentTrailingAverage() external view returns (uint256) {
        return _calculateTrailingAverage();
    }

    /**
     * @notice Get USDXL price from Chainlink oracle
     * @param offchainPrice Optional offchain price
     * @return The USDXL price in USD (8 decimals)
     */
    function _getUsdxlPrice(int256 offchainPrice) internal pure returns (uint256) {
        require(offchainPrice > 0, "Offchain price must be positive");
        return uint256(offchainPrice);
    }

    /**
     * @notice Update all parameters
     * @param newTargetPrice The new target price
     * @param newRateFactor The new rate factor
     * @param newHalvingFactor The new halving factor
     * @param newMinimumChange The new minimum change
     * @param newMaxRate The new maximum rate (cannot exceed 100%)
     * @dev Only callable by owner
     */
    function updateParameters(
        uint256 newTargetPrice,
        uint256 newRateFactor,
        uint256 newHalvingFactor,
        uint256 newMinimumChange,
        uint256 newMaxRate
    ) external onlyOwner {
        require(newTargetPrice > 0, "Target price must be positive");
        require(newRateFactor >= 0, "Rate factor must be non-negative");
        require(newHalvingFactor > 0, "Halving factor must be positive");
        require(newMinimumChange > 0, "Minimum change must be positive");
        require(newMaxRate > 0, "Max rate must be positive");
        require(newMaxRate <= 1e27, "Max rate cannot exceed 100%");
        
        targetPrice = newTargetPrice;
        rateFactor = newRateFactor;
        halvingFactor = newHalvingFactor;
        minimumChange = newMinimumChange;
        maxRate = newMaxRate;
        
        emit ParametersUpdated(
            newTargetPrice,
            newRateFactor,
            newHalvingFactor,
            newMinimumChange,
            newMaxRate,
            block.timestamp
        );
    }

    /**
     * @notice Update execution interval
     * @param newInterval The new execution interval in seconds
     * @dev Only callable by owner
     */
    function updateExecutionInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Execution interval must be positive");
        require(newInterval <= baseRateWindow, "Execution interval cannot exceed base rate window");
        
        uint256 oldMaxSamples = baseRateWindow / executionInterval;
        executionInterval = newInterval;
        uint256 newMaxSamples = baseRateWindow / executionInterval;
        
        // If the new max samples is different, we need to resize the buffer
        if (newMaxSamples != oldMaxSamples) {
            _resizeBuffer(newMaxSamples);
        }
        
        emit ExecutionIntervalUpdated(executionInterval, block.timestamp);
    }

    /**
     * @notice Update the base rate window
     * @param newBaseRateWindow The new base rate window in seconds
     * @dev Only callable by owner
     * @dev Must be >= executionInterval and an exact multiple of executionInterval
     */
    function updateBaseRateWindow(uint256 newBaseRateWindow) external onlyOwner {
        require(newBaseRateWindow >= executionInterval, "Base rate window must be >= execution interval");
        require(newBaseRateWindow % executionInterval == 0, "Base rate window must be exact multiple of execution interval");
        
        uint256 oldMaxSamples = baseRateWindow / executionInterval;
        baseRateWindow = newBaseRateWindow;
        uint256 newMaxSamples = baseRateWindow / executionInterval;
        
        // If the new max samples is different, we need to resize the buffer
        if (newMaxSamples != oldMaxSamples) {
            _resizeBuffer(newMaxSamples);
        }
        
        emit BaseRateWindowUpdated(baseRateWindow, block.timestamp);
    }

    /**
     * @notice Resize the circular buffer when execution interval changes
     * @param newMaxSamples The new maximum number of samples
     */
    function _resizeBuffer(uint256 newMaxSamples) internal {
        uint256[] memory oldSamples = usdt0RateSamples;
        uint256 oldTotalSamples = totalSamples;
        
        // Create new buffer
        usdt0RateSamples = new uint256[](newMaxSamples);
        
        // Copy existing samples, keeping the most recent ones
        uint256 samplesToCopy = oldTotalSamples > newMaxSamples ? newMaxSamples : oldTotalSamples;
        
        if (samplesToCopy > 0 && oldSamples.length > 0) {
            for (uint256 i = 0; i < samplesToCopy; i++) {
                // Start from the most recent samples
                // Calculate the starting index for the most recent samples
                uint256 startIndex = sampleIndex >= samplesToCopy ? sampleIndex - samplesToCopy : 0;
                uint256 oldIndex = (startIndex + i) % oldSamples.length;
                usdt0RateSamples[i] = oldSamples[oldIndex];
            }
        }
        
        // Reset indices
        sampleIndex = samplesToCopy % newMaxSamples;
        totalSamples = samplesToCopy;
    }

    /**
     * @notice Emergency function to update rate manually
     * @param newRate The new interest rate (in ray)
     * @dev Only callable by owner
     */
    function emergencyUpdateRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Rate must be positive");
        _updateInterestRate(newRate);
        currentRate = newRate;
        emit RateUpdated(currentRate, newRate, 0, 0, block.timestamp);
    }

    /**
     * @notice Get the next execution time
     * @return The timestamp when execute() can be called next
     */
    function getNextExecutionTime() external view returns (uint256) {
        return lastExecutionTime + executionInterval;
    }

    /**
     * @notice Check if execution is due
     * @return True if enough time has passed since last execution
     */
    function isExecutionDue() external view returns (bool) {
        return block.timestamp >= lastExecutionTime + executionInterval;
    }

    /**
     * @notice Get all current parameters
     * @return baseRate_ The current base rate (calculated dynamically)
     * @return targetPrice_ The current target price
     * @return rateFactor_ The current rate factor
     * @return halvingFactor_ The current halving factor
     * @return minimumChange_ The current minimum change
     * @return maxRate_ The current maximum rate
     * @return baseRateWindow_ The current base rate window
     * @return executionInterval_ The current execution interval
     */
    function getParameters() external view returns (
        uint256 baseRate_,
        uint256 targetPrice_,
        uint256 rateFactor_,
        uint256 halvingFactor_,
        uint256 minimumChange_,
        uint256 maxRate_,
        uint256 baseRateWindow_,
        uint256 executionInterval_
    ) {
        return (_calculateTrailingAverage(), targetPrice, rateFactor, halvingFactor, minimumChange, maxRate, baseRateWindow, executionInterval);
    }

    /**
     * @dev Update the interest rate strategy with new rate
     * @param newRate The new interest rate (in ray)
     */
    function _updateInterestRate(uint256 newRate) internal {
        // Cap the rate at maxRate to prevent excessive rates
        if (newRate > maxRate) {
            newRate = maxRate;
        }
        
        // Always update the rate (either the calculated rate or the capped rate)
        _baseVariableBorrowRate = newRate;
    }

    /**
     * @dev Maintain perpetual loan to ensure rate updates
     * Creates or refreshes a perpetual loan to keep the rate mechanism active
     */
    function _maintainPerpetualLoan() internal {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        
        if (!perpetualLoanActive) {
            // Create initial perpetual loan
            pool.borrow(
                address(USDXL_TOKEN),
                perpetualLoanAmount,
                2, // Variable rate mode
                0, // Referral code
                address(this)
            );
            perpetualLoanActive = true;
            perpetualLoanDebt = perpetualLoanAmount;
            emit PerpetualLoanCreated(perpetualLoanAmount, block.timestamp);
        } else {
            // Refresh perpetual loan by repaying and reborrowing
            uint256 repayAmount = _getCurrentDebt() / 1000;
            uint256 borrowAmount = perpetualLoanAmount / 1000;
            USDXL_TOKEN.approve(address(pool), repayAmount);
            if (_getCurrentDebt() > 0) {
                // Repay current debt
                USDXL_TOKEN.approve(address(pool), repayAmount);
                pool.repay(
                    address(USDXL_TOKEN),
                    repayAmount,
                    2, // Variable rate mode
                    address(this)
                );
                pool.borrow(
                    address(USDXL_TOKEN),
                    borrowAmount,
                    2, // Variable rate mode
                    0, // Referral code
                    address(this)
                );
                emit PerpetualLoanRefreshed(repayAmount, borrowAmount, block.timestamp);
            }
        }
    }

    /**
     * @dev Get current debt amount for this contract
     * @return The current debt amount
     */
    function _getCurrentDebt() internal view returns (uint256) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        DataTypes.ReserveData memory reserveData = pool.getReserveData(address(USDXL_TOKEN));
        
        // Get variable debt token
        address variableDebtToken = reserveData.variableDebtTokenAddress;
        if (variableDebtToken == address(0)) return 0;
        
        return IERC20(variableDebtToken).balanceOf(address(this));
    }

    /**
     * @notice Get current perpetual loan status
     * @return active Whether the perpetual loan is active
     * @return debt The current debt amount
     */
    function getPerpetualLoanStatus() external view returns (bool active, uint256 debt) {
        return (perpetualLoanActive, _getCurrentDebt());
    }

    /**
     * @notice Emergency function to repay all debt and deactivate perpetual loan
     * @dev Only callable by owner
     */
    function emergencyRepayAll() external onlyOwner {
        uint256 currentDebt = _getCurrentDebt();
        if (currentDebt > 0) {
            IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
            USDXL_TOKEN.approve(address(pool), currentDebt);
            
            try pool.repay(
                address(USDXL_TOKEN),
                currentDebt,
                2, // Variable rate mode
                address(this)
            ) {
                perpetualLoanActive = false;
                perpetualLoanDebt = 0;
            } catch {
                revert("Repay failed");
            }
        } else {
        }
    }

    /**
     * @notice Get the current interest rate from the strategy
     * @return The current interest rate (in ray)
     */
    function getCurrentInterestRate() external view returns (uint256) {
        return _baseVariableBorrowRate;
    }

    /**
     * @notice Withdraw supplied HYPE from the lending pool
     * @param amount The amount of aWHYPE to withdraw (use type(uint256).max for all)
     * @param to The recipient address for the HYPE
     * @dev Only callable by owner
     */
    function withdrawSuppliedHYPE(uint256 amount, address payable to) external onlyOwner nonReentrant {
        _withdrawSuppliedHYPE(amount, to);
    }

    function _withdrawSuppliedHYPE(uint256 amount, address payable to) internal {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        // Get the aWHYPE token address
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        address whypeAddress = WRAPPED_HYPE_GATEWAY.getWHYPEAddress();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(whypeAddress);
        address aWhypeAddress = reserveData.aTokenAddress;
        require(aWhypeAddress != address(0), "aWHYPE token not found");
        IAToken aWhype = IAToken(aWhypeAddress);
        uint256 balance = aWhype.balanceOf(address(this));
        require(balance > 0, "No supplied HYPE to withdraw");
        uint256 amountToWithdraw = amount;
        if (amount == type(uint256).max) {
            amountToWithdraw = balance;
        } else {
            require(amount <= balance, "Insufficient aWHYPE balance");
        }
        aWhype.approve(address(WRAPPED_HYPE_GATEWAY), amountToWithdraw);
        WRAPPED_HYPE_GATEWAY.withdrawHYPE(address(0), amountToWithdraw, to);
        emit HYPEWithdrawnFromPool(amountToWithdraw, to, block.timestamp);
    }

    /**
     * @notice Close the perpetual loan and withdraw all supplied HYPE
     * @param to The recipient address for the withdrawn HYPE
     * @dev Only callable by owner
     */
    function closeLoanAndWithdrawAll(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        // First, repay all debt if there is any
        uint256 currentDebt = _getCurrentDebt();
        if (currentDebt > 0) {
            IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
            USDXL_TOKEN.approve(address(pool), currentDebt);
            try pool.repay(
                address(USDXL_TOKEN),
                currentDebt,
                2, // Variable rate mode
                address(this)
            ) {
                perpetualLoanActive = false;
                perpetualLoanDebt = 0;
            } catch {
                revert("Failed to repay debt");
            }
        } else {
            perpetualLoanActive = false;
            perpetualLoanDebt = 0;
        }
        // Withdraw all supplied HYPE
        _withdrawSuppliedHYPE(type(uint256).max, to);
        emit LoanClosed(block.timestamp);
    }

    /**
     * @notice Get the current supplied HYPE balance
     * @return The current aWHYPE balance
     */
    function getSuppliedHYPEBalance() external view returns (uint256) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        address whypeAddress = WRAPPED_HYPE_GATEWAY.getWHYPEAddress();
        DataTypes.ReserveData memory reserveData = pool.getReserveData(whypeAddress);
        address aWhypeAddress = reserveData.aTokenAddress;
        
        if (aWhypeAddress == address(0)) {
            return 0;
        }
        
        IAToken aWhype = IAToken(aWhypeAddress);
        return aWhype.balanceOf(address(this));
    }

    /**
     * @notice Withdraw HYPE from the controller
     * @param amount The amount to withdraw
     * @param to The recipient address
     * @dev Only callable by owner
     */
    function withdrawHYPE(uint256 amount, address payable to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(address(this).balance >= amount, "Insufficient HYPE balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "HYPE transfer failed");
        
        emit HYPEWithdrawn(to, amount);
    }

    /**
     * @dev Fallback function to receive HYPE
     */
    receive() external payable {
        emit HYPEReceived(msg.sender, msg.value);
    }

    /**
     * @notice Add or remove an executor from the whitelist
     * @param executor The address to add/remove
     * @param enabled True to add, false to remove
     * @dev Only callable by owner
     */
    function updateExecutor(address executor, bool enabled) external onlyOwner {
        require(executor != address(0), "Invalid executor address");
        executors[executor] = enabled;
        emit ExecutorUpdated(executor, enabled, block.timestamp);
    }

    /**
     * @notice Batch update multiple executors
     * @param executors_ Array of executor addresses
     * @param enabled Array of boolean values (true to add, false to remove)
     * @dev Only callable by owner
     */
    function batchUpdateExecutors(address[] calldata executors_, bool[] calldata enabled) external onlyOwner {
        require(executors_.length == enabled.length, "Arrays length mismatch");
        require(executors_.length > 0, "Empty arrays");
        
        for (uint256 i = 0; i < executors_.length; i++) {
            require(executors_[i] != address(0), "Invalid executor address");
            executors[executors_[i]] = enabled[i];
            emit ExecutorUpdated(executors_[i], enabled[i], block.timestamp);
        }
    }

    /**
     * @notice Check if an address is an authorized executor
     * @param executor The address to check
     * @return True if the address is owner or whitelisted executor
     */
    function isAuthorizedExecutor(address executor) external view returns (bool) {
        return executor == owner() || executors[executor];
    }
}
