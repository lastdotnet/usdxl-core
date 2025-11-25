// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";

/**
 * @title WhalesTestBase
 * @notice Base contract for test utilities that transfer tokens from whale addresses to users
 * @dev Provides functionality to fund test users with tokens by transferring from known whale addresses
 */
abstract contract WhalesTestBase is Test {
    // Mapping of token addresses to their known whale addresses
    mapping(address => address) public tokenWhales;

    // Common whale addresses used across tests
    address constant WSTHYPE_WHALE = 0x7ABcA40474D6B5F000f801d7FE7e0df4C89425fF;
    address constant USDT_WHALE = 0xAF4BF7Bd1Cd226741B3B5beE3C8027CEfd3d9345;
    address constant USDXL_WHALE = 0x7911c2c9c5f5a6f4Bef58d7dF35903abd3EE9DD6;
    address constant WHYPE_WHALE = 0xBd19E19E4b70eB7F248695a42208bc1EdBBFb57D;
    address constant HY_WSTHYPE_WHALE = 0x049752D7Cc26c855B50C2e4905c665Ab2333bFf2;

    // Token addresses (these should be set in the inheriting contract)
    address constant WSTHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address constant USDXL = 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645;
    address constant WHYPE = 0x5555555555555555555555555555555555555555;
    address constant HY_WSTHYPE = 0xC8b6E0acf159E058E22c564C0C513ec21f8a1Bf5;
    address constant STAT_HY_WHYPE = 0x3Df418bE6Dad3f824d00A7c516DAd3Ea2A5a79C6;
    address constant NATIVE_ASSET = address(0);

    bool public initializedWhales = false;

    /**
     * @notice Initialize whale addresses for known tokens
     * @dev Should be called in setUp() of inheriting contracts
     */
    function initializeWhales() internal {
        tokenWhales[WSTHYPE] = WSTHYPE_WHALE;
        tokenWhales[USDT0] = USDT_WHALE;
        tokenWhales[USDXL] = USDXL_WHALE;
        tokenWhales[WHYPE] = WHYPE_WHALE;
        tokenWhales[HY_WSTHYPE] = HY_WSTHYPE_WHALE;
    }

    /**
     * @notice Transfer tokens from a whale to a user
     * @param token The token contract address
     * @param user The user address to receive tokens
     * @param amount The amount of tokens to transfer
     * @return success Whether the transfer was successful
     * @return whaleAddress The whale address that was used for the transfer
     */
    function fundAccount(address token, address user, uint256 amount)
        internal
        returns (bool success, address whaleAddress)
    {
        if (_isNativeAsset(token)) {
            vm.deal(user, amount);
            return (true, address(0));
        }

        if (user == address(0)) {
            revert("User cannot be zero address");
        }

        if (!initializedWhales) {
            initializeWhales();
            initializedWhales = true;
        }

        IERC20 tokenContract = IERC20(token);

        if (_isStaticAsset(token)) {
            console2.log("Handling static asset");
            return _handleStaticAsset(token, user, amount);
        }

        if (tokenWhales[token] == address(0)) {
            console2.log("No whale addresses found for token", token);
            return (false, address(0));
        }

        // Check whale balance and transfer if sufficient
        uint256 balance = tokenContract.balanceOf(tokenWhales[token]);

        if (balance >= amount) {
            // Impersonate the whale and transfer tokens
            vm.startPrank(tokenWhales[token]);
            bool transferSuccess = tokenContract.transfer(user, amount);
            vm.stopPrank();

            if (transferSuccess) {
                return (true, tokenWhales[token]);
            } else {
                return (false, address(0));
            }
        } else {
            return (false, address(0));
        }
    }

    function _isStaticAsset(address token) internal pure returns (bool) {
        return token == STAT_HY_WHYPE;
    }

    function _handleStaticAsset(address token, address user, uint256 amount) internal returns (bool success, address whaleAddress) {
        address asset = IStaticATokenLM(token).asset();
        vm.startPrank(tokenWhales[asset]);
        console2.log("Approving asset");
        console2.log("Token:", token);
        console2.log("Asset:", asset);
        console2.log("Amount:", amount);
        console2.log("Whale:", tokenWhales[asset]);
        console2.log("Whale balance:", IERC20(asset).balanceOf(tokenWhales[asset]));
        //198728119522562594116
        //198728119522562594116
        IERC20(asset).approve(token, amount);
        uint256 depositedAmount = IStaticATokenLM(token).deposit(amount, user, 0, true);
        console2.log("Deposited amount:", depositedAmount);
        console2.log("Assets to shares:", IStaticATokenLM(token).convertToShares(amount));

        vm.stopPrank();
        return (true, tokenWhales[token]);
    }

    /**
     * @notice Transfer tokens from a specific whale to a user
     * @param token The token contract address
     * @param whale The specific whale address to use
     * @param user The user address to receive tokens
     * @param amount The amount of tokens to transfer
     * @return success Whether the transfer was successful
     */
    function transferTokensFromSpecificWhale(address token, address whale, address user, uint256 amount)
        internal
        returns (bool success)
    {
        console2.log("Attempting to transfer tokens from specific whale");
        console2.log("Amount:", amount);
        console2.log("Whale:", whale);
        console2.log("User:", user);

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(whale);

        console2.log("Whale balance:", balance);

        if (balance < amount) {
            console2.log("Whale has insufficient balance");
            return false;
        }

        // Impersonate the whale and transfer tokens
        vm.startPrank(whale);
        bool transferSuccess = tokenContract.transfer(user, amount);
        vm.stopPrank();

        if (transferSuccess) {
            console2.log("Transfer successful from whale");
            console2.log("Whale:", whale);
            return true;
        } else {
            console2.log("Transfer failed from whale");
            console2.log("Whale:", whale);
            return false;
        }
    }

    /**
     * @notice Check if a whale has sufficient balance for a token
     * @param token The token contract address
     * @param whale The whale address to check
     * @param amount The amount to check against
     * @return hasSufficientBalance Whether the whale has sufficient balance
     */
    function checkWhaleBalance(address token, address whale, uint256 amount)
        internal
        view
        returns (bool hasSufficientBalance)
    {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(whale);
        return balance >= amount;
    }

    /**
     * @notice Get the whale address for a token
     * @param token The token contract address
     * @return whale The whale address for the token
     */
    function getWhaleForToken(address token) internal view returns (address whale) {
        return tokenWhales[token];
    }

    /**
     * @notice Set a whale address for a token
     * @param token The token contract address
     * @param whale The whale address to set
     */
    function setWhaleForToken(address token, address whale) internal {
        tokenWhales[token] = whale;
        console2.log("Set whale for token");
        console2.log("Whale:", whale);
    }

    /**
     * @notice Fund a user with tokens and also fund a router/contract
     * @param user The user address to receive tokens
     * @param router The router/contract address to receive tokens
     * @param token The token contract address
     * @param userAmount The amount to transfer to user
     * @param routerAmount The amount to transfer to router
     * @return userSuccess Whether user funding was successful
     * @return routerSuccess Whether router funding was successful
     */
    function fundUserAndRouter(address user, address router, address token, uint256 userAmount, uint256 routerAmount)
        internal
        returns (bool userSuccess, bool routerSuccess)
    {
        console2.log("Funding user and router with token");

        // Fund user
        (bool userTransferSuccess,) = fundAccount(token, user, userAmount);
        userSuccess = userTransferSuccess;

        // Fund router
        (bool routerTransferSuccess,) = fundAccount(token, router, routerAmount);
        routerSuccess = routerTransferSuccess;

        console2.log("User funding success:", userSuccess);
        console2.log("Router funding success:", routerSuccess);

        return (userSuccess, routerSuccess);
    }

    /**
     * @notice Get token balance for a user
     * @param token The token contract address
     * @param user The user address
     * @return balance The token balance
     */
    function getTokenBalance(address token, address user) internal view returns (uint256 balance) {
        return IERC20(token).balanceOf(user);
    }

    /**
     * @notice Log whale information for debugging
     * @param token The token contract address
     */
    function logWhaleInfo(address token) internal view {
        console2.log("Token:");
        console2.log("Whale address:", tokenWhales[token]);

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(tokenWhales[token]);
        console2.log("Whale balance:", balance);
    }

    function _isNativeAsset(address asset) internal pure returns (bool) {
        return asset == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) || asset == address(0);
    }
}

interface IStaticATokenLM {
  /**
   * @notice Deposits `ASSET` in the Aave protocol and mints static aTokens to msg.sender
   * @param assets The amount of underlying `ASSET` to deposit (e.g. deposit of 100 USDC)
   * @param receiver The address that will receive the static aTokens
   * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   * @param depositToAave bool
   * - `true` if the msg.sender comes with underlying tokens (e.g. USDC)
   * - `false` if the msg.sender comes already with aTokens (e.g. aUSDC)
   * @return uint256 The amount of StaticAToken minted, static balance
   **/
  function deposit(
    uint256 assets,
    address receiver,
    uint16 referralCode,
    bool depositToAave
  ) external returns (uint256);

  function asset() external view returns (address);

  function convertToShares(uint256 assets) external view returns (uint256 shares);
}
