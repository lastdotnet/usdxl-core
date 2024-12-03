// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';

import {UiUsdxlDataProvider, IUiUsdxlDataProvider} from '../contracts/facilitators/aave/misc/UiGhoDataProvider.sol';

contract TestUiGhoDataProvider is TestGhoBase {
  UiUsdxlDataProvider dataProvider;

  function setUp() public {
    dataProvider = new UiUsdxlDataProvider(IPool(POOL), GHO_TOKEN);
  }

  function testGhoReserveData() public {
    DataTypes.ReserveDataLegacy memory baseData = POOL.getReserveData(address(GHO_TOKEN));
    (uint256 bucketCapacity, uint256 bucketLevel) = GHO_TOKEN.getFacilitatorBucket(
      baseData.aTokenAddress
    );
    IUiUsdxlDataProvider.UsdxlReserveData memory result = dataProvider.getUsdxlReserveData();
    assertEq(
      result.usdxlBaseVariableBorrowRate,
      baseData.currentVariableBorrowRate,
      'Unexpected variable borrow rate'
    );
    assertEq(
      result.usdxlDiscountedPerToken,
      GHO_DISCOUNT_STRATEGY.USDXL_DISCOUNTED_PER_DISCOUNT_TOKEN(),
      'Unexpected discount per token'
    );
    assertEq(
      result.usdxlDiscountRate,
      GHO_DISCOUNT_STRATEGY.DISCOUNT_RATE(),
      'Unexpected discount rate'
    );
    assertEq(
      result.usdxlMinDiscountTokenBalanceForDiscount,
      GHO_DISCOUNT_STRATEGY.MIN_DISCOUNT_TOKEN_BALANCE(),
      'Unexpected minimum discount token balance'
    );
    assertEq(
      result.usdxlMinDebtTokenBalanceForDiscount,
      GHO_DISCOUNT_STRATEGY.MIN_DEBT_TOKEN_BALANCE(),
      'Unexpected minimum debt token balance'
    );
    assertEq(
      result.usdxlReserveLastUpdateTimestamp,
      baseData.lastUpdateTimestamp,
      'Unexpected last timestamp'
    );
    assertEq(
      result.usdxlCurrentBorrowIndex,
      baseData.variableBorrowIndex,
      'Unexpected borrow index'
    );
    assertEq(result.aaveFacilitatorBucketLevel, bucketLevel, 'Unexpected facilitator bucket level');
    assertEq(
      result.aaveFacilitatorBucketMaxCapacity,
      bucketCapacity,
      'Unexpected facilitator bucket capacity'
    );
  }

  function testGhoUserData() public {
    IUiUsdxlDataProvider.UsdxlUserData memory result = dataProvider.getUsdxlUserData(ALICE);
    assertEq(
      result.userUsdxlDiscountPercent,
      GHO_DEBT_TOKEN.getDiscountPercent(ALICE),
      'Unexpected discount percent'
    );
    assertEq(
      result.userDiscountTokenBalance,
      IERC20(GHO_DEBT_TOKEN.getDiscountToken()).balanceOf(ALICE),
      'Unexpected discount token balance'
    );
    assertEq(
      result.userPreviousUsdxlBorrowIndex,
      GHO_DEBT_TOKEN.getPreviousIndex(ALICE),
      'Unexpected previous index'
    );
    assertEq(
      result.userUsdxlScaledBorrowBalance,
      GHO_DEBT_TOKEN.scaledBalanceOf(ALICE),
      'Unexpected scaled balance'
    );
  }
}
