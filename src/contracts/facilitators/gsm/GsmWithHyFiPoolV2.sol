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
  using Strings for uint256;

  bytes32 public constant HARVESTER_ROLE = keccak256('HARVESTER_ROLE');

  // HyFi Pool integration
  IPool public immutable HYFI_POOL;
  IAToken public immutable HYTOKEN;
  IPoolAddressesProvider public immutable HYFI_ADDRESSES_PROVIDER;
  IHyFiOracle public immutable HYFI_ORACLE;

  // Balancer Pool integration
  IRouter public immutable BALANCER_ROUTER;
  IPermit2 public immutable PERMIT2;

  // Track total deposited amount in HyFi Pool
  uint256 public totalDepositedInHyFiPool;
  
  // Mutable Balancer pool address (appended to end of storage for upgrade safety)
  IGyroECLPPool public BALANCER_POOL;

  event PoolDeposit(uint256 amount, uint256 hyTokenBalance);
  event PoolWithdraw(uint256 amount, uint256 hyTokenBalance);
  event InterestHarvested(address indexed admin, address indexed receiver, uint256 amount);
  event BuyHyAsset(address indexed originator, address indexed receiver, uint256 amount, uint256 ghoSold, uint256 fee);
  event NoLiquidityToAddProportional();
  event NoLiquidityToAddUnbalanced();
  event LiquidityAddedProportional(uint256 bptMinted, uint256[] amountsIn);
  event LiquidityAddedUnbalanced(uint256 bptMinted, uint256[] amountsIn);
  event BalancerPoolUpdated(address indexed oldPool, address indexed newPool);

  /**
   * @dev Constructor
   * @param usdxlToken The address of the GHO token contract
   * @param underlyingAsset The address of the collateral asset
   * @param priceStrategy The address of the price strategy
   * @param hyfiAddressesProvider The address of the HyFi addresses provider
   * @param balancerRouter The address of the Balancer router
   * @param permit2 The address of the Permit2 contract
   */
  constructor(
    address usdxlToken,
    address underlyingAsset,
    address priceStrategy,
    address hyfiAddressesProvider,
    address balancerRouter,
    address permit2
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
    address swapRouter;
    bytes swapData;
    address sellToken;
    address buyToken;
    uint256 maxAmountIn;
    uint256 minAmountOut;
  }

  struct SwapOutput {
    address token;
    uint256 amountSold;
    uint256 amountBought;
  }

  function harvestLiquidity(
    SwapParams[] calldata swapParams
  ) external onlyRole(HARVESTER_ROLE) {
    _harvestLiquidity(swapParams);
  }

  function calculateSwapAmounts() external view returns (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) {
    return _calculateSwapAmounts();
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
   * @notice Update the Balancer pool address
   * @dev Only admin can update the pool address
   * @param newBalancerPool The new Balancer pool address
   */
  function updateBalancerPool(address newBalancerPool) external onlyRole(HARVESTER_ROLE) {
    require(newBalancerPool != address(0), 'ZERO_ADDRESS_NOT_VALID');
    require(newBalancerPool != address(BALANCER_POOL), 'SAME_ADDRESS');
    
    address oldPool = address(BALANCER_POOL);
    BALANCER_POOL = IGyroECLPPool(newBalancerPool);
    
    emit BalancerPoolUpdated(oldPool, newBalancerPool);
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
      SwapParams calldata swapParams
  ) internal returns (uint256 amountSold, uint256 amountBought) {
      // Reset allowance to zero first, then approve the new amount
      IERC20(swapParams.sellToken).safeApprove(swapParams.swapRouter, 0);
      IERC20(swapParams.sellToken).safeApprove(swapParams.swapRouter, swapParams.maxAmountIn);

      SwapWithDataLocals memory locals;

      if (swapParams.swapData.length == 0) {
        amountSold = swapParams.maxAmountIn;
        amountBought = swapParams.minAmountOut;
        return (amountSold, amountBought);
      }

      locals.buyTokenBalanceBefore = IERC20(swapParams.buyToken).balanceOf(address(this));
      locals.sellTokenBalanceBefore = IERC20(swapParams.sellToken).balanceOf(address(this));

      uint256 gasUsed = gasleft();

      // Execute swap via router
      (bool success,) = swapParams.swapRouter.call(swapParams.swapData);
      require(success, "SWAP_FAILED");

      gasUsed = gasUsed - gasleft();

      locals.buyTokenBalanceAfter = IERC20(swapParams.buyToken).balanceOf(address(this));
      locals.sellTokenBalanceAfter = IERC20(swapParams.sellToken).balanceOf(address(this));

      amountSold = locals.sellTokenBalanceBefore - locals.sellTokenBalanceAfter;
      amountBought = locals.buyTokenBalanceAfter - locals.buyTokenBalanceBefore;

      require(amountBought > 0, "SWAP_CHECK_OUTPUT_RECEIVER");

      // Revoke approval
      IERC20(swapParams.sellToken).safeApprove(swapParams.swapRouter, 0);

      return (amountSold, amountBought);
  }

  //TODO: make it so harvestLiquidity cannot dip into underlying withdrawn from hyfi pool
  //TODO: consider if it makes sense to gate minBptOut for addLiquidityUnbalanced
  //TODO: make sure pool token order matches swapParams

  struct AddLiquidityToBalancerPoolLocals {
    uint256 usdxlBalance;
    uint256 underlyingBalance;
    uint256 usdxlIndex;
    uint256 underlyingIndex;
    uint256 totalBptMinted;
    uint256 totalUsdxlUsed;
    uint256 totalUnderlyingUsed;
    GyroECLPPoolDynamicData poolData;
    IERC20[] poolTokens;
    bool canProvideLiquidity;
    uint256[] amountsUsed;
  }

  function _harvestLiquidity(SwapParams[] calldata swapParams) internal {
    _harvestInterest(address(this));

    SwapOutput[] memory swapOutputs = new SwapOutput[](swapParams.length);

    for (uint256 i = 0; i < swapParams.length; i++) {
      (swapOutputs[i].amountSold, swapOutputs[i].amountBought) = _swapWithData(swapParams[i]);
      swapOutputs[i].token = swapParams[i].buyToken;
      require(swapOutputs[i].amountSold <= swapParams[i].maxAmountIn, 'INPUT_SLIPPAGE_EXCEEDED');
      require(swapOutputs[i].amountBought >= swapParams[i].minAmountOut, 'OUTPUT_SLIPPAGE_EXCEEDED');
    }

    // LP into balancer pool
    _addLiquidityToBalancerPool(swapOutputs);

    // redeposit leftover underlying
    _migrateToHyFiPool();
  }

  /**
   * @dev Add liquidity to the Balancer pool, first proportionally then unbalanced
   * @param swapOutputs The swap outputs to add liquidity for
   */
  function _addLiquidityToBalancerPool(SwapOutput[] memory swapOutputs) internal {
    AddLiquidityToBalancerPoolLocals memory locals;

    // Get pool data to determine token order and ratios
    locals.poolData = BALANCER_POOL.getGyroECLPPoolDynamicData();
    locals.poolTokens = BALANCER_POOL.getGyroECLPPoolImmutableData().tokens;

    // If we don't have any tokens to LP, return early
    for (uint256 i = 0; i < locals.poolTokens.length; i++) {
      if (IERC20(locals.poolTokens[i]).balanceOf(address(this)) > 0) {
        locals.canProvideLiquidity = true;
      }
    }

    if (!locals.canProvideLiquidity) {
      emit NoLiquidityToAddProportional();
      return;
    }

    // Setup approvals via Permit2
    _setupPermit2Approvals(swapOutputs);

    // Step 1: Add liquidity proportionally if we have both tokens
    (locals.amountsUsed, locals.totalBptMinted) = 
      _addLiquidityProportional(
        locals.poolTokens,
        locals.poolData,
        swapOutputs
      );
    
    if (locals.totalBptMinted > 0) {
      emit LiquidityAddedProportional(locals.totalBptMinted, locals.amountsUsed);
    } else {
      emit NoLiquidityToAddProportional();
    }

    // Step 2: Subtract the amounts used from the swap outputs
    for (uint256 i = 0; i < swapOutputs.length; i++) {
      if (locals.amountsUsed[i] <= swapOutputs[i].amountBought) {
        swapOutputs[i].amountBought -= locals.amountsUsed[i];
      } else {
        swapOutputs[i].amountBought = 0;
      }
    }

    // Step 3: Add remaining liquidity unbalanced
    locals.totalBptMinted = _addLiquidityUnbalanced(
      locals.poolTokens,
      swapOutputs
    );
    
    if (locals.totalBptMinted > 0) {
      emit LiquidityAddedUnbalanced(locals.totalBptMinted, locals.amountsUsed);
    }
  }

  function _setupPermit2Approvals(SwapOutput[] memory swapOutputs) internal {
    for (uint256 i = 0; i < swapOutputs.length; i++) {
      IERC20(swapOutputs[i].token).safeApprove(address(PERMIT2), 0);
      IERC20(swapOutputs[i].token).safeApprove(address(PERMIT2), swapOutputs[i].amountBought);
    }
  }

  /**
   * @dev Add liquidity proportionally based on pool ratios
   */
  function _addLiquidityProportional(
    IERC20[] memory poolTokens,
    GyroECLPPoolDynamicData memory poolData,
    SwapOutput[] memory swapOutputs
  ) internal returns (uint256[] memory amountsIn, uint256 exactBptAmountOut) {
    amountsIn = new uint256[](swapOutputs.length);
    for (uint256 i = 0; i < swapOutputs.length; i++) {
      amountsIn[i] = swapOutputs[i].amountBought;
    }

    // Add liquidity proportionally
    uint256[] memory actualAmountsIn = BALANCER_ROUTER.addLiquidityProportional(
      address(BALANCER_POOL),
      amountsIn,
      0,
      false, // wethIsEth
      "" // userData
    );

    return (actualAmountsIn, exactBptAmountOut);
  }

  /**
   * @dev Add liquidity unbalanced with whatever tokens remain
   */
  function _addLiquidityUnbalanced(
    IERC20[] memory poolTokens,
    SwapOutput[] memory swapOutputs
  ) internal returns (uint256 bptOut) {
    // Skip if no tokens to add
    if (swapOutputs.length == 0) {
      return 0;
    }

    // Prepare amounts array in pool token order
    uint256[] memory amountsIn = new uint256[](swapOutputs.length);
    for (uint256 i = 0; i < swapOutputs.length; i++) {
      amountsIn[i] = swapOutputs[i].amountBought;
    }

    // Add liquidity unbalanced (minBptOut = 0 since we already checked global minimum)
    bptOut = BALANCER_ROUTER.addLiquidityUnbalanced(
      address(BALANCER_POOL),
      amountsIn,
      0, // minBptAmountOut (we check total at the end)
      false, // wethIsEth
      "" // userData
    );
  }

  struct CalculateAmountsInLocals {
    GyroECLPPoolImmutableData immutableData;
    GyroECLPPoolDynamicData dynamicData;
    uint256 sumOfBalancesLiveScaled18;
    uint256 harvestAmount;
    bool underlyingInPool;
    IERC20[] poolTokens;
  }

  function _calculateSwapAmounts() internal returns (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) {
    CalculateAmountsInLocals memory locals;

    locals.harvestAmount = getHarvestableUnderlyingBalance();
    
    locals.dynamicData = BALANCER_POOL.getGyroECLPPoolDynamicData();
    locals.immutableData = BALANCER_POOL.getGyroECLPPoolImmutableData();

    tokenIn = UNDERLYING_ASSET;
    locals.poolTokens = locals.immutableData.tokens;
    tokensOut = new address[](locals.poolTokens.length);
    amountsIn = new uint256[](locals.poolTokens.length);

    // Sum up live balances scaled to 18 decimals
    for (uint256 i = 0; i < tokensOut.length; i++) {
      tokensOut[i] = address(locals.poolTokens[i]);
      locals.sumOfBalancesLiveScaled18 += locals.dynamicData.balancesLiveScaled18[i];
    }

    // Calculate amounts in based on pool ratios
    for (uint256 i = 0; i < tokensOut.length; i++) {
      amountsIn[i] = locals.harvestAmount * locals.dynamicData.balancesLiveScaled18[i] / locals.sumOfBalancesLiveScaled18;
    }

    return (tokenIn, tokensOut, amountsIn);
  }
}
