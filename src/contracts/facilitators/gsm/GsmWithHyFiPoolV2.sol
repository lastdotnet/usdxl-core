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
import {IGyroECLPPool, GyroECLPPoolImmutableData, GyroECLPPoolDynamicData} from 'src/contracts/dependencies/balancer/interfaces/pool-gyro/IGyroECLPPool.sol';
import {IRouter} from 'src/contracts/dependencies/balancer/interfaces/vault/IRouter.sol';
import {IPermit2} from 'src/contracts/dependencies/permit2/IPermit2.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {IHyFiOracle} from '@hypurrfi/core/contracts/interfaces/IHyFiOracle.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IGsmStructs} from 'src/contracts/facilitators/gsm/interfaces/IGsmStructs.sol';
import {BalancerLib} from 'src/contracts/facilitators/gsm/libraries/BalancerLib.sol';
import {GluexLib} from 'src/contracts/facilitators/gsm/libraries/GluexLib.sol';
import {StorageLib} from 'src/contracts/facilitators/gsm/libraries/StorageLib.sol';

/**
 * @title GsmWithHyFiPoolV2
 * @author Last Labs
 * @notice USDXL Stability Module with HyFi Pool integration. It provides buy/sell facilities to go to/from an underlying asset to/from USDXL.
 * @dev To be covered by a proxy contract. This implementation deposits underlying assets into HyFi pools for yield generation.
 * @dev This implementation allows for interest to be harvested and swapped to USDXL.
 */
contract GsmWithHyFiPoolV2 is Gsm, IGsmStructs {
  using GPv2SafeERC20 for IERC20;
  using SafeCast for uint256;
  using WadRayMath for uint256;
  using SafeERC20 for IERC20;
  using Strings for uint256;

  bytes32 public constant HARVESTER_ROLE = keccak256('HARVESTER_ROLE');

  // HyFi Pool integration
  IPool public immutable HYFI_POOL;
  IAToken public immutable HYTOKEN;
  IPoolAddressesProvider public immutable HYFI_ADDRESSES_PROVIDER;
  IHyFiOracle public immutable HYFI_ORACLE;

  // Balancer integration
  IRouter public immutable BALANCER_ROUTER;
  IPermit2 public immutable PERMIT2;
  address public immutable GLUEX_ROUTER;

  /// @notice Deprecated storage variable
  uint256 public totalDepositedInHyFiPool;

  // Mutable Balancer Pool - can be updated by admin
  StorageValues public storageValues;

  event PoolDeposit(uint256 amount, uint256 hyTokenBalance);
  event PoolWithdraw(uint256 amount, uint256 hyTokenBalance);
  event InterestHarvested(address indexed admin, address indexed receiver, uint256 amount);
  event BuyHyAsset(address indexed originator, address indexed receiver, uint256 amount, uint256 ghoSold, uint256 fee);
  event HarvestDonated(address indexed donor, uint256 amount);
  event BalancerPoolUpdated(address indexed oldPool, address indexed newPool);

  modifier onlyValidPool() {
    require(storageValues.balancerPool != address(0), 'INVALID_POOL');
    _;
  }

  /**
   * @dev Constructor
   * @param usdxlToken The address of the USDXL token contract
   * @param underlyingAsset The address of the collateral asset
   * @param priceStrategy The address of the price strategy
   * @param hyfiAddressesProvider The address of the HyFi addresses provider
   * @param balancerRouter The address of the Balancer router
   * @param permit2 The address of the Permit2 contract
   * @param gluexRouter The address of the GlueX router
   */
  constructor(
    address usdxlToken,
    address underlyingAsset,
    address priceStrategy,
    address hyfiAddressesProvider,
    address balancerRouter,
    address permit2,
    address gluexRouter
  ) Gsm(usdxlToken, underlyingAsset, priceStrategy) {
    require(hyfiAddressesProvider != address(0), 'ZERO_ADDRESS_NOT_VALID');
    require(balancerRouter != address(0), 'ZERO_ADDRESS_NOT_VALID');
    require(permit2 != address(0), 'ZERO_ADDRESS_NOT_VALID');

    HYFI_ADDRESSES_PROVIDER = IPoolAddressesProvider(hyfiAddressesProvider);
    HYFI_POOL = IPool(HYFI_ADDRESSES_PROVIDER.getPool());
    HYFI_ORACLE = IHyFiOracle(HYFI_ADDRESSES_PROVIDER.getPriceOracle());
    
    // Get the corresponding hyToken for the underlying asset
    HYTOKEN = IAToken(HYFI_POOL.getReserveData(underlyingAsset).aTokenAddress);

    BALANCER_ROUTER = IRouter(balancerRouter);
    PERMIT2 = IPermit2(permit2);
    GLUEX_ROUTER = address(gluexRouter);
  }

  /**
   * @notice GSM initializer
   * @param admin The address of the default admin role
   * @param usdxlTreasury The address of the USDXL treasury
   * @param exposureCap Maximum amount of user-supplied underlying asset in GSM
   * @param balancerPool The address of the Balancer pool
   */
  function initializeWithPool(
    address admin,
    address usdxlTreasury,
    uint128 exposureCap,
    address balancerPool
  ) public initializer {    
    if (_usdxlTreasury == address(0)) {
      super.initialize(admin, usdxlTreasury, exposureCap);
    } else {
      StorageLib.migrateToHyFiPool(storageValues, _getConstants());
    }
    if (storageValues.totalDepositedInHyFiPool == 0) {
      storageValues.totalDepositedInHyFiPool = totalDepositedInHyFiPool;
    }
    StorageLib.updateBalancerPool(storageValues, balancerPool);
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

  function _harvestInterest(address receiver) internal returns (uint256 harvestAmount) {
    harvestAmount = getHarvestableUnderlyingBalance();
    require(harvestAmount > 0, 'NO_INTEREST_TO_HARVEST');

    // Withdraw from HyFi Pool
    StorageLib.withdraw(_getConstants(), harvestAmount);

    // Transfer to receiver
    if (receiver != address(this)) {
      IERC20(UNDERLYING_ASSET).safeTransfer(receiver, harvestAmount);
    }

    return harvestAmount;
  }

  function harvestLiquidity(
    SwapParams[] calldata swapParams
  ) external onlyRole(HARVESTER_ROLE) onlyValidPool {
    _harvestLiquidity(swapParams);
  }

  function harvestDonate(uint256 amount) external {
    require(amount > 0, 'INVALID_AMOUNT');
    
    // transfer donation to GSM
    IERC20(UNDERLYING_ASSET).safeTransferFrom(msg.sender, address(this), amount);

    // deposit to HyFi Pool
    StorageLib.deposit(_getConstants(), amount);

    emit HarvestDonated(msg.sender, amount);
  }

  function calculateSwapAmounts(uint256 harvestAmount) external view onlyValidPool returns (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) {
    return BalancerLib.calculateSwapAmounts(harvestAmount, getHarvestableUnderlyingBalance(), _getConstants());
  }

  function calculateBptAmountOut(uint256[] memory amountsIn) external view onlyValidPool returns (uint256 minBptAmountOut) {
    return BalancerLib.calculateBptAmountOut(amountsIn, _getConstants());
  }

  function getTotalDepositedInHyFiPool() external view returns (uint256) {
    return storageValues.totalDepositedInHyFiPool;
  }

  function getBalancerPool() external view returns (address) {
    return storageValues.balancerPool;
  }

  function emergencyPoolDeposit() external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 amount = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
    StorageLib.deposit(_getConstants(), amount);
    storageValues.totalDepositedInHyFiPool += amount;

    emit PoolDeposit(amount, HYTOKEN.balanceOf(address(this)));
  }

  function emergencyPoolWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    StorageLib.withdraw(_getConstants(), storageValues.totalDepositedInHyFiPool);
    storageValues.totalDepositedInHyFiPool = 0;

    emit PoolWithdraw(storageValues.totalDepositedInHyFiPool, HYTOKEN.balanceOf(address(this)));
  }

  /**
   * @notice Update the current exposure
   * @dev Sweeps in underlying tokens transferred directly to the GSM
   */
  function updateCurrentExposure() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _currentExposure = uint128(getTotalUnderlying());
  }

  /**
   * @notice Update the Balancer pool address
   * @dev Only admin can update the pool
   * @param newBalancerPool The new Balancer pool address
   */
  function updateBalancerPool(address newBalancerPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    StorageLib.updateBalancerPool(storageValues, newBalancerPool);
  }

  function getHarvestableUnderlyingBalance() public view returns (uint256) {
    return HYTOKEN.balanceOf(address(this)) - storageValues.totalDepositedInHyFiPool;
  }

  function getTotalUnderlying() public view returns (uint256) {
    return IERC20(UNDERLYING_ASSET).balanceOf(address(this)) + storageValues.totalDepositedInHyFiPool;
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
    if (underlyingHyTokenBalance >= storageValues.totalDepositedInHyFiPool) {
      return storageValues.totalDepositedInHyFiPool;
    } else {
      return underlyingHyTokenBalance;
    }
  }

  /// @inheritdoc Gsm
  function GSM_REVISION() public pure virtual override returns (uint256) {
    return 3; // Incremented for Balancer Pool integration
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
    StorageLib.rescueTokens(tokens, to);
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
    storageValues.totalDepositedInHyFiPool -= amount;
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
      storageValues.totalDepositedInHyFiPool -= amount;
      StorageLib.withdraw(_getConstants(), amountToWithdraw);
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
    storageValues.totalDepositedInHyFiPool += amount;
  }

  /**
   * @notice Migrate existing USDT0 balance to HyFi Pool
   * @dev This function should be called during the upgrade process
   */
  function _migrateToHyFiPool(IGsmStructs.Constants memory constants) internal {
    uint256 balance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
    if (balance == 0) {
      return;
    }

    // Approve HyFi pool to spend underlying asset
    IERC20(constants.underlyingAsset).approve(constants.hyfiPool, balance);

    // Deposit into HyFi Pool
    StorageLib.deposit(constants, balance);

    storageValues.totalDepositedInHyFiPool += balance;

    emit PoolDeposit(balance, HYTOKEN.balanceOf(address(this)));
  }

  function _harvestLiquidity(SwapParams[] calldata swapParams) internal {
    uint256 harvestAmount = _harvestInterest(address(this));

    IGsmStructs.SwapOutput[] memory swapOutputs = new IGsmStructs.SwapOutput[](swapParams.length);

    for (uint256 i = 0; i < swapParams.length; i++) {
      (swapOutputs[i].amountSold, swapOutputs[i].amountBought) = GluexLib.swapWithData(swapParams[i], _getConstants());
      require(swapOutputs[i].amountSold <= swapParams[i].maxAmountIn 
              && swapOutputs[i].amountSold <= harvestAmount, 'INPUT_SLIPPAGE_EXCEEDED');
      harvestAmount -= swapOutputs[i].amountSold;
      swapOutputs[i].token = swapParams[i].buyToken;
      require(swapOutputs[i].amountBought >= swapParams[i].minAmountOut, 'OUTPUT_SLIPPAGE_EXCEEDED');
    }

    // LP into balancer pool
    BalancerLib.addLiquidityToBalancerPool(swapOutputs, _getConstants());

    // redeposit leftover underlying
    StorageLib.deposit(_getConstants(), harvestAmount);
  }

  function _getConstants() private view returns (Constants memory) {
    return Constants({
      balancerRouter: BALANCER_ROUTER,
      balancerPool: storageValues.balancerPool,
      permit2: PERMIT2,
      gluexRouter: GLUEX_ROUTER,
      underlyingAsset: UNDERLYING_ASSET,
      hyfiPool: address(HYFI_POOL),
      hyToken: address(HYTOKEN)
    });
  }
}
