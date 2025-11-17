// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

/**
 * @notice Interface for Uniswap's Permit2 contract
 * @dev Simplified interface for approval functionality
 */
interface IPermit2 {
    /**
     * @notice Approve a spender to transfer tokens
     * @param token The token to approve
     * @param spender The address to approve
     * @param amount The amount to approve (uint160 max)
     * @param expiration The expiration timestamp (uint48 max)
     */
    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external;
}

