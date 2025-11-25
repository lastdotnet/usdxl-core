// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGsmStructs} from 'src/contracts/facilitators/gsm/interfaces/IGsmStructs.sol';
import {SafeERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

library GluexLib {
  using SafeERC20 for IERC20;

  function swapWithData(IGsmStructs.SwapParams calldata swapParams, IGsmStructs.Constants memory constants) external returns (uint256 amountSold, uint256 amountBought) {
    return _swapWithData(swapParams, constants);
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
      IGsmStructs.SwapParams calldata swapParams,
      IGsmStructs.Constants memory constants
  ) internal returns (uint256 amountSold, uint256 amountBought) {
      // Reset allowance to zero first, then approve the new amount
      IERC20(swapParams.sellToken).safeApprove(constants.gluexRouter, 0);
      IERC20(swapParams.sellToken).safeApprove(constants.gluexRouter, swapParams.maxAmountIn);

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
      (bool success,) = constants.gluexRouter.call(swapParams.swapData);
      require(success, "SWAP_FAILED");

      gasUsed = gasUsed - gasleft();

      locals.buyTokenBalanceAfter = IERC20(swapParams.buyToken).balanceOf(address(this));
      locals.sellTokenBalanceAfter = IERC20(swapParams.sellToken).balanceOf(address(this));

      amountSold = locals.sellTokenBalanceBefore - locals.sellTokenBalanceAfter;
      amountBought = locals.buyTokenBalanceAfter - locals.buyTokenBalanceBefore;

      require(amountBought > 0, "SWAP_CHECK_OUTPUT_RECEIVER");

      // Revoke approval
      IERC20(swapParams.sellToken).safeApprove(constants.gluexRouter, 0);

      return (amountSold, amountBought);
  }
}