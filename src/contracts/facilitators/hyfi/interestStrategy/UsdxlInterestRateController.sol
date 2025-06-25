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
import {console2 as console} from 'forge-std/console2.sol';
/**
 * @title UsdxlInterestRateController
 * @author Last Labs
 * @notice Controller for USDXL interest rates based on price deviation from peg
 * @dev Runs 3 times per day, maintains perpetual loan to ensure rate updates, 
 *      adjusts rates based on USDXL price relative to $1 peg
 */
contract UsdxlInterestRateController is UsdxlMutableInterestRateStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant EXECUTION_INTERVAL = 8 hours; // 3 times per day
    uint256 public constant PERPETUAL_LOAN_AMOUNT = 1000e18; // 1000 USDXL perpetual loan

    // Configurable parameters (can be updated by owner)
    uint256 public minRate = 0.06e27; // 6% minimum rate (in ray)
    uint256 public rateAdjustment = 0.0015e27; // 0.15% adjustment (in ray)
    uint256 public priceThreshold = 0.995e8; // 0.995 threshold for rate adjustments
    uint256 public targetPrice = 1e8; // $1 target price (8 decimals)

    // State variables
    IUsdxlToken public immutable USDXL_TOKEN;
    address public immutable USDXL_ORACLE;
    address public immutable USDXL_RESERVE;
    
    uint256 public lastExecutionTime;
    uint256 public currentRate;
    bool public perpetualLoanActive;
    uint256 public perpetualLoanDebt;

    // Events
    event RateUpdated(uint256 oldRate, uint256 newRate, uint256 usdxlPrice, uint256 timestamp);
    event PerpetualLoanCreated(uint256 amount, uint256 timestamp);
    event PerpetualLoanRefreshed(uint256 amount, uint256 timestamp);
    event ExecutionSkipped(uint256 reason, uint256 timestamp);
    event PriceDataEmitted(uint256 offchainPrice, uint256 onchainPrice, uint256 timestamp);
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

    // Errors
    error ExecutionTooEarly();
    error InvalidOraclePrice();
    error PerpetualLoanFailed();
    error RateUpdateFailed();
    error InvalidParameter();

    /**
     * @dev Constructor
     * @param addressesProvider The Aave V3 Pool Addresses Provider
     * @param usdxlToken The USDXL token address
     * @param usdxlOracle The USDXL oracle address
     * @param usdxlReserve The USDXL reserve address in the pool
     * @param initialRate The initial interest rate (in ray)
     */
    constructor(
        address addressesProvider,
        address usdxlToken,
        address usdxlOracle,
        address usdxlReserve,
        uint256 initialRate
    ) UsdxlMutableInterestRateStrategy(addressesProvider, initialRate, address(this)) {
        require(usdxlToken != address(0), "Invalid USDXL token");
        require(usdxlOracle != address(0), "Invalid USDXL oracle");
        require(usdxlReserve != address(0), "Invalid USDXL reserve");
        require(initialRate >= minRate, "Rate below minimum");

        USDXL_TOKEN = IUsdxlToken(usdxlToken);
        USDXL_ORACLE = usdxlOracle;
        USDXL_RESERVE = usdxlReserve;
        currentRate = initialRate;
        lastExecutionTime = block.timestamp;
    }

    /**
     * @notice Update configurable parameters
     * @param newMinRate The new minimum rate (in ray)
     * @param newRateAdjustment The new rate adjustment amount (in ray)
     * @param newPriceThreshold The new price threshold (8 decimals)
     * @param newTargetPrice The new target price (8 decimals)
     * @dev Only callable by owner
     */
    function updateParameters(
        uint256 newMinRate,
        uint256 newRateAdjustment,
        uint256 newPriceThreshold,
        uint256 newTargetPrice
    ) external onlyOwner {
        // Validate parameters
        require(newMinRate > 0, "Min rate must be positive");
        require(newRateAdjustment > 0, "Rate adjustment must be positive");
        require(newPriceThreshold > 0, "Price threshold must be positive");
        require(newTargetPrice > 0, "Target price must be positive");
        require(newPriceThreshold <= newTargetPrice, "Threshold cannot exceed target");
        
        // Ensure current rate doesn't go below new minimum
        if (currentRate < newMinRate) {
            revert("Current rate below new minimum");
        }

        // Store old values for event
        uint256 oldMinRate = minRate;
        uint256 oldRateAdjustment = rateAdjustment;
        uint256 oldPriceThreshold = priceThreshold;
        uint256 oldTargetPrice = targetPrice;

        // Update parameters
        minRate = newMinRate;
        rateAdjustment = newRateAdjustment;
        priceThreshold = newPriceThreshold;
        targetPrice = newTargetPrice;

        emit ParametersUpdated(
            oldMinRate, newMinRate,
            oldRateAdjustment, newRateAdjustment,
            oldPriceThreshold, newPriceThreshold,
            oldTargetPrice, newTargetPrice,
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

        uint256 oldMinRate = minRate;
        minRate = newMinRate;

        emit ParametersUpdated(
            oldMinRate, newMinRate,
            rateAdjustment, rateAdjustment,
            priceThreshold, priceThreshold,
            targetPrice, targetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Update rate adjustment only
     * @param newRateAdjustment The new rate adjustment amount (in ray)
     * @dev Only callable by owner
     */
    function updateRateAdjustment(uint256 newRateAdjustment) external onlyOwner {
        require(newRateAdjustment > 0, "Rate adjustment must be positive");

        uint256 oldRateAdjustment = rateAdjustment;
        rateAdjustment = newRateAdjustment;

        emit ParametersUpdated(
            minRate, minRate,
            oldRateAdjustment, newRateAdjustment,
            priceThreshold, priceThreshold,
            targetPrice, targetPrice,
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

        uint256 oldPriceThreshold = priceThreshold;
        priceThreshold = newPriceThreshold;

        emit ParametersUpdated(
            minRate, minRate,
            rateAdjustment, rateAdjustment,
            oldPriceThreshold, newPriceThreshold,
            targetPrice, targetPrice,
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

        uint256 oldTargetPrice = targetPrice;
        targetPrice = newTargetPrice;

        emit ParametersUpdated(
            minRate, minRate,
            rateAdjustment, rateAdjustment,
            priceThreshold, priceThreshold,
            oldTargetPrice, newTargetPrice,
            block.timestamp
        );
    }

    /**
     * @notice Execute rate control logic
     * @dev Can be called by anyone, but only executes if enough time has passed
     * @param offchainPrice Optional offchain-calculated USDXL price (8 decimals)
     */
    function execute(int256 offchainPrice) external nonReentrant {
        // Check if enough time has passed since last execution
        if (block.timestamp < lastExecutionTime + EXECUTION_INTERVAL) {
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
        return lastExecutionTime + EXECUTION_INTERVAL;
    }

    /**
     * @notice Check if execution is due
     * @return True if enough time has passed since last execution
     */
    function isExecutionDue() external view returns (bool) {
        return block.timestamp >= lastExecutionTime + EXECUTION_INTERVAL;
    }

    /**
     * @notice Get all current parameters
     * @return minRate_ The current minimum rate
     * @return rateAdjustment_ The current rate adjustment
     * @return priceThreshold_ The current price threshold
     * @return targetPrice_ The current target price
     */
    function getParameters() external view returns (
        uint256 minRate_,
        uint256 rateAdjustment_,
        uint256 priceThreshold_,
        uint256 targetPrice_
    ) {
        return (minRate, rateAdjustment, priceThreshold, targetPrice);
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
        (bool success, bytes memory data) = USDXL_ORACLE.staticcall(
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
            newRate = currentRate + rateAdjustment;
        } else if (usdxlPrice >= priceThreshold && currentRate > minRate) {
            // USDXL price at or above threshold and current rate above minimum, decrease rate
            newRate = currentRate - rateAdjustment;
            
            // Ensure rate doesn't go below minimum
            if (newRate < minRate) {
                newRate = minRate;
            }
        }
        // If price >= threshold and rate is already at minimum, no change (newRate remains currentRate)

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
                PERPETUAL_LOAN_AMOUNT,
                2, // Variable rate mode
                0, // Referral code
                address(this)
            ) {
                perpetualLoanActive = true;
                perpetualLoanDebt = PERPETUAL_LOAN_AMOUNT;
                emit PerpetualLoanCreated(PERPETUAL_LOAN_AMOUNT, block.timestamp);
            } catch {
                // If borrow fails, try with smaller amount
                uint256 smallerAmount = PERPETUAL_LOAN_AMOUNT / 10;
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
                        emit PerpetualLoanRefreshed(currentDebt, block.timestamp);
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
                            emit PerpetualLoanRefreshed(smallerAmount, block.timestamp);
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
        console.log("getPerpetualLoanStatus called. Current debt:", _getCurrentDebt());
        return (perpetualLoanActive, _getCurrentDebt());
    }

    /**
     * @notice Emergency function to repay all debt and deactivate perpetual loan
     * @dev Only callable by owner
     */
    function emergencyRepayAll() external onlyOwner {
        // For debugging: log current debt
        // slither-disable-next-line unused-import
        // solhint-disable-next-line no-console
        console.log("emergencyRepayAll called. Current debt:", _getCurrentDebt());

        uint256 currentDebt = _getCurrentDebt();
        if (currentDebt > 0) {
            IPool pool = IPool(ADDRESSES_PROVIDER.getPool());
            // For debugging: log approve
            console.log("Approving USDXL_TOKEN for pool:", address(pool), "amount:", currentDebt);
            USDXL_TOKEN.approve(address(pool), currentDebt);
            
            try pool.repay(
                USDXL_RESERVE,
                currentDebt,
                2, // Variable rate mode
                address(this)
            ) {
                // For debugging: log successful repay
                console.log("Repay successful. Debt repaid:", currentDebt);
                perpetualLoanActive = false;
                perpetualLoanDebt = 0;
            } catch {
                // For debugging: log failed repay
                console.log("Repay failed for debt:", currentDebt);
                revert("Repay failed");
            }
        } else {
            // For debugging: log no debt to repay
            console.log("No debt to repay in emergencyRepayAll");
        }
    }

    /**
     * @notice Get the current interest rate from the strategy
     * @return The current interest rate (in ray)
     */
    function getCurrentInterestRate() external view returns (uint256) {
        return _baseVariableBorrowRate;
    }
} 