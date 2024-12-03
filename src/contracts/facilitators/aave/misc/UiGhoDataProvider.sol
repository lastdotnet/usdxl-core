// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IUsdxlToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {UsdxlDiscountRateStrategy} from '../interestStrategy/GhoDiscountRateStrategy.sol';
import {IUsdxlVariableDebtToken} from '../tokens/interfaces/IGhoVariableDebtToken.sol';
import {IUiUsdxlDataProvider} from './interfaces/IUiGhoDataProvider.sol';

/**
 * @title UiGhoDataProvider
 * @author Aave
 * @notice Data provider of USDXL token as a reserve within the Aave Protocol
 */
contract UiUsdxlDataProvider is IUiUsdxlDataProvider {
  IPool public immutable POOL;
  IUsdxlToken public immutable USDXL;

  /**
   * @dev Constructor
   * @param pool The address of the Pool contract
   * @param usdxlToken The address of the GhoToken contract
   */
  constructor(IPool pool, IUsdxlToken usdxlToken) {
    POOL = pool;
    USDXL = usdxlToken;
  }

  /// @inheritdoc IUiUsdxlDataProvider
  function getUsdxlReserveData() public view override returns (UsdxlReserveData memory) {
    DataTypes.ReserveDataLegacy memory baseData = POOL.getReserveData(address(USDXL));
    IUsdxlVariableDebtToken debtToken = IUsdxlVariableDebtToken(baseData.variableDebtTokenAddress);
    UsdxlDiscountRateStrategy discountRateStrategy = UsdxlDiscountRateStrategy(
      debtToken.getDiscountRateStrategy()
    );

    (uint256 bucketCapacity, uint256 bucketLevel) = USDXL.getFacilitatorBucket(
      baseData.aTokenAddress
    );

    return
      UsdxlReserveData({
        usdxlBaseVariableBorrowRate: baseData.currentVariableBorrowRate,
        usdxlDiscountedPerToken: discountRateStrategy.USDXL_DISCOUNTED_PER_DISCOUNT_TOKEN(),
        usdxlDiscountRate: discountRateStrategy.DISCOUNT_RATE(),
        usdxlMinDebtTokenBalanceForDiscount: discountRateStrategy.MIN_DEBT_TOKEN_BALANCE(),
        usdxlMinDiscountTokenBalanceForDiscount: discountRateStrategy.MIN_DISCOUNT_TOKEN_BALANCE(),
        usdxlReserveLastUpdateTimestamp: baseData.lastUpdateTimestamp,
        usdxlCurrentBorrowIndex: baseData.variableBorrowIndex,
        aaveFacilitatorBucketLevel: bucketLevel,
        aaveFacilitatorBucketMaxCapacity: bucketCapacity
      });
  }

  /// @inheritdoc IUiUsdxlDataProvider
  function getUsdxlUserData(address user) public view override returns (UsdxlUserData memory) {
    DataTypes.ReserveDataLegacy memory baseData = POOL.getReserveData(address(USDXL));
    IUsdxlVariableDebtToken debtToken = IUsdxlVariableDebtToken(baseData.variableDebtTokenAddress);
    address discountToken = debtToken.getDiscountToken();

    return
      UsdxlUserData({
        userUsdxlDiscountPercent: debtToken.getDiscountPercent(user),
        userDiscountTokenBalance: IERC20(discountToken).balanceOf(user),
        userPreviousUsdxlBorrowIndex: debtToken.getPreviousIndex(user),
        userUsdxlScaledBorrowBalance: debtToken.scaledBalanceOf(user)
      });
  }
}
