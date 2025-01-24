// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title IUiGhoDataProvider
 * @author Aave
 * @notice Defines the basic interface of the UiGhoDataProvider
 */
interface IUiUsdxlDataProvider {
  struct UsdxlReserveData {
    uint256 usdxlBaseVariableBorrowRate;
    uint256 usdxlDiscountedPerToken;
    uint256 usdxlDiscountRate;
    uint256 usdxlMinDebtTokenBalanceForDiscount;
    uint256 usdxlMinDiscountTokenBalanceForDiscount;
    uint40 usdxlReserveLastUpdateTimestamp;
    uint128 usdxlCurrentBorrowIndex;
    uint256 aaveFacilitatorBucketLevel;
    uint256 aaveFacilitatorBucketMaxCapacity;
  }

  struct UsdxlUserData {
    uint256 userUsdxlDiscountPercent;
    uint256 userDiscountTokenBalance;
    uint256 userPreviousUsdxlBorrowIndex;
    uint256 userUsdxlScaledBorrowBalance;
  }

  /**
   * @notice Returns data of the GHO reserve and the Aave Facilitator
   * @return An object with information related to the GHO reserve and the Aave Facilitator
   */
  function getUsdxlReserveData() external view returns (UsdxlReserveData memory);

  /**
   * @notice Returns data of the user's position on GHO
   * @return An object with information related to the user's position with regard to GHO
   */
  function getUsdxlUserData(address user) external view returns (UsdxlUserData memory);
}
