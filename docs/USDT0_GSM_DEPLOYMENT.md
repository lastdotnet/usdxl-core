# USDT0 GSM Deployment Guide

## Overview

This guide explains how to deploy a USDT0 GSM (GHO Stability Module) for USDXL. The GSM allows users to swap between USDXL and USDT0 tokens at a fixed exchange rate, providing liquidity and stability for the USDXL ecosystem.

## What is a GSM?

A GSM (GHO Stability Module) is a market maker that facilitates swaps between USDXL and an underlying asset (in this case, USDT0). It provides:

- **Buy Asset**: Users can sell USDXL to receive USDT0
- **Sell Asset**: Users can sell USDT0 to receive USDXL
- **Fixed Exchange Rate**: 1:1 ratio between USDXL and USDT0
- **Fee Structure**: Configurable fees for buy/sell operations
- **Exposure Management**: Configurable exposure caps to manage risk

## Prerequisites

Before deploying the USDT0 GSM, ensure you have:

1. **USDXL Token**: Already deployed and configured
2. **USDT0 Token**: The target stablecoin token address
3. **Deployer Account**: An account with sufficient ETH for deployment
4. **Admin Roles**: Access to USDXL admin functions
5. **Environment Setup**: Foundry installed and configured

## Configuration

Edit the `Usdt0GsmConfig` struct in `script/deploy/DeployUsdt0Gsm.s.sol`:

```solidity
Usdt0GsmConfig memory config = Usdt0GsmConfig({
    usdxlToken: 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645, // USDXL token address
    usdt0Token: 0x0000000000000000000000000000000000000000, // USDT0 token address - UPDATE THIS
    usdxlAdmin: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // USDXL admin address
    gsmOwner: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // GSM owner address
    treasury: 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb, // Treasury address
    priceRatio: 1e18, // 1:1 price ratio (1 USDT0 = 1 USDXL)
    buyFee: 0.02e4, // 2% buy fee
    sellFee: 0, // 0% sell fee
    exposureCap: 1000000e6, // 1M USDT0 exposure cap (assuming 6 decimals)
    gsmCapacity: 1000000e18 // 1M USDXL capacity
});
```

### Configuration Parameters

- **usdxlToken**: Address of the USDXL token contract
- **usdt0Token**: Address of the USDT0 token contract (UPDATE THIS)
- **usdxlAdmin**: Address with USDXL admin privileges
- **gsmOwner**: Address that will own the GSM contract
- **treasury**: Address that receives GSM fees
- **priceRatio**: Exchange rate from USDT0 to USDXL (1e18 = 1:1)
- **buyFee**: Fee charged when buying USDT0 with USDXL (in basis points)
- **sellFee**: Fee charged when selling USDT0 for USDXL (in basis points)
- **exposureCap**: Maximum amount of USDT0 the GSM can hold
- **gsmCapacity**: Maximum amount of USDXL the GSM can mint

## Deployment Steps

### 1. Set Environment Variables

Create a `.env` file with your private key:

```bash
PRIVATE_KEY=your_private_key_here
```

### 2. Update USDT0 Token Address

Replace the placeholder USDT0 token address in the deployment script with the actual address.

### 3. Deploy the GSM

Run the deployment script:

```bash
# For local testing
forge script script/deploy/DeployUsdt0Gsm.s.sol --broadcast --fork-url http://localhost:8545

# For testnet
forge script script/deploy/DeployUsdt0Gsm.s.sol --broadcast --rpc-url $TESTNET_RPC_URL

# For mainnet
forge script script/deploy/DeployUsdt0Gsm.s.sol --broadcast --rpc-url $MAINNET_RPC_URL
```

### 4. Verify Deployment

The script will output deployment addresses and save them to `deployments/usdt0-gsm-deployment.json`.

## Post-Deployment Setup

After deployment, you may need to:

1. **Grant Roles**: Ensure the GSM has the necessary roles on the USDXL token
2. **Fund the GSM**: Provide initial USDT0 liquidity to the GSM
3. **Configure Parameters**: Adjust fees, exposure caps, or other parameters as needed
4. **Add to Registry**: Register the GSM in any relevant registries

## Contract Architecture

The deployment creates several contracts:

1. **FixedPriceStrategy**: Manages the 1:1 exchange rate between USDXL and USDT0
2. **FixedFeeStrategy**: Handles buy/sell fees
3. **Gsm Implementation**: Core GSM logic
4. **Gsm Proxy**: Upgradeable proxy for the GSM implementation

## Usage Examples

### Buying USDT0 with USDXL

```solidity
// User calls buyAsset to sell USDXL and receive USDT0
gsm.buyAsset(minAmount, receiver);
```

### Selling USDT0 for USDXL

```solidity
// User calls sellAsset to sell USDT0 and receive USDXL
gsm.sellAsset(maxAmount, receiver);
```

## Security Considerations

1. **Access Control**: Ensure only authorized addresses can call admin functions
2. **Exposure Limits**: Set appropriate exposure caps to manage risk
3. **Fee Structure**: Consider the impact of fees on user adoption
4. **Liquidity**: Ensure sufficient USDT0 liquidity is available
5. **Upgradeability**: The GSM is upgradeable via proxy - secure the admin role

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure the deployer has USDXL admin privileges
2. **Invalid Token Address**: Verify the USDT0 token address is correct
3. **Insufficient Balance**: Ensure the deployer has enough ETH for gas
4. **Token Decimals**: Verify the USDT0 token has the expected decimals (typically 6)

### Verification

To verify the deployed contracts on Etherscan:

```bash
forge verify-contract --rpc-url $RPC_URL --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY <CONTRACT_ADDRESS> <CONTRACT_NAME>
```

## Support

For questions or issues with the USDT0 GSM deployment, please refer to the project documentation or contact the development team. 