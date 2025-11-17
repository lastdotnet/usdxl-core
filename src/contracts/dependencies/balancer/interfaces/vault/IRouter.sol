// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

/**
 * @notice Interface for the Balancer V3 Router contract
 * @dev Based on Balancer V3 pool operation examples
 */
interface IRouter {
    /**
     * @notice Add liquidity to a pool with unbalanced token amounts
     * @param pool Address of the pool
     * @param amountsIn Exact amounts of tokens to add
     * @param minBptAmountOut Minimum amount of BPT to receive
     * @param wethIsEth Whether to use native ETH for WETH
     * @param userData Additional user data
     * @return bptAmountOut Amount of BPT minted
     */
    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory amountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Add liquidity to a pool proportionally
     * @param pool Address of the pool
     * @param maxAmountsIn Maximum amounts of tokens to add
     * @param exactBptAmountOut Exact amount of BPT to mint
     * @param wethIsEth Whether to use native ETH for WETH
     * @param userData Additional user data
     * @return amountsIn Actual amounts of tokens added
     */
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn);
}

