// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GyroECLPPoolDynamicData, GyroECLPPoolImmutableData} from 'src/contracts/dependencies/balancer/interfaces/pool-gyro/IGyroECLPPool.sol';
import {IGsmStructs} from 'src/contracts/facilitators/gsm/interfaces/IGsmStructs.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {console2} from 'forge-std/console2.sol';
import {IGyroECLPPool} from 'src/contracts/dependencies/balancer/interfaces/pool-gyro/IGyroECLPPool.sol';
import {IWeightedPool, WeightedPoolDynamicData, WeightedPoolImmutableData} from 'src/contracts/dependencies/balancer/interfaces/pool-weighted/IWeightedPool.sol';

library BalancerLib {
  using SafeERC20 for IERC20;

  event NoLiquidityToAddProportional();
  event NoLiquidityToAddUnbalanced();
  event LiquidityAddedProportional(uint256 bptMinted, uint256[] amountsIn);
  event LiquidityAddedUnbalanced(uint256 bptMinted, uint256[] amountsIn);

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
    IGsmStructs.BalancerPoolData poolData;
    IERC20[] poolTokens;
    bool canProvideLiquidity;
    uint256[] amountsUsed;
  }

  /**
   * @dev Add liquidity to the Balancer pool, first proportionally then unbalanced
   * @param swapOutputs The swap outputs to add liquidity for
   */
  function addLiquidityToBalancerPool(IGsmStructs.SwapOutput[] memory swapOutputs, IGsmStructs.Constants memory constants) external {
    AddLiquidityToBalancerPoolLocals memory locals;

    // Get pool data to determine token order and ratios
    locals.poolData = _getBalancerPoolData(constants);
    locals.poolTokens = locals.poolData.tokens;

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
    _setupPermit2Approvals(swapOutputs, constants);

    console2.log('add liquidity proportional');

    // Step 1: Add liquidity proportionally if we have both tokens
    (locals.amountsUsed, locals.totalBptMinted) = 
      _addLiquidityProportional(
        swapOutputs,
        constants
      );
    
    if (locals.totalBptMinted > 0) {
      emit LiquidityAddedProportional(locals.totalBptMinted, locals.amountsUsed);
    } else {
      emit NoLiquidityToAddProportional();
      return;
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
      swapOutputs,
      constants
    );
    
    if (locals.totalBptMinted > 0) {
      emit LiquidityAddedUnbalanced(locals.totalBptMinted, locals.amountsUsed);
    } else {
      emit NoLiquidityToAddUnbalanced();
    }
  }

  function _setupPermit2Approvals(IGsmStructs.SwapOutput[] memory swapOutputs, IGsmStructs.Constants memory constants) internal {
    for (uint256 i = 0; i < swapOutputs.length; i++) {
      IERC20(swapOutputs[i].token).safeApprove(address(constants.permit2), 0);
      IERC20(swapOutputs[i].token).safeApprove(address(constants.permit2), swapOutputs[i].amountBought);
      constants.permit2.approve(swapOutputs[i].token, address(constants.balancerRouter), uint160(swapOutputs[i].amountBought), uint48(0));
    }
  }

  /**
   * @dev Add liquidity proportionally based on pool ratios
   */
  function _addLiquidityProportional(
    IGsmStructs.SwapOutput[] memory swapOutputs,
    IGsmStructs.Constants memory constants
  ) internal returns (uint256[] memory amountsIn, uint256 exactBptAmountOut) {
    amountsIn = new uint256[](swapOutputs.length);
    for (uint256 i = 0; i < swapOutputs.length; i++) {
      amountsIn[i] = swapOutputs[i].amountBought;
    }

    console2.log('amountsIn[i]:', amountsIn[0]);
    console2.log('calculate bpt amount out');

    exactBptAmountOut = _calculateBptAmountOut(amountsIn, constants);
    
    // Capture BPT balance before
    uint256 bptBalanceBefore = IERC20(address(constants.balancerPool)).balanceOf(address(this));

    // Try to add liquidity proportionally
    try constants.balancerRouter.addLiquidityProportional(
      address(constants.balancerPool),
      amountsIn,
      exactBptAmountOut, // exactBptAmountOut
      false, // wethIsEth
      "" // userData
    ) returns (uint256[] memory actualAmountsIn) {
      // Capture BPT balance after
      uint256 bptBalanceAfter = IERC20(address(constants.balancerPool)).balanceOf(address(this));
      exactBptAmountOut = bptBalanceAfter - bptBalanceBefore;
      return (actualAmountsIn, exactBptAmountOut);
    } catch {
      // If proportional fails, return 0
      console2.log('addLiquidityProportional failed');
      return (new uint256[](swapOutputs.length), 0);
    }
  }

  /**
   * @dev Add liquidity unbalanced with whatever tokens remain
   */
  function _addLiquidityUnbalanced(
    IGsmStructs.SwapOutput[] memory swapOutputs,
    IGsmStructs.Constants memory constants
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

    // Try to add liquidity unbalanced
    try constants.balancerRouter.addLiquidityUnbalanced(
      address(constants.balancerPool),
      amountsIn,
      0, // minBptAmountOut
      false, // wethIsEth
      "" // userData
    ) returns (uint256 bptAmountOut) {
      return bptAmountOut;
    } catch {
      // If unbalanced fails, return 0
      console2.log('addLiquidityUnbalanced failed');
      return 0;
    }
  }

  /**
   * @dev Add liquidity proportionally based on pool ratios
   */
  function addLiquidityProportional(
    IGsmStructs.SwapOutput[] memory swapOutputs,
    IGsmStructs.Constants memory constants
  ) external returns (uint256[] memory amountsIn, uint256 bptOut) {
    return _addLiquidityProportional(swapOutputs, constants);
  }

  struct CalculateSwapAmountsLocals {
    IGsmStructs.BalancerPoolData poolData;
    uint256 sumOfBalancesLiveScaled18;
    uint256 harvestAmount;
    bool underlyingInPool;
    IERC20[] poolTokens;
  }

  function calculateSwapAmounts(uint256 harvestAmount, uint256 harvestBalance, IGsmStructs.Constants memory constants) external view returns (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) {
    CalculateSwapAmountsLocals memory locals;

    locals.harvestAmount = harvestBalance;

    if (harvestAmount < locals.harvestAmount) {
      locals.harvestAmount = harvestAmount;
    }
    
    locals.poolData = _getBalancerPoolData(constants);

    tokenIn = constants.underlyingAsset;
    locals.poolTokens = locals.poolData.tokens;
    tokensOut = new address[](locals.poolTokens.length);
    amountsIn = new uint256[](locals.poolTokens.length);

    // Sum up live balances scaled to 18 decimals
    for (uint256 i = 0; i < tokensOut.length; i++) {
      tokensOut[i] = address(locals.poolTokens[i]);
      locals.sumOfBalancesLiveScaled18 += locals.poolData.balancesLiveScaled18[i];
      console2.log('balancesLiveScaled18[i]:', locals.poolData.balancesLiveScaled18[i]);
    }

    // Calculate amounts in based on pool ratios
    for (uint256 i = 0; i < tokensOut.length; i++) {
      amountsIn[i] = locals.harvestAmount * locals.poolData.balancesLiveScaled18[i] / locals.sumOfBalancesLiveScaled18;
    }

    // if amountsIn[i] is 0, set it to 10
    for (uint256 i = 0; i < tokensOut.length; i++) {
      if (amountsIn[i] == 0) {
        amountsIn[i] = 10;
        for (uint256 j = 0; j < tokensOut.length; j++) {
          if (j != i && amountsIn[j] > 10) {
            amountsIn[j] -= 10;
          }
        }
      }
    }

    return (tokenIn, tokensOut, amountsIn);
  }

  struct CalculateBptAmountOutLocals {
    IGsmStructs.BalancerPoolData balancerPoolData;
    uint256 bptTotalSupply;
    uint256 bptAmountOut;
  }

  function calculateBptAmountOut(uint256[] memory amountsIn, IGsmStructs.Constants memory constants) external view returns (uint256 minBptAmountOut) {
    return _calculateBptAmountOut(amountsIn, constants);
  }

  function _calculateBptAmountOut(uint256[] memory amountsIn, IGsmStructs.Constants memory constants) internal view returns (uint256 minBptAmountOut) {
    CalculateBptAmountOutLocals memory locals;

    minBptAmountOut = type(uint256).max;

    locals.balancerPoolData = _getBalancerPoolData(constants);
    locals.bptTotalSupply = locals.balancerPoolData.totalSupply;

    for (uint256 i = 0; i < amountsIn.length; i++) {
      if (amountsIn[i] == 0) {
        continue;
      }
      locals.bptAmountOut = amountsIn[i] * 10 ** (18 - IERC20Metadata(address(locals.balancerPoolData.tokens[i])).decimals()) 
                                  * locals.bptTotalSupply / locals.balancerPoolData.balancesLiveScaled18[i];
      if (locals.bptAmountOut < minBptAmountOut) {
        minBptAmountOut = locals.bptAmountOut;
      }
    }
    return minBptAmountOut;
  }

  function _getBalancerPoolData(IGsmStructs.Constants memory constants) internal view returns (IGsmStructs.BalancerPoolData memory balancerPoolData) {
    // Try IWeightedPool first
    try IWeightedPool(constants.balancerPool).getWeightedPoolImmutableData() returns (WeightedPoolImmutableData memory immutableData) {
      balancerPoolData.tokens = immutableData.tokens;
      balancerPoolData.balancesLiveScaled18 = IWeightedPool(constants.balancerPool).getWeightedPoolDynamicData().balancesLiveScaled18;
      balancerPoolData.totalSupply = IERC20(address(constants.balancerPool)).totalSupply();
      return balancerPoolData;
    } catch {
      // Try IGyroECLPPool
      try IGyroECLPPool(constants.balancerPool).getGyroECLPPoolImmutableData() returns (GyroECLPPoolImmutableData memory immutableData) {
        balancerPoolData.tokens = immutableData.tokens;
        balancerPoolData.balancesLiveScaled18 = IGyroECLPPool(constants.balancerPool).getGyroECLPPoolDynamicData().balancesLiveScaled18;
        balancerPoolData.totalSupply = IERC20(address(constants.balancerPool)).totalSupply();
        return balancerPoolData;
      } catch {
        revert("UNSUPPORTED_POOL_TYPE");
      }
    }
  }

  function isBalancerPool(address balancerPool) external view returns (bool) {
    return _isBalancerPool(balancerPool);
  }

  function _isBalancerPool(address balancerPool) internal view returns (bool) {
    // Check if address has nonzero bytecode
    uint256 size;
    assembly {
      size := extcodesize(balancerPool)
    }
    if (size == 0) {
      return false;
    }

    // Try IWeightedPool first
    try IWeightedPool(balancerPool).getWeightedPoolImmutableData() returns (WeightedPoolImmutableData memory) {
      return true;
    } catch {
      try IGyroECLPPool(balancerPool).getGyroECLPPoolImmutableData() returns (GyroECLPPoolImmutableData memory) {
        return true;
      } catch {
        return false;
      }
    }
  }
}