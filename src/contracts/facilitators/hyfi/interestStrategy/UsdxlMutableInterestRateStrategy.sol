// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IDefaultInterestRateStrategy} from '@aave/core-v3/contracts/interfaces/IDefaultInterestRateStrategy.sol';
import {IReserveInterestRateStrategy} from '@aave/core-v3/contracts/interfaces/IReserveInterestRateStrategy.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title UsdxlMutableInterestRateStrategy
 * @author Aave
 * @notice Implements the calculation of USDXL interest rates with mutable variable borrow rate.
 * @dev The variable borrow interest rate can be updated by the owner. The rest of parameters are zeroed.
 */
contract UsdxlMutableInterestRateStrategy is IDefaultInterestRateStrategy, Ownable {
  /// @inheritdoc IDefaultInterestRateStrategy
  uint256 public constant OPTIMAL_USAGE_RATIO = 0;

  /// @inheritdoc IDefaultInterestRateStrategy
  uint256 public constant OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO = 0;

  /// @inheritdoc IDefaultInterestRateStrategy
  uint256 public constant MAX_EXCESS_USAGE_RATIO = 0;

  /// @inheritdoc IDefaultInterestRateStrategy
  uint256 public constant MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO = 0;

  /// @inheritdoc IDefaultInterestRateStrategy
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

  // Base variable borrow rate when usage rate = 0. Expressed in ray
  uint256 internal _baseVariableBorrowRate;

  // Events
  event InterestRateUpdated(uint256 oldRate, uint256 newRate, uint256 timestamp);

  /**
   * @dev Constructor
   * @param addressesProvider The address of the PoolAddressesProvider
   * @param borrowRate The variable borrow rate (expressed in ray)
   * @param owner The owner of the contract who can update rates
   */
  constructor(address addressesProvider, uint256 borrowRate, address owner) {
    ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
    _baseVariableBorrowRate = borrowRate;
    _transferOwnership(owner);
  }

  /**
   * @notice Update the base variable borrow rate
   * @param newRate The new variable borrow rate (expressed in ray)
   * @dev Only callable by owner
   */
  function updateBaseVariableBorrowRate(uint256 newRate) external onlyOwner {
    uint256 oldRate = _baseVariableBorrowRate;
    _baseVariableBorrowRate = newRate;
    emit InterestRateUpdated(oldRate, newRate, block.timestamp);
  }

  function getVariableRateSlope1() external pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getVariableRateSlope2() external pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getStableRateSlope1() external pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getStableRateSlope2() external pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getStableRateExcessOffset() external pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getBaseStableBorrowRate() public pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getBaseVariableBorrowRate() external view override returns (uint256) {
    return _baseVariableBorrowRate;
  }

  /// @inheritdoc IDefaultInterestRateStrategy
  function getMaxVariableBorrowRate() external view override returns (uint256) {
    return _baseVariableBorrowRate;
  }

  /// @inheritdoc IReserveInterestRateStrategy
  function calculateInterestRates(
    DataTypes.CalculateInterestRatesParams memory
  ) public view override returns (uint256, uint256, uint256) {
    return (0, 0, _baseVariableBorrowRate);
  }

  function setInterestRateParams(address reserve, bytes calldata rateData) external {}
} 