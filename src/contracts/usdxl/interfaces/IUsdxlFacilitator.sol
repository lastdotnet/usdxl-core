// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IGhoFacilitator
 * @author Aave
 * @notice Defines the behavior of a Usdxl Facilitator
 */
interface IUsdxlFacilitator {
  /**
   * @dev Emitted when fees are distributed to the GhoTreasury
   * @param usdxlTreasury The address of the ghoTreasury
   * @param asset The address of the asset transferred to the ghoTreasury
   * @param amount The amount of the asset transferred to the ghoTreasury
   */
  event FeesDistributedToTreasury(
    address indexed usdxlTreasury,
    address indexed asset,
    uint256 amount
  );

  /**
   * @dev Emitted when Gho Treasury address is updated
   * @param oldUsdxlTreasury The address of the old GhoTreasury contract
   * @param newUsdxlTreasury The address of the new GhoTreasury contract
   */
  event UsdxlTreasuryUpdated(address indexed oldUsdxlTreasury, address indexed newUsdxlTreasury);

  /**
   * @notice Distribute fees to the GhoTreasury
   */
  function distributeFeesToTreasury() external;

  /**
   * @notice Updates the address of the Gho Treasury
   * @dev WARNING: The GhoTreasury is where revenue fees are sent to. Update carefully
   * @param newUsdxlTreasury The address of the GhoTreasury
   */
  function updateUsdxlTreasury(address newUsdxlTreasury) external;

  /**
   * @notice Returns the address of the Gho Treasury
   * @return The address of the GhoTreasury contract
   */
  function getUsdxlTreasury() external view returns (address);
}
