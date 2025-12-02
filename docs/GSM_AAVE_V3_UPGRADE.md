# GSM Aave V3 Upgrade Guide

This guide explains how to upgrade an existing GSM (GHO Stability Module) to integrate with Aave V3 for yield generation.

## Overview

The upgrade script (`UpgradeGsmToAaveV3.s.sol`) upgrades an existing GSM to a new implementation that:

1. **Deposits existing USDT0 balance** into an Aave V3 pool for yield generation
2. **Redirects all new deposits and withdrawals** to go through the Aave V3 pool
3. **Keeps all interest earned** by the GSM for potential withdrawal by the GSM admin
4. **Maintains the 1:1 price ratio** between USDT0 and USDXL

## Prerequisites

Before running the upgrade script, ensure you have:

1. **Access to the existing GSM proxy** and its proxy admin
2. **Aave V3 addresses provider** for the target network
3. **Sufficient permissions** to upgrade the proxy
4. **USDT0 token** deployed and configured
5. **USDXL token** deployed and configured

## Configuration

Update the following addresses in `UpgradeGsmToAaveV3.s.sol`:

```solidity
UpgradeConfig memory config = UpgradeConfig({
    gsmProxy: 0x0000000000000000000000000000000000000000, // UPDATE: Existing GSM proxy address
    proxyAdmin: 0x0000000000000000000000000000000000000000, // UPDATE: Proxy admin address
    aaveAddressesProvider: 0x0000000000000000000000000000000000000000, // UPDATE: Aave V3 addresses provider
    usdt0Token: 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, // USDT0 token address
    usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
    admin: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb // Admin address
});
```

### Required Addresses

- **gsmProxy**: The address of the existing GSM proxy contract
- **proxyAdmin**: The address of the proxy admin contract
- **aaveAddressesProvider**: The Aave V3 addresses provider for your network
- **usdt0Token**: The USDT0 token contract address
- **usdxlToken**: The USDXL token contract address
- **admin**: The admin address that will control the upgraded GSM

## Running the Upgrade

### 1. Test the Upgrade (Recommended)

First, run the test script to verify everything works:

```bash
forge script script/deploy/TestGsmAaveV3Upgrade.s.sol:TestGsmAaveV3Upgrade --rpc-url <RPC_URL> --broadcast --verify
```

### 2. Run the Upgrade Script

```bash
forge script script/deploy/UpgradeGsmToAaveV3.s.sol:UpgradeGsmToAaveV3 --rpc-url <RPC_URL> --broadcast --verify
```

### 3. Verify the Upgrade

After running the upgrade script, verify that:

1. The GSM proxy now points to the new implementation
2. The existing USDT0 balance has been deposited into Aave V3
3. The GSM can still perform buy/sell operations
4. Interest is being accumulated in the aToken

## New Features

### Aave V3 Integration

The upgraded GSM includes the following new functions:

- `migrateToAaveV3()`: Migrates existing USDT0 balance to Aave V3
- `withdrawInterest(uint256 amount)`: Allows admin to withdraw earned interest
- `getTotalDepositedInAave()`: Returns total amount deposited in Aave V3
- `getATokenBalance()`: Returns current aToken balance
- `getTotalUnderlyingBalance()`: Returns total underlying balance including Aave deposits

### Interest Management

- All interest earned from Aave V3 deposits is kept by the GSM
- The GSM admin can withdraw interest using `withdrawInterest()`
- Interest is represented by aTokens and can be redeemed for USDT0

### Maintained Functionality

- All existing GSM functions remain unchanged
- Price ratio remains 1:1 between USDT0 and USDXL
- All access control and security features are preserved
- EIP-712 signature support is maintained
- EIP-2612 permit support for gas-efficient transactions

### New UX Improvements

- **EIP-2612 Permit Support**: Added `sellAssetWithPermit()` function that allows users to sell assets without a separate approval transaction
- **Better Gas Efficiency**: Users can now sell assets in a single transaction using EIP-2612 permits
- **Flexible Transaction Options**: Users can choose between traditional approve + sell, signature-based sell, or permit-based sell

## User Experience Considerations

### Approval Requirements

**Important**: The `sellAsset()` and `sellAssetWithSig()` functions require users to approve the GSM contract to spend their USDT0 tokens before selling. This is because these functions use `safeTransferFrom()` to transfer tokens from the user to the GSM.

**Three Options for Users**:

1. **Traditional Approach** (2 transactions):
   ```solidity
   // Step 1: Approve GSM to spend USDT0
   usdt0.approve(gsmAddress, amount);
   
   // Step 2: Sell USDT0 for USDXL
   gsm.sellAsset(maxAmount, receiver);
   ```

2. **Signature Approach** (2 transactions, but with signature for authorization):
   ```solidity
   // Step 1: Approve GSM to spend USDT0
   usdt0.approve(gsmAddress, amount);
   
   // Step 2: Sell USDT0 for USDXL using signature
   gsm.sellAssetWithSig(originator, maxAmount, receiver, deadline, signature);
   ```

3. **Permit Approach** (1 transaction, if USDT0 supports EIP-2612):
   ```solidity
   // Single transaction using permit signature
   gsm.sellAssetWithPermit(
     maxAmount, 
     receiver, 
     deadline,
     v,
     r,
     s
   );
   ```

### Frontend Integration

When integrating with frontends, consider:

- **Check Permit Support**: Verify if USDT0 supports EIP-2612 permit functionality
- **Fallback Strategy**: Always provide the traditional approve + sell flow as fallback
- **Gas Estimation**: Permit transactions are more gas-efficient
- **User Education**: Clearly explain the different transaction options to users
- **Signature Management**: Handle both EIP-712 signatures and EIP-2612 permits

## Post-Upgrade Operations

### 1. Monitor Aave V3 Integration

Check that the GSM is properly integrated with Aave V3:

```solidity
// Get total deposited amount
uint256 totalDeposited = gsm.getTotalDepositedInAave();

// Get current aToken balance
uint256 aTokenBalance = gsm.getATokenBalance();

// Get total underlying balance
uint256 totalBalance = gsm.getTotalUnderlyingBalance();
```

### 2. Withdraw Interest (Admin Only)

The GSM admin can withdraw earned interest:

```solidity
// Withdraw specific amount of interest
gsm.withdrawInterest(amount);

// Or withdraw all available interest
uint256 aTokenBalance = gsm.getATokenBalance();
gsm.withdrawInterest(aTokenBalance);
```

### 3. Monitor Performance

Track the performance of the Aave V3 integration:

- Monitor aToken balance growth over time
- Track interest earned vs. deposited amount
- Ensure liquidity remains available for users

## Security Considerations

1. **Access Control**: Only the GSM admin can withdraw interest
2. **Aave V3 Integration**: Ensure Aave V3 contracts are properly verified
3. **Liquidity Management**: Monitor available liquidity for user operations
4. **Interest Withdrawal**: Implement proper controls for interest withdrawal

## Troubleshooting

### Common Issues

1. **Upgrade Permission Denied**: Ensure you have admin rights on the proxy
2. **Aave V3 Integration Failed**: Verify Aave V3 addresses provider is correct
3. **Migration Failed**: Check USDT0 balance and Aave V3 pool availability
4. **Interface Mismatch**: Ensure the new implementation is compatible

### Verification Steps

1. Check GSM revision: `gsm.GSM_REVISION()` should return 2
2. Verify Aave integration: `gsm.getTotalDepositedInAave()` should be > 0
3. Test buy/sell operations to ensure they work with Aave V3
4. Verify interest accumulation over time

## Network-Specific Configuration

### Ethereum Mainnet

```solidity
aaveAddressesProvider: 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e
```

### Polygon

```solidity
aaveAddressesProvider: 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
```

### Avalanche

```solidity
aaveAddressesProvider: 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
```

## Support

For questions or issues with the upgrade process, please refer to:

1. The Aave V3 documentation: https://docs.aave.com/developers/
2. The GSM documentation in this repository
3. The upgrade script comments and error messages

## Changelog

- **v2.0.0**: Initial Aave V3 integration
  - Added Aave V3 deposit/withdraw functionality
  - Implemented interest accumulation for GSM admin
  - Maintained 1:1 price ratio
  - Preserved all existing GSM functionality
