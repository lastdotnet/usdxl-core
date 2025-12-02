// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import {PercentageMath} from '@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol';
import {IGsmFeeStrategy} from './interfaces/IGsmFeeStrategy.sol';

/**
 * @title NoBuyFixedFeeStrategy
 * @author Last Labs
 * @notice Fee strategy using a fixed rate to calculate buy/sell fees
 */
contract NoBuyFixedFeeStrategy is IGsmFeeStrategy {
  using Math for uint256;

  uint256 internal immutable _buyFee;
  uint256 internal immutable _sellFee;

  constructor() {
    _buyFee = 1e4;
    _sellFee = 0;
  }

  /// @inheritdoc IGsmFeeStrategy
  function getBuyFee(uint256 grossAmount) external view returns (uint256) {
    return grossAmount.mulDiv(_buyFee, PercentageMath.PERCENTAGE_FACTOR, Math.Rounding.Up);
  }

  /// @inheritdoc IGsmFeeStrategy
  function getSellFee(uint256 grossAmount) external view returns (uint256) {
    return grossAmount.mulDiv(_sellFee, PercentageMath.PERCENTAGE_FACTOR, Math.Rounding.Up);
  }

  /// @inheritdoc IGsmFeeStrategy
  function getGrossAmountFromTotalBought(uint256 totalAmount) external view returns (uint256) {
    if (totalAmount == 0) {
      return 0;
    } else if (_buyFee == 0) {
      return totalAmount;
    } else {
      return
        totalAmount.mulDiv(
          PercentageMath.PERCENTAGE_FACTOR,
          PercentageMath.PERCENTAGE_FACTOR + _buyFee,
          Math.Rounding.Down
        );
    }
  }

  /// @inheritdoc IGsmFeeStrategy
  function getGrossAmountFromTotalSold(uint256 totalAmount) external view returns (uint256) {
    if (totalAmount == 0) {
      return 0;
    } else if (_sellFee == 0) {
      return totalAmount;
    } else {
      return
        totalAmount.mulDiv(
          PercentageMath.PERCENTAGE_FACTOR,
          PercentageMath.PERCENTAGE_FACTOR - _sellFee,
          Math.Rounding.Up
        );
    }
  }
}
