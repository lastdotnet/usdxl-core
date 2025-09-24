// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title WhalesTestBase
 * @notice Base contract for tests that need to transfer assets from whale addresses
 * @dev Provides utilities to transfer tokens from known whale addresses to test accounts
 */
abstract contract WhalesTestBase is Test {

    // Token addresses
    address constant WHYPE = 0x5555555555555555555555555555555555555555;
    address constant WSTHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address constant USDXL = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
    
    // Whale addresses
    address constant WHYPE_WHALE = 0x4c6452F18D5967F1f7e9884BC5cDFC60452E015A;
    address constant WSTHYPE_WHALE = 0x7ABcA40474D6B5F000f801d7FE7e0df4C89425fF;
    address constant USDT0_WHALE = 0x8cC81c5C09394CEaCa7a53be5f547AE719D75dFC;
    address constant USDXL_WHALE = 0x7911c2c9c5f5a6f4Bef58d7dF35903abd3EE9DD6;
    
    /**
     * @notice Transfer tokens from a whale address to a recipient
     * @param recipient The address to receive the tokens
     * @param amount The amount of tokens to transfer
     */
    function dealWhype(
        address recipient,
        uint256 amount
    ) internal {
        IERC20 tokenContract = IERC20(WHYPE);
        // Check whale has sufficient balance
        uint256 whaleBalance = tokenContract.balanceOf(WHYPE_WHALE);
        require(whaleBalance >= amount, "Whale has insufficient balance");
        
        // Impersonate whale and transfer tokens
        vm.startPrank(WHYPE_WHALE);
        IERC20(WHYPE).transfer(recipient, amount);
        vm.stopPrank();
        
        // Verify transfer was successful
        uint256 recipientBalance = tokenContract.balanceOf(recipient);
        require(recipientBalance >= amount, "Transfer failed");
    }

    function dealWstHype(
        address recipient,
        uint256 amount
    ) internal {
        IERC20 tokenContract = IERC20(WSTHYPE);
        uint256 whaleBalance = tokenContract.balanceOf(WSTHYPE_WHALE);
        require(whaleBalance >= amount, "Whale has insufficient balance");
        
        vm.startPrank(WSTHYPE_WHALE);
        IERC20(WSTHYPE).transfer(recipient, amount);
        vm.stopPrank();

        uint256 recipientBalance = tokenContract.balanceOf(recipient);
        require(recipientBalance >= amount, "Transfer failed");
    }

    function dealUsdt0(
        address recipient,
        uint256 amount
    ) internal {
        IERC20 tokenContract = IERC20(USDT0);
        uint256 whaleBalance = tokenContract.balanceOf(USDT0_WHALE);
        console2.log("Whale balance:", whaleBalance);
        console2.log("Amount:", amount);
        require(whaleBalance >= amount, "Whale has insufficient balance");
        
        vm.startPrank(USDT0_WHALE);
        IERC20(USDT0).transfer(recipient, amount);
        vm.stopPrank();

        uint256 recipientBalance = tokenContract.balanceOf(recipient);
        require(recipientBalance >= amount, "Transfer failed");
    }

    function dealUsdxl(
        address recipient,
        uint256 amount
    ) internal {
        IERC20 tokenContract = IERC20(USDXL);
        uint256 whaleBalance = tokenContract.balanceOf(USDXL_WHALE);
        require(whaleBalance >= amount, "Whale has insufficient balance");
        
        vm.startPrank(USDXL_WHALE);
        IERC20(USDXL).transfer(recipient, amount);
        vm.stopPrank();

        uint256 recipientBalance = tokenContract.balanceOf(recipient);
        require(recipientBalance >= amount, "Transfer failed");
    }
}
