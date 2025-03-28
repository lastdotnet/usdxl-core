// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IUsdxlDiscountRateStrategy} from '../interestStrategy/interfaces/IUsdxlDiscountRateStrategy.sol';

/**
 * @title ZeroDiscountRateStrategy
 * @author Aave
 * @notice Discount Rate Strategy that always return zero discount rate.
 */
contract ZeroDiscountRateStrategy is IUsdxlDiscountRateStrategy {
  /// @inheritdoc IUsdxlDiscountRateStrategy
  function calculateDiscountRate(
    uint256 debtBalance,
    uint256 discountTokenBalance
  ) external view override returns (uint256) {
    return 0;
  }
}
