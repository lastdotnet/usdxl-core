// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {GPv2SafeERC20} from '@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IAToken} from '@aave/core-v3/contracts/interfaces/IAToken.sol';
import {WadRayMath} from '@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol';
import {IUsdxlToken} from '../../usdxl/interfaces/IUsdxlToken.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Gsm} from './Gsm.sol';

/**
 * @title GsmWithAaveV3
 * @author Aave
 * @notice GHO Stability Module with Aave V3 integration. It provides buy/sell facilities to go to/from an underlying asset to/from GHO.
 * @dev To be covered by a proxy contract. This implementation deposits underlying assets into Aave V3 pools for yield generation.
 */
contract GsmWithAaveV3 is Gsm {
  using GPv2SafeERC20 for IERC20;
  using SafeCast for uint256;
  using WadRayMath for uint256;
  
  // Aave V3 integration
  IPool public immutable AAVE_POOL;
  IAToken public immutable ATOKEN;
  IPoolAddressesProvider public immutable AAVE_ADDRESSES_PROVIDER;

  // Track total deposited amount in Aave V3
  uint256 public totalDepositedInAave;

  event PoolDeposit(uint256 amount, uint256 aTokenBalance);
  event PoolWithdraw(uint256 amount, uint256 aTokenBalance);
  event InterestHarvested(address indexed admin, uint256 amount);
  event BuyHyAsset(address indexed originator, address indexed receiver, uint256 amount, uint256 ghoSold, uint256 fee);

  /**
   * @dev Constructor
   * @param usdxlToken The address of the GHO token contract
   * @param underlyingAsset The address of the collateral asset
   * @param priceStrategy The address of the price strategy
   * @param aaveAddressesProvider The address of the Aave V3 addresses provider
   */
  constructor(
    address usdxlToken,
    address underlyingAsset,
    address priceStrategy,
    address aaveAddressesProvider
  ) Gsm(usdxlToken, underlyingAsset, priceStrategy) {
    require(aaveAddressesProvider != address(0), 'ZERO_ADDRESS_NOT_VALID');

    AAVE_ADDRESSES_PROVIDER = IPoolAddressesProvider(aaveAddressesProvider);
    AAVE_POOL = IPool(AAVE_ADDRESSES_PROVIDER.getPool());
    
    // Get the corresponding aToken for the underlying asset
    ATOKEN = IAToken(AAVE_POOL.getReserveData(underlyingAsset).aTokenAddress);
  }

  /**
   * @notice GSM initializer
   * @param admin The address of the default admin role
   * @param usdxlTreasury The address of the GHO treasury
   * @param exposureCap Maximum amount of user-supplied underlying asset in GSM
   */
  function initialize(
    address admin,
    address usdxlTreasury,
    uint128 exposureCap
  ) external override initializer {
    _initialize(admin, usdxlTreasury, exposureCap);
    
    // Migrate existing balance to Aave V3
    _migrateToAaveV3();
  }

  /**
   * @notice Withdraw interest earned from Aave V3
   * @dev Only admin can withdraw interest
   */
  function harvestInterest() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 harvestAmount = getHarvestableUnderlyingBalance();
    require(harvestAmount > 0, 'NO_INTEREST_TO_HARVEST');

    // Withdraw from Aave V3
    AAVE_POOL.withdraw(UNDERLYING_ASSET, harvestAmount, address(this));

    // Transfer to admin
    IERC20(UNDERLYING_ASSET).safeTransfer(msg.sender, harvestAmount);

    emit InterestHarvested(msg.sender, harvestAmount);
  }

  function emergencyPoolDeposit() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 amount = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
    IERC20(UNDERLYING_ASSET).approve(address(AAVE_POOL), amount);
    AAVE_POOL.deposit(UNDERLYING_ASSET, amount, address(this), 0);
    totalDepositedInAave += amount;

    emit PoolDeposit(amount, ATOKEN.balanceOf(address(this)));
  }

  function emergencyPoolWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    AAVE_POOL.withdraw(UNDERLYING_ASSET, totalDepositedInAave, address(this));
    totalDepositedInAave = 0;

    emit PoolWithdraw(totalDepositedInAave, ATOKEN.balanceOf(address(this)));
  }

  function updateCurrentExposure() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _currentExposure = uint128(getTotalUnderlying());
  }

  function getHarvestableUnderlyingBalance() public view returns (uint256) {
    return ATOKEN.balanceOf(address(this)) - totalDepositedInAave;
  }

  function getTotalUnderlying() public view returns (uint256) {
    return IERC20(UNDERLYING_ASSET).balanceOf(address(this)) + totalDepositedInAave;
  }

  function getAvailableUnderlying() public view returns (uint256) {
    return IERC20(UNDERLYING_ASSET).balanceOf(address(this)) + getAavePoolAvailableLiquidity();
  }

  function getAvailableUnderlyingViaHyAsset() public view returns (uint256) {
    return IERC20(ATOKEN).balanceOf(address(this));
  }

  /**
   * @notice Get the actual available liquidity in the aToken contract for the underlying asset
   * @return The available liquidity in the aToken contract
   */
  function getAavePoolAvailableLiquidity() public view returns (uint256) {
    uint256 underlyingATokenBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(ATOKEN));
    if (underlyingATokenBalance >= totalDepositedInAave) {
      return totalDepositedInAave;
    } else {
      return underlyingATokenBalance;
    }
  }

  /**
   * @notice Convert underlying asset amount to equivalent aToken amount
   * @param underlyingAmount The amount of underlying asset
   * @return The equivalent aToken amount
   */
  function underlyingToATokenAmount(uint256 underlyingAmount) public view returns (uint256) {
    uint256 liquidityIndex = AAVE_POOL.getReserveNormalizedIncome(UNDERLYING_ASSET);
    return underlyingAmount.rayDiv(liquidityIndex);
  }

  /// @inheritdoc Gsm
  function GSM_REVISION() public pure virtual override returns (uint256) {
    return 2; // Incremented for Aave V3 integration
  }

  function getBuyLiquidity() public view returns (uint256 underlying, uint256 underlyingViaHyAsset) {
    return (getAvailableUnderlying(), getAvailableUnderlyingViaHyAsset());
  }

  function buyHyAsset(
    uint256 minAmount,
    address receiver
  ) external notFrozen notSeized returns (uint256, uint256) {
    return _buyHyAsset(msg.sender, minAmount, receiver);
  }

  /**
   * @dev Emergency function to rescue stuck tokens
   * @param tokens The tokens to rescue
   * @param to The address to send the tokens to
  */
  function rescueTokens(address[] memory tokens, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
      require(to != address(0), 'INVALID_TO');
      
      for (uint256 i = 0; i < tokens.length; i++) {
        address token = tokens[i];
        if (token == address(0)) {
          uint256 balance = address(this).balance;
          if (balance > 0) {
              (bool success, ) = to.call{value: balance}('');
              require(success, 'ETH_TRANSFER_FAILED');
          }
        } else {
          uint256 balance = IERC20(token).balanceOf(address(this));
          if (balance > 0) {
              IERC20(token).safeTransfer(to, balance);
          }
        }
      }
  }

  function _buyHyAsset(
    address originator,
    uint256 minAmount,
    address receiver
  ) internal returns (uint256, uint256) {
    (
      uint256 assetAmount,
      uint256 ghoSold,
      uint256 grossAmount,
      uint256 fee
    ) = _calculateGhoAmountForBuyAsset(minAmount);

    _beforeBuyHyAsset(originator, assetAmount, receiver);

    require(assetAmount > 0, 'INVALID_AMOUNT');
    require(_currentExposure >= assetAmount, 'INSUFFICIENT_AVAILABLE_EXOGENOUS_ASSET_LIQUIDITY');

    _currentExposure -= uint128(assetAmount);
    _accruedFees += fee.toUint128();
    IUsdxlToken(USDXL_TOKEN).transferFrom(originator, address(this), ghoSold);
    IUsdxlToken(USDXL_TOKEN).burn(grossAmount);
    IERC20(ATOKEN).safeTransfer(receiver, underlyingToATokenAmount(assetAmount));

    emit BuyHyAsset(originator, receiver, assetAmount, ghoSold, fee);
    return (assetAmount, ghoSold);
  }

  function _beforeBuyHyAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal {
    require(amount <= getAvailableUnderlyingViaHyAsset(), 'INSUFFICIENT_LIQUIDITY');
    totalDepositedInAave -= amount;
  }

  /**
   * @dev Hook that is called before `buyAsset`.
   * @dev This implementation handles Aave V3 withdrawal logic
   * @param amount The amount of the underlying asset desired for purchase
   */
  function _beforeBuyAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal override {    
    // Check available liquidity (including Aave V3 deposits)
    require(amount <= getAvailableUnderlying(), 'INSUFFICIENT_LIQUIDITY');

    uint256 currentBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

    uint256 currentWithdrawableBalance = getAavePoolAvailableLiquidity();

    if (currentBalance < amount) {
      uint256 amountToWithdraw = amount - currentBalance;
      totalDepositedInAave -= amount;
      AAVE_POOL.withdraw(UNDERLYING_ASSET, amountToWithdraw, address(this));
    }    
  }

  /**
   * @dev Hook that is called before `sellAsset`.
   * @dev This implementation handles Aave V3 deposit logic
   * @param amount The amount of the underlying asset desired to sell
   */
  function _beforeSellAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal override {
    // Deposit to Aave V3 for yield generation
    IERC20(UNDERLYING_ASSET).approve(address(AAVE_POOL), amount);
    AAVE_POOL.deposit(UNDERLYING_ASSET, amount, address(this), 0);
    totalDepositedInAave += amount;
  }

  /**
   * @notice Migrate existing USDT0 balance to Aave V3
   * @dev This function should be called during the upgrade process
   */
  function _migrateToAaveV3() internal {
    uint256 balance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
    require(balance > 0, 'NO_BALANCE_TO_MIGRATE');

    // Approve Aave pool to spend underlying asset
    IERC20(UNDERLYING_ASSET).approve(address(AAVE_POOL), balance);

    // Deposit into Aave V3
    AAVE_POOL.deposit(UNDERLYING_ASSET, balance, address(this), 0);

    totalDepositedInAave += balance;

    emit PoolDeposit(balance, ATOKEN.balanceOf(address(this)));
  }
}
