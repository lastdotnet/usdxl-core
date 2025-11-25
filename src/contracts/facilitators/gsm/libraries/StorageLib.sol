// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGsmStructs} from 'src/contracts/facilitators/gsm/interfaces/IGsmStructs.sol';
import {SafeERC20, IERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {BalancerLib} from 'src/contracts/facilitators/gsm/libraries/BalancerLib.sol';

library StorageLib {
  using SafeERC20 for IERC20;

  event PoolDeposit(uint256 amount, uint256 hyTokenBalance);
  event BalancerPoolUpdated(address indexed oldPool, address indexed newPool);
 
  function updateBalancerPool(IGsmStructs.StorageValues storage storageValues, address newBalancerPool) external {
    require(storageValues.balancerPool == address(0) || newBalancerPool != storageValues.balancerPool, 'SAME_POOL_ADDRESS');

    if (newBalancerPool != address(0)) {
      require(BalancerLib.isBalancerPool(newBalancerPool), 'INVALID_BALANCER_POOL');
    }
    
    address oldPool = storageValues.balancerPool;
    storageValues.balancerPool = newBalancerPool;
    
    emit BalancerPoolUpdated(oldPool, newBalancerPool);
  }

    function rescueTokens(address[] memory tokens, address to) external {
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

    function emergencyPoolDeposit(IGsmStructs.StorageValues storage storageValues, IGsmStructs.Constants memory constants) external {
      uint256 amount = IERC20(constants.underlyingAsset).balanceOf(address(this));
      _deposit(constants, amount);
      storageValues.totalDepositedInHyFiPool += amount;

      emit PoolDeposit(amount, IERC20(constants.hyToken).balanceOf(address(this)));
    }

    function migrateToHyFiPool(IGsmStructs.StorageValues storage storageValues, IGsmStructs.Constants memory constants) external {
      uint256 balance = IERC20(constants.underlyingAsset).balanceOf(address(this));
      if (balance == 0) {
      return;
      }

      // Approve HyFi pool to spend underlying asset
      IERC20(constants.underlyingAsset).approve(constants.hyfiPool, balance);

      // Deposit into HyFi Pool
      _deposit(constants, balance);

      storageValues.totalDepositedInHyFiPool += balance;

      emit PoolDeposit(balance, IERC20(constants.hyToken).balanceOf(address(this)));
    }

    function deposit(IGsmStructs.Constants memory constants, uint256 amount) external {
      _deposit(constants, amount);
    }

    function _deposit(IGsmStructs.Constants memory constants, uint256 amount) private {
      IERC20(constants.underlyingAsset).safeApprove(constants.hyfiPool, 0);
      IERC20(constants.underlyingAsset).safeApprove(constants.hyfiPool, amount);
      IPool(constants.hyfiPool).deposit(constants.underlyingAsset, amount, address(this), 0);
    }

    function withdraw(IGsmStructs.Constants memory constants, uint256 amount) external {
      _withdraw(constants.hyfiPool, constants.underlyingAsset, amount);
    }

    function _withdraw(address hyfiPool, address underlyingAsset, uint256 amount) private {
      IPool(hyfiPool).withdraw(underlyingAsset, amount, address(this));
    }
}