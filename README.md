[![Build pass](https://github.com/aave/gho/actions/workflows/node.js.yml/badge.svg)](https://github.com/aave/gho/actions/workflows/node.js.yml)

# Usdxl

This repository contains the source code, tests and deployments for both USDXL itself and the first facilitator integrating HypurrFi. The repository uses the Foundry development framework.

## Description

USDXL is a decentralized, protocol-agnostic crypto-asset intended to maintain a stable value. USDXL is minted and burned by approved entities named Facilitators.

The first facilitator is the HypurrFi V3 Ethereum Pool, which allows users to mint USDXL against their collateral assets, based on the interest rate set by the HypurrFi Governance. In addition, there is a FlashMint module as a second facilitator, which facilitates arbitrage and liquidations, providing instant liquidity.

Furthermore, the HypurrFi Governance has the ability to approve entities as Facilitators and manage the total amount of USDXL they can generate (also known as bucket's capacity).

## Documentation

See the link to the technical paper

- [Technical Paper](./techpaper/GHO_Technical_Paper.pdf)
- [Developer Documentation](https://docs.gho.xyz/)

## Audits and Formal Verification

You can find all audit reports under the [audits](./audits/) folder

- [2022-08-12 - OpenZeppelin](./audits/2022-08-12_Openzeppelin-v1.pdf)
- [2022-11-10 - OpenZeppelin](./audits/2022-11-10_Openzeppelin-v2.pdf)
- [2023-03-01 - ABDK](./audits/2023-03-01_ABDK.pdf)
- [2023-02-28 - Certora Formal Verification](./certora/reports/Aave_Gho_Formal_Verification_Report.pdf)
- [2023-07-06 - Sigma Prime](./audits/2023-07-06_SigmaPrime.pdf)
- [2023-06-13 - Sigma Prime (GhoSteward)](./audits/2023-06-13_GhoSteward_SigmaPrime.pdf)
- [2023-09-20 - Emanuele Ricci @Stermi (GHO Stability Module)](./audits/2023-09-20_GSM_Stermi.pdf)
- [2023-10-23 - Sigma Prime (GHO Stability Module)](./audits/2023-10-23_GSM_SigmaPrime.pdf)
- [2023-12-07 - Certora Formal Verification (GHO Stability Module)](./certora/reports/Formal_Verification_Report_of_GHO_Stability_Module.pdf)
- [2024-03-14 - Certora Formal Verification (GhoStewardV2)](./audits/2024-03-14_GhoStewardV2_Certora.pdf)
- [2024-06-11 - Certora Formal Verification (UpgradeableGHO)](./audits/2024-06-11_UpgradeableGHO_Certora.pdf)
- [2024-06-11 - Certora Formal Verification (Modular Gho Stewards)](./audits/2024-09-15_ModularGhoStewards_Certora.pdf)

## Getting Started

Clone the repository and run the following command to install dependencies:

```sh
forge i
```

```sh
cp .env.example .env
# Fill PRIVATE_KEY and PUBLIC_KEY in the .env file with your editor
code .env
```

Compile contracts:

```sh
forge build
```

Run the test suite:

```sh
forge test
```

Deploy and setup USDXL in a local Anvil network:

```sh
anvil
# In a new terminal:
forge script script/DeployUsdxl.sol --broadcast --fork-url http://localhost:8545
```

Deploy and setup USDXL in Goerli testnet:

```sh
forge script script/DeployUsdxl.sol --broadcast --rpc-url $GOERLI_RPC_URL
```

## Connect with the community

You can join the [Telegram](https://t.me/+YvsBvSxlQrVhNDkx) channel to ask questions about the protocol or talk about USDXL with other peers.
