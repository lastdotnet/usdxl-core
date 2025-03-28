// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {WadRayMath} from '@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol';
import {IUsdxlDiscountRateStrategy} from './interfaces/IUsdxlDiscountRateStrategy.sol';

/**
 * @title GhoDiscountRateStrategy contract
 * @author Aave
 * @notice Implements the calculation of the discount rate depending on the current strategy
 */
contract UsdxlDiscountRateStrategy is IUsdxlDiscountRateStrategy {
  using WadRayMath for uint256;

  /**
   * @dev Amount of debt that is entitled to get a discount per unit of discount token
   * Expressed with the number of decimals of the discounted token
   */
  uint256 public constant USDXL_DISCOUNTED_PER_DISCOUNT_TOKEN = 100e18;

  /**
   * @dev Percentage of discount to apply to the part of the debt that is entitled to get a discount
   * Expressed in bps, a value of 3000 results in 30.00%
   */
  uint256 public constant DISCOUNT_RATE = 0.3e4;

  /**
   * @dev Minimum balance amount of discount token to be entitled to a discount
   * Expressed with the number of decimals of the discount token
   */
  uint256 public constant MIN_DISCOUNT_TOKEN_BALANCE = 1e15;

  /**
   * @dev Minimum balance amount of debt token to be entitled to a discount
   * Expressed with the number of decimals of the debt token
   */
  uint256 public constant MIN_DEBT_TOKEN_BALANCE = 1e18;

  /// @inheritdoc IUsdxlDiscountRateStrategy
  function calculateDiscountRate(
    uint256 debtBalance,
    uint256 discountTokenBalance
  ) external pure override returns (uint256) {
    if (discountTokenBalance < MIN_DISCOUNT_TOKEN_BALANCE || debtBalance < MIN_DEBT_TOKEN_BALANCE) {
      return 0;
    } else {
      uint256 discountedBalance = discountTokenBalance.wadMul(USDXL_DISCOUNTED_PER_DISCOUNT_TOKEN);
      if (discountedBalance >= debtBalance) {
        return DISCOUNT_RATE;
      } else {
        return (discountedBalance * DISCOUNT_RATE) / debtBalance;
      }
    }
  }
}
