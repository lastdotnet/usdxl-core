// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GPv2SafeERC20} from '@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IAToken} from '@aave/core-v3/contracts/interfaces/IAToken.sol';
import {WadRayMath} from '@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol';
import {IUsdxlToken} from '../../usdxl/interfaces/IUsdxlToken.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {ProxyAdmin} from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Gsm} from './Gsm.sol';
import {SafeERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IWeightedPool} from 'src/contracts/dependencies/balancer/interfaces/pool-weighted/IWeightedPool.sol';

/**
 * @title GsmWithHyFiPoolV2
 * @author Last Labs
 * @notice USDXL Stability Module with HyFi Pool integration. It provides buy/sell facilities to go to/from an underlying asset to/from USDXL.
 * @dev To be covered by a proxy contract. This implementation deposits underlying assets into HyFi pools for yield generation.
 * @dev This implementation allows for interest to be harvested and swapped to USDXL.
 */
contract GsmWithHyFiPoolV2 is Gsm {
  using GPv2SafeERC20 for IERC20;
  using SafeCast for uint256;
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;

  bytes32 public constant HARVESTER_ROLE = keccak256('HARVESTER_ROLE');

  // HyFi Pool integration
  IPool public immutable HYFI_POOL;
  IAToken public immutable HYTOKEN;
  IPoolAddressesProvider public immutable HYFI_ADDRESSES_PROVIDER;

  // Balancer Pool integration
  IWeightedPool public immutable BALANCER_POOL;

  // Track total deposited amount in HyFi Pool
  uint256 public totalDepositedInHyFiPool;

  event PoolDeposit(uint256 amount, uint256 hyTokenBalance);
  event PoolWithdraw(uint256 amount, uint256 hyTokenBalance);
  event InterestHarvested(address indexed admin, address indexed receiver, uint256 amount);
  event BuyHyAsset(address indexed originator, address indexed receiver, uint256 amount, uint256 ghoSold, uint256 fee);

  /**
   * @dev Constructor
   * @param usdxlToken The address of the GHO token contract
   * @param underlyingAsset The address of the collateral asset
   * @param priceStrategy The address of the price strategy
   * @param hyfiAddressesProvider The address of the HyFi addresses provider
   */
  constructor(
    address usdxlToken,
    address underlyingAsset,
    address priceStrategy,
    address hyfiAddressesProvider,
    address balancerPool
  ) Gsm(usdxlToken, underlyingAsset, priceStrategy) {
    require(hyfiAddressesProvider != address(0), 'ZERO_ADDRESS_NOT_VALID');
    require(balancerPool != address(0), 'ZERO_ADDRESS_NOT_VALID');

    HYFI_ADDRESSES_PROVIDER = IPoolAddressesProvider(hyfiAddressesProvider);
    HYFI_POOL = IPool(HYFI_ADDRESSES_PROVIDER.getPool());
    
    // Get the corresponding hyToken for the underlying asset
    HYTOKEN = IAToken(HYFI_POOL.getReserveData(underlyingAsset).aTokenAddress);

    BALANCER_POOL = IWeightedPool(balancerPool);
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
  ) public override initializer {
    if (_usdxlTreasury == address(0)) {
      super.initialize(admin, usdxlTreasury, exposureCap);
    } else {
      _migrateToHyFiPool();
    }
    _grantRole(HARVESTER_ROLE, admin);
  }

  /**
   * @notice Withdraw interest earned from HyFi Pool
   * @dev Only admin can withdraw interest
   */
  function harvestInterest() external onlyRole(HARVESTER_ROLE) {
    _harvestInterest(_usdxlTreasury);
  }

  function harvestInterestTo(address receiver) external onlyRole(HARVESTER_ROLE) {
    _harvestInterest(receiver);
  }

  function _harvestInterest(address receiver) internal {
    uint256 harvestAmount = getHarvestableUnderlyingBalance();
    require(harvestAmount > 0, 'NO_INTEREST_TO_HARVEST');

    // Withdraw from HyFi Pool
    HYFI_POOL.withdraw(UNDERLYING_ASSET, harvestAmount, address(this));

    // Transfer to receiver
    if (receiver != address(this)) {
      IERC20(UNDERLYING_ASSET).safeTransfer(receiver, harvestAmount);
    }
  }

  struct SwapParams {
    bytes swapData;
    address sellToken;
    address buyToken;
    uint256 maxAmountIn;
    uint256 minAmountOut;
  }

  function harvestAndSwap(address swapRouter, SwapParams[] calldata swapParams) external onlyRole(HARVESTER_ROLE) {
    _harvestInterest(address(this));

    for (uint256 i = 0; i < swapParams.length; i++) {
      (uint256 amountSold, uint256 amountBought) = _swapWithData(swapRouter, swapParams[i]);
      require(amountSold <= swapParams[i].maxAmountIn, 'INPUT_SLIPPAGE_EXCEEDED');
      require(amountBought >= swapParams[i].minAmountOut, 'OUTPUT_SLIPPAGE_EXCEEDED');
    }

    // LP into balancer pool

    // redeposit leftover underlying
    _migrateToHyFiPool();
  }

  function emergencyPoolDeposit() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 amount = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
    IERC20(UNDERLYING_ASSET).approve(address(HYFI_POOL), amount);
    HYFI_POOL.deposit(UNDERLYING_ASSET, amount, address(this), 0);
    totalDepositedInHyFiPool += amount;

    emit PoolDeposit(amount, HYTOKEN.balanceOf(address(this)));
  }

  function emergencyPoolWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    HYFI_POOL.withdraw(UNDERLYING_ASSET, totalDepositedInHyFiPool, address(this));
    totalDepositedInHyFiPool = 0;

    emit PoolWithdraw(totalDepositedInHyFiPool, HYTOKEN.balanceOf(address(this)));
  }

  /**
   * @notice Update the current exposure
   * @dev Sweeps in underlying tokens transferred directly to the GSM
   */
  function updateCurrentExposure() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _currentExposure = uint128(getTotalUnderlying());
  }

  function getHarvestableUnderlyingBalance() public view returns (uint256) {
    return HYTOKEN.balanceOf(address(this)) - totalDepositedInHyFiPool;
  }

  function getTotalUnderlying() public view returns (uint256) {
    return IERC20(UNDERLYING_ASSET).balanceOf(address(this)) + totalDepositedInHyFiPool;
  }

  function getAvailableUnderlying() public view returns (uint256) {
    return IERC20(UNDERLYING_ASSET).balanceOf(address(this)) + getHyFiPoolAvailableLiquidity();
  }

  function getAvailableUnderlyingViaHyAsset() public view returns (uint256) {
    return IERC20(address(HYTOKEN)).balanceOf(address(this));
  }

  /**
   * @notice Get the actual available liquidity in the hyToken contract for the underlying asset
   * @return The available liquidity in the hyToken contract
   */
  function getHyFiPoolAvailableLiquidity() public view returns (uint256) {
    uint256 underlyingHyTokenBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(HYTOKEN));
    if (underlyingHyTokenBalance >= totalDepositedInHyFiPool) {
      return totalDepositedInHyFiPool;
    } else {
      return underlyingHyTokenBalance;
    }
  }

  /// @inheritdoc Gsm
  function GSM_REVISION() public pure virtual override returns (uint256) {
    return 2; // Incremented for HyFi Pool integration
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
    IERC20(address(HYTOKEN)).safeTransfer(receiver, assetAmount);

    _afterBuyHyAsset(originator, assetAmount, receiver);
    
    emit BuyHyAsset(originator, receiver, assetAmount, ghoSold, fee);
    return (assetAmount, ghoSold);
  }

  function _beforeBuyHyAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal virtual{
    require(amount <= getAvailableUnderlyingViaHyAsset(), 'INSUFFICIENT_LIQUIDITY');
    totalDepositedInHyFiPool -= amount;
  }

  function _afterBuyHyAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal virtual {}

  /**
   * @dev Hook that is called before `buyAsset`.
   * @dev This implementation handles HyFi Pool withdrawal logic
   * @param amount The amount of the underlying asset desired for purchase
   */
  function _beforeBuyAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal override {    
    // Check available liquidity (including HyFi Pool deposits)
    require(amount <= getAvailableUnderlying(), 'INSUFFICIENT_LIQUIDITY');

    uint256 currentBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

    if (currentBalance < amount) {
      uint256 amountToWithdraw = amount - currentBalance;
      totalDepositedInHyFiPool -= amount;
      HYFI_POOL.withdraw(UNDERLYING_ASSET, amountToWithdraw, address(this));
    }    
  }

  /**
   * @dev Hook that is called after `sellAsset`.
   * @dev This implementation handles HyFi Pool deposit logic
   * @param amount The amount of the underlying asset desired to sell
   */
  function _afterSellAsset(address /*originator*/, uint256 amount, address /*receiver*/) internal override {
    // Deposit to HyFi Pool for yield generation
    IERC20(UNDERLYING_ASSET).approve(address(HYFI_POOL), amount);
    HYFI_POOL.deposit(UNDERLYING_ASSET, amount, address(this), 0);
    totalDepositedInHyFiPool += amount;
  }

  /**
   * @notice Migrate existing USDT0 balance to HyFi Pool
   * @dev This function should be called during the upgrade process
   */
  function _migrateToHyFiPool() internal {
    uint256 balance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
    if (balance == 0) {
      return;
    }

    // Approve HyFi pool to spend underlying asset
    IERC20(UNDERLYING_ASSET).approve(address(HYFI_POOL), balance);

    // Deposit into HyFi Pool
    HYFI_POOL.deposit(UNDERLYING_ASSET, balance, address(this), 0);

    totalDepositedInHyFiPool += balance;

    emit PoolDeposit(balance, HYTOKEN.balanceOf(address(this)));
  }

  struct SwapWithDataLocals {
    uint256 buyTokenBalanceBefore;
    uint256 sellTokenBalanceBefore;
    uint256 buyTokenBalanceAfter;
    uint256 sellTokenBalanceAfter;
  }

  /**
    * @dev Execute swap using swap router
    */
  function _swapWithData(
      address swapRouter,
      SwapParams calldata swapParams
  ) internal returns (uint256 amountSold, uint256 amountBought) {
      // Reset allowance to zero first, then approve the new amount
      IERC20(swapParams.sellToken).safeApprove(swapRouter, 0);
      IERC20(swapParams.sellToken).safeApprove(swapRouter, swapParams.maxAmountIn);

      SwapWithDataLocals memory locals;

      locals.buyTokenBalanceBefore = IERC20(swapParams.buyToken).balanceOf(address(this));
      locals.sellTokenBalanceBefore = IERC20(swapParams.sellToken).balanceOf(address(this));

      uint256 gasUsed = gasleft();

      // Execute swap on Gluex
      (bool success,) = swapRouter.call(swapParams.swapData);
      require(success, "SWAP_FAILED");

      gasUsed = gasUsed - gasleft();

      locals.buyTokenBalanceAfter = IERC20(swapParams.buyToken).balanceOf(address(this));
      locals.sellTokenBalanceAfter = IERC20(swapParams.sellToken).balanceOf(address(this));

      amountSold = locals.sellTokenBalanceBefore - locals.sellTokenBalanceAfter;
      amountBought = locals.buyTokenBalanceAfter - locals.buyTokenBalanceBefore;

      require(amountBought > 0, "NO_OUTPUT_AMOUNT_RECEIVED");

      // Revoke approval
      IERC20(swapParams.sellToken).safeApprove(swapRouter, 0);

      return (amountSold, amountBought);
  }
}
