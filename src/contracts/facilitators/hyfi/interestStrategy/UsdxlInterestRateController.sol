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

/**
 * @title UsdxlInterestRateController
 * @author Last Labs
 * @notice Controller for USDXL interest rates based on price deviation from peg
 * @dev Runs 3 times per day, maintains perpetual loan to ensure rate updates, 
 *      adjusts rates based on USDXL price relative to $1 peg
 */
contract UsdxlInterestRateController is UsdxlMutableInterestRateStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Configurable parameters (can be updated by owner)
    uint256 public minRate = 0.085e27; // 8.5% minimum rate (in ray)
    uint256 public maxRate = 0.50e27; // 50% maximum rate (in ray)
    uint256 public rateIncreaseAdjustment = 0.002e27; // 0.2% increase tick (in ray)
    uint256 public rateDecreaseAdjustment = 0.001e27; // 0.1% decrease tick (in ray)
    uint256 public priceThreshold = 0.995e8; // 0.995 threshold for rate adjustments
    uint256 public targetPrice = 1e8; // $1 target price (8 decimals)
    uint256 public perpetualLoanAmount; // Perpetual loan amount (in USDXL)
    uint256 public executionInterval; // Execution interval in seconds
    address public usdxlOracle; // USDXL oracle address

    // State variables
    IUsdxlToken public immutable USDXL_TOKEN;
    address public immutable USDXL_RESERVE;
    IWrappedHypeGateway public immutable WRAPPED_HYPE_GATEWAY;
    
    uint256 public lastExecutionTime;
    uint256 public currentRate;
    bool public perpetualLoanActive;
    uint256 public perpetualLoanDebt;

    // Executor whitelist
    mapping(address => bool) public executors;

    // Events
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 usdxlPrice, uint256 timestamp);
    event PerpetualLoanCreated(uint256 amount, uint256 timestamp);
    event PerpetualLoanRefreshed(uint256 repayAmount, uint256 borrowAmount, uint256 timestamp);
    event ExecutionSkipped(uint256 reason, uint256 timestamp);
    event PriceDataEmitted(uint256 offchainPrice, uint256 onchainPrice, uint256 timestamp);
    event PerpetualLoanAmountUpdated(uint256 oldAmount, uint256 newAmount, uint256 timestamp);
    event ExecutionIntervalUpdated(uint256 oldInterval, uint256 newInterval, uint256 timestamp);
    event UsdxlOracleUpdated(address oldOracle, address newOracle, uint256 timestamp);
    event MaxRateUpdated(uint256 oldMaxRate, uint256 newMaxRate, uint256 timestamp);
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
    event HYPEReceived(address sender, uint256 amount);
    event HYPEWithdrawn(address recipient, uint256 amount);
    event HYPESupplied(uint256 amount, uint256 timestamp);
    event HYPEWithdrawnFromPool(uint256 amount, address recipient, uint256 timestamp);
    event LoanClosed(uint256 timestamp);

    // Errors
    error ExecutionTooEarly();
    error InvalidOraclePrice();
    error PerpetualLoanFailed();
    error RateUpdateFailed();
    error InvalidParameter();
    error UnauthorizedExecutor();

    // Modifiers
    modifier onlyOwnerOrExecutor() {
        require(msg.sender == owner() || executors[msg.sender], "Unauthorized executor");
        _;
    }

    /**
     * @dev Constructor
     * @param addressesProvider The Aave V3 Pool Addresses Provider
     * @param usdxlToken The USDXL token address
     * @param usdxlOracleAddress The USDXL oracle address
     * @param usdxlReserve The USDXL reserve address in the pool
     * @param initialRate The initial interest rate (in ray)
     * @param owner The owner address
     * @param initialPerpetualLoanAmount The initial perpetual loan amount (in USDXL)
     * @param wrappedHypeGateway The WrappedHypeGateway address
     */
    constructor(
        address addressesProvider,
        address usdxlToken,
        address usdxlOracleAddress,
        address usdxlReserve,
        uint256 initialRate,
        address owner,
        uint256 initialPerpetualLoanAmount,
        address wrappedHypeGateway
    ) UsdxlMutableInterestRateStrategy(addressesProvider, initialRate, owner) payable {
        require(usdxlToken != address(0), "Invalid USDXL token");
        require(usdxlOracleAddress != address(0), "Invalid USDXL oracle");
        require(usdxlReserve != address(0), "Invalid USDXL reserve");
        require(wrappedHypeGateway != address(0), "Invalid WrappedHypeGateway");
        require(initialRate >= minRate, "Rate below minimum");
        require(initialRate <= maxRate, "Rate above maximum");
        require(initialPerpetualLoanAmount > 0, "Invalid perpetual loan amount");

        USDXL_TOKEN = IUsdxlToken(usdxlToken);
        USDXL_RESERVE = usdxlReserve;
        WRAPPED_HYPE_GATEWAY = IWrappedHypeGateway(wrappedHypeGateway);
        currentRate = initialRate;
        lastExecutionTime = block.timestamp;
        perpetualLoanAmount = initialPerpetualLoanAmount;
        executionInterval = 4 hours; // Default execution interval
        usdxlOracle = usdxlOracleAddress;

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
     * @notice Update maximum rate only
     * @param newMaxRate The new maximum rate (in ray)
     * @dev Only callable by owner
     */
    function updateMaxRate(uint256 newMaxRate) external onlyOwner {
        require(newMaxRate > 0, "Max rate must be positive");
        require(newMaxRate > minRate, "Max rate must exceed min rate");
        if (currentRate > newMaxRate) {
            currentRate = newMaxRate;
        }

        uint256 oldMaxRate = maxRate;
        maxRate = newMaxRate;

        emit MaxRateUpdated(oldMaxRate, newMaxRate, block.timestamp);
    }

    /**
     * @notice Update configurable parameters
     * @param newMinRate The new minimum rate (in ray)
     * @param newMaxRate The new maximum rate (in ray)
     * @param newRateIncreaseAdjustment The new rate increase tick (in ray)
     * @param newRateDecreaseAdjustment The new rate decrease tick (in ray)
     * @param newPriceThreshold The new price threshold (8 decimals)
     * @param newTargetPrice The new target price (8 decimals)
     * @dev Only callable by owner
     */
    function updateParameters(
        uint256 newMinRate,
        uint256 newMaxRate,
        uint256 newRateIncreaseAdjustment,
        uint256 newRateDecreaseAdjustment,
        uint256 newPriceThreshold,
        uint256 newTargetPrice
    ) external onlyOwner {
        // Validate parameters
        require(newMinRate > 0, "Min rate must be positive");
        require(newMaxRate > 0, "Max rate must be positive");
        require(newMaxRate > newMinRate, "Max rate must exceed min rate");
        require(newRateIncreaseAdjustment > 0, "Increase adjustment must be positive");
        require(newRateDecreaseAdjustment > 0, "Decrease adjustment must be positive");
        require(newPriceThreshold > 0, "Price threshold must be positive");
        require(newTargetPrice > 0, "Target price must be positive");
        require(newPriceThreshold <= newTargetPrice, "Threshold cannot exceed target");
        // Ensure current rate doesn't go outside new bounds
        if (currentRate < newMinRate) {
            revert("Current rate below new minimum");
        }
        if (currentRate > newMaxRate) {
            currentRate = newMaxRate;
        }
        // Update parameters
        minRate = newMinRate;
        maxRate = newMaxRate;
        rateIncreaseAdjustment = newRateIncreaseAdjustment;
        rateDecreaseAdjustment = newRateDecreaseAdjustment;
        priceThreshold = newPriceThreshold;
        targetPrice = newTargetPrice;
        emit ParametersUpdated(
            newMinRate,
            newMaxRate,
            newRateIncreaseAdjustment,
            newRateDecreaseAdjustment,
            newPriceThreshold,
            newTargetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update minimum rate only
     * @param newMinRate The new minimum rate (in ray)
     * @dev Only callable by owner
     */
    function updateMinRate(uint256 newMinRate) external onlyOwner {
        require(newMinRate > 0, "Min rate must be positive");
        if (currentRate < newMinRate) {
            revert("Current rate below new minimum");
        }
        minRate = newMinRate;
        emit ParametersUpdated(
            newMinRate,
            maxRate,
            rateIncreaseAdjustment,
            rateDecreaseAdjustment,
            priceThreshold,
            targetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update rate increase adjustment only
     * @param newRateIncreaseAdjustment The new rate increase tick (in ray)
     * @dev Only callable by owner
     */
    function updateRateIncreaseAdjustment(uint256 newRateIncreaseAdjustment) external onlyOwner {
        require(newRateIncreaseAdjustment > 0, "Increase adjustment must be positive");
        rateIncreaseAdjustment = newRateIncreaseAdjustment;
        emit ParametersUpdated(
            minRate,
            maxRate,
            newRateIncreaseAdjustment,
            rateDecreaseAdjustment,
            priceThreshold,
            targetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update rate decrease adjustment only
     * @param newRateDecreaseAdjustment The new rate decrease tick (in ray)
     * @dev Only callable by owner
     */
    function updateRateDecreaseAdjustment(uint256 newRateDecreaseAdjustment) external onlyOwner {
        require(newRateDecreaseAdjustment > 0, "Decrease adjustment must be positive");
        rateDecreaseAdjustment = newRateDecreaseAdjustment;
        emit ParametersUpdated(
            minRate,
            maxRate,
            rateIncreaseAdjustment,
            newRateDecreaseAdjustment,
            priceThreshold,
            targetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update price threshold only
     * @param newPriceThreshold The new price threshold (8 decimals)
     * @dev Only callable by owner
     */
    function updatePriceThreshold(uint256 newPriceThreshold) external onlyOwner {
        require(newPriceThreshold > 0, "Price threshold must be positive");
        require(newPriceThreshold <= targetPrice, "Threshold cannot exceed target");
        priceThreshold = newPriceThreshold;
        emit ParametersUpdated(
            minRate,
            maxRate,
            rateIncreaseAdjustment,
            rateDecreaseAdjustment,
            newPriceThreshold,
            targetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update target price only
     * @param newTargetPrice The new target price (8 decimals)
     * @dev Only callable by owner
     */
    function updateTargetPrice(uint256 newTargetPrice) external onlyOwner {
        require(newTargetPrice > 0, "Target price must be positive");
        require(priceThreshold <= newTargetPrice, "Threshold cannot exceed target");
        targetPrice = newTargetPrice;
        emit ParametersUpdated(
            minRate,
            maxRate,
            rateIncreaseAdjustment,
            rateDecreaseAdjustment,
            priceThreshold,
            newTargetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update perpetual loan amount
     * @param newAmount The new perpetual loan amount (in USDXL)
     * @dev Only callable by owner
     */
    function updatePerpetualLoanAmount(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Invalid perpetual loan amount");
        uint256 oldAmount = perpetualLoanAmount;
        perpetualLoanAmount = newAmount;
        emit PerpetualLoanAmountUpdated(oldAmount, newAmount, block.timestamp);
    }

    /**
     * @notice Update execution interval
     * @param newInterval The new execution interval in seconds
     * @dev Only callable by owner
     */
    function updateExecutionInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Execution interval must be positive");
        uint256 oldInterval = executionInterval;
        executionInterval = newInterval;
        emit ExecutionIntervalUpdated(oldInterval, newInterval, block.timestamp);
    }

    /**
     * @notice Update USDXL oracle
     * @param newOracle The new USDXL oracle address
     * @dev Only callable by owner
     */
    function updateUsdxlOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid USDXL oracle");
        address oldOracle = usdxlOracle;
        usdxlOracle = newOracle;
        emit UsdxlOracleUpdated(oldOracle, newOracle, block.timestamp);
    }

    /**
     * @notice Execute rate control logic
     * @dev Can be called by anyone, but only executes if enough time has passed
     * @param offchainPrice Optional offchain-calculated USDXL price (8 decimals)
     */
    function execute(int256 offchainPrice) external nonReentrant onlyOwnerOrExecutor {
        // Check if enough time has passed since last execution
        if (block.timestamp < lastExecutionTime + executionInterval) {
            emit ExecutionSkipped(1, block.timestamp); // Reason 1: Too early
            return;
        }

        // If offchainPrice is provided but zero, revert
        if (offchainPrice <= 0) {
            revert("Offchain price is zero");
        }

        // Get current USDXL price (onchain)
        uint256 onchainPrice = _getUsdxlPrice();
        
        // Use offchain price if provided and valid, otherwise use onchain price
        uint256 usdxlPrice = uint256(offchainPrice);
        
        if (usdxlPrice == 0) {
            emit ExecutionSkipped(2, block.timestamp); // Reason 2: Invalid price
            return;
        }

        // Emit price data for transparency
        emit PriceDataEmitted(uint256(offchainPrice), onchainPrice, block.timestamp);

        // Maintain perpetual loan to ensure rate updates
        _maintainPerpetualLoan();

        // Calculate new rate based on price
        uint256 newRate = _calculateNewRate(usdxlPrice);
        
        // Update rate if it has changed
        if (newRate != currentRate) {
            _updateInterestRate(newRate);
            emit RateUpdated(currentRate, newRate, usdxlPrice, block.timestamp);
            currentRate = newRate;
        }

        lastExecutionTime = block.timestamp;
    }

    /**
     * @notice Emergency function to update rate manually
     * @param newRate The new interest rate (in ray)
     * @dev Only callable by owner
     */
    function emergencyUpdateRate(uint256 newRate) external onlyOwner {
        require(newRate >= minRate, "Rate below minimum");
        require(newRate <= maxRate, "Rate above maximum");
        _updateInterestRate(newRate);
        currentRate = newRate;
        emit RateUpdated(currentRate, newRate, 0, block.timestamp);
    }

    /**
     * @notice Withdraw any accumulated USDXL from the controller
     * @param amount The amount to withdraw
     * @param to The recipient address
     * @dev Only callable by owner
     */
    function withdrawUsdxl(uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(USDXL_TOKEN.balanceOf(address(this)) >= amount, "Insufficient balance");
        
        USDXL_TOKEN.transfer(to, amount);
    }

    /**
     * @notice Get current USDXL price from oracle
     * @return The USDXL price in USD (8 decimals)
     */
    function getUsdxlPrice() external view returns (uint256) {
        return _getUsdxlPrice();
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
     * @return minRate_ The current minimum rate
     * @return maxRate_ The current maximum rate
     * @return rateIncreaseAdjustment_ The current rate increase tick
     * @return rateDecreaseAdjustment_ The current rate decrease tick
     * @return priceThreshold_ The current price threshold
     * @return targetPrice_ The current target price
     */
    function getParameters() external view returns (
        uint256 minRate_,
        uint256 maxRate_,
        uint256 rateIncreaseAdjustment_,
        uint256 rateDecreaseAdjustment_,
        uint256 priceThreshold_,
        uint256 targetPrice_
    ) {
        return (minRate, maxRate, rateIncreaseAdjustment, rateDecreaseAdjustment, priceThreshold, targetPrice);
    }

    /**
     * @dev Get USDXL price from oracle
     * @return The USDXL price in USD (8 decimals)
     */
    function _getUsdxlPrice() internal view returns (uint256) {
        try this._callOracle() returns (int256 price) {
            if (price <= 0) return 0;
            return uint256(price);
        } catch {
            return 0;
        }
    }

    /**
     * @dev External function to call oracle (needed for try/catch)
     * @return The USDXL price from oracle
     */
    function _callOracle() external view returns (int256) {
        // Call the oracle's latestAnswer function
        (bool success, bytes memory data) = usdxlOracle.staticcall(
            abi.encodeWithSignature("latestAnswer()")
        );
        
        if (!success || data.length == 0) {
            return 0;
        }
        
        return abi.decode(data, (int256));
    }

    /**
     * @dev Calculate new interest rate based on USDXL price
     * @param usdxlPrice The current USDXL price
     * @return The new interest rate (in ray)
     */
    function _calculateNewRate(uint256 usdxlPrice) internal view returns (uint256) {
        uint256 newRate = currentRate;
        if (usdxlPrice < priceThreshold) {
            // USDXL price below threshold, increase rate
            newRate = currentRate + rateIncreaseAdjustment;
            if (newRate > maxRate) {
                newRate = maxRate;
            }
        } else if (usdxlPrice >= priceThreshold && currentRate > minRate) {
            // USDXL price at or above threshold and current rate above minimum, decrease rate
            newRate = currentRate > rateDecreaseAdjustment ? currentRate - rateDecreaseAdjustment : minRate;
            if (newRate < minRate) {
                newRate = minRate;
            }
        }
        return newRate;
    }

    /**
     * @dev Update the interest rate strategy with new rate
     * @param newRate The new interest rate (in ray)
     */
    function _updateInterestRate(uint256 newRate) internal {
        // Update the rate directly in the inherited interest rate strategy
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
            try pool.borrow(
                USDXL_RESERVE,
                perpetualLoanAmount,
                2, // Variable rate mode
                0, // Referral code
                address(this)
            ) {
                perpetualLoanActive = true;
                perpetualLoanDebt = perpetualLoanAmount;
                emit PerpetualLoanCreated(perpetualLoanAmount, block.timestamp);
            } catch {
                // If borrow fails, try with smaller amount
                uint256 smallerAmount = perpetualLoanAmount / 10;
                try pool.borrow(
                    USDXL_RESERVE,
                    smallerAmount,
                    2, // Variable rate mode
                    0, // Referral code
                    address(this)
                ) {
                    perpetualLoanActive = true;
                    perpetualLoanDebt = smallerAmount;
                    emit PerpetualLoanCreated(smallerAmount, block.timestamp);
                } catch {
                    // If still fails, skip this execution
                    emit ExecutionSkipped(3, block.timestamp); // Reason 3: Borrow failed
                    return;
                }
            }
        } else {
            // Refresh perpetual loan by repaying and reborrowing
            uint256 currentDebt = _getCurrentDebt();
            if (currentDebt > 0) {
                // Repay current debt
                USDXL_TOKEN.approve(address(pool), currentDebt);
                try pool.repay(
                    USDXL_RESERVE,
                    currentDebt,
                    2, // Variable rate mode
                    address(this)
                ) {
                    // Reborrow the same amount
                    try pool.borrow(
                        USDXL_RESERVE,
                        currentDebt,
                        2, // Variable rate mode
                        0, // Referral code
                        address(this)
                    ) {
                        emit PerpetualLoanRefreshed(currentDebt, currentDebt, block.timestamp);
                    } catch {
                        // If reborrow fails, try with smaller amount
                        uint256 smallerAmount = currentDebt / 2;
                        try pool.borrow(
                            USDXL_RESERVE,
                            smallerAmount,
                            2, // Variable rate mode
                            0, // Referral code
                            address(this)
                        ) {
                            perpetualLoanDebt = smallerAmount;
                            emit PerpetualLoanRefreshed(smallerAmount, smallerAmount, block.timestamp);
                        } catch {
                            emit ExecutionSkipped(4, block.timestamp); // Reason 4: Reborrow failed
                        }
                    }
                } catch {
                    emit ExecutionSkipped(5, block.timestamp); // Reason 5: Repay failed
                }
            }
        }
    }

    /**
     * @dev Get current debt amount for this contract
     * @return The current debt amount
     */
    function _getCurrentDebt() internal view returns (uint256) {
        IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
        DataTypes.ReserveData memory reserveData = pool.getReserveData(USDXL_RESERVE);
        
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
                USDXL_RESERVE,
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
                USDXL_RESERVE,
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