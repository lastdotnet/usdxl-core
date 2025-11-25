// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";

interface IGluexRouter {
    function swap(bytes calldata data) external payable returns (bytes memory);
}

/**
 * @title MockGluexRouter
 * @notice Mock router for testing swaps - shared between leverage and adapter tests
 * @author Last Labs
 */
contract MockGluexRouter {
    function swap(bytes calldata data) external payable returns (bytes memory) {
        // Parse the swap data to extract amounts and tokens
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) =
            abi.decode(data, (address, address, uint256, uint256));

        // Transfer tokens from caller to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Mint output tokens to caller (simulating a swap)
        // In a real scenario, this would be the actual swap logic
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        return abi.encode(amountOut);
    }

    /**
     * @dev Fallback function that handles all calls to the router
     * @param data The calldata containing swap parameters
     */
    fallback(bytes calldata data) external payable returns (bytes memory) {
        require(data.length >= 128, "MockGluexRouter: Insufficient calldata");

        // Parse the calldata
        address sellToken = address(uint160(uint256(bytes32(data[0:32]))));
        address buyToken = address(uint160(uint256(bytes32(data[32:64]))));
        uint256 sellAmount = uint256(bytes32(data[64:96]));
        uint256 buyAmount = uint256(bytes32(data[96:128]));

        // Transfer sellToken from caller to this contract (simulating the swap)
        if (sellAmount > 0) {
            if (sellToken == address(0)) {
                revert("MockGluexRouter: ETH not supported");
            } else {
                IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
            }
        }

        // Transfer buyToken from this contract to caller (simulating the swap result)
        if (buyAmount > 0) {
            // For ETH, we can use vm.deal to increase the balance
            if (buyToken == address(0)) {
                revert("MockGluexRouter: ETH not supported");
            } else {
                IERC20(buyToken).transfer(msg.sender, buyAmount);
            }
        }

        return abi.encode(buyAmount);
    }

    /**
     * @dev Standard Uniswap V2 style swap function for compatibility
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256, /* amountOutMin */
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    )
        external
        returns (uint256[] memory amounts)
    {
        // Simple 1:1 swap simulation
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // For testing purposes, we need to mint output tokens to maintain router balance
        // This simulates the router having infinite liquidity
        // Try to mint tokens to this contract first, then transfer
        (bool success,) = path[1].call(abi.encodeWithSignature("mint(address,uint256)", address(this), amountIn));
        if (success) {
            IERC20(path[1]).transfer(to, amountIn);
        } else {
            // Fallback: try direct transfer (for real tokens)
            IERC20(path[1]).transfer(to, amountIn);
        }

        uint256[] memory result = new uint256[](2);
        result[0] = amountIn;
        result[1] = amountIn;
        return result;
    }

    /**
     * @dev Function to mint tokens for testing purposes
     */
    function mintTokensTo(address token, address to, uint256 amount) external {
        // This is a mock function for testing - in reality, only token contracts can mint
        // For testing purposes, we'll transfer from this contract's balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance >= amount) {
            IERC20(token).transfer(to, amount);
        } else {
            // If we don't have enough, transfer what we have
            IERC20(token).transfer(to, balance);
        }
    }

    /**
     * @notice Encode Gluex swap calldata for MockGluexRouter
     * @param sellToken Token to sell
     * @param buyToken Token to buy
     * @param sellAmount Amount to sell
     * @param buyAmount Amount to buy
     * @return Encoded calldata
     */
    function encodeGluexCalldata(address sellToken, address buyToken, uint256 sellAmount, uint256 buyAmount)
        external
        view
        returns (bytes memory)
    {
        console2.log('sellToken:', sellToken);
        return abi.encode(
            sellToken, // First 32 bytes: sellToken address
            buyToken, // Next 32 bytes: buyToken address
            sellAmount, // Next 32 bytes: sellAmount
            buyAmount // Next 32 bytes: buyAmount
        );
    }

    /**
     * @dev Receive function to handle ETH transfers
     */
    receive() external payable {
        // Accept ETH transfers
    }
}
