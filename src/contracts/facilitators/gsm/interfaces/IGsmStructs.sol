// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRouter} from 'src/contracts/dependencies/balancer/interfaces/vault/IRouter.sol';
import {IGyroECLPPool} from 'src/contracts/dependencies/balancer/interfaces/pool-gyro/IGyroECLPPool.sol';
import {IPermit2} from 'src/contracts/dependencies/permit2/IPermit2.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IGsmStructs {
  struct StorageValues {
    address balancerPool;
    uint256 totalDepositedInHyFiPool;
  }

  struct SwapParams {
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

  struct Constants {
    IRouter balancerRouter;
    address balancerPool;
    IPermit2 permit2;
    address gluexRouter;
    address underlyingAsset;
    address hyfiPool;
    address hyToken;
  }

  struct BalancerPoolData {
    IERC20[] tokens;
    uint256[] balancesLiveScaled18;
    uint256 totalSupply;
  }
}