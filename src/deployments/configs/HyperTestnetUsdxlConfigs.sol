// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol";
import {ConfiguratorInputTypes} from "@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import {IDefaultInterestRateStrategy} from "@aave/core-v3/contracts/interfaces/IDefaultInterestRateStrategy.sol";
import {AdminUpgradeabilityProxy} from
    "@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol";
import {Constants} from "src/test/helpers/Constants.sol";

import {IUsdxlToken} from "src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {UpgradeableUsdxlToken} from "src/contracts/usdxl/UpgradeableUsdxlToken.sol";
import {UsdxlOracle} from "src/contracts/facilitators/hyfi/oracle/UsdxlOracle.sol";
import {UsdxlAToken} from "src/contracts/facilitators/hyfi/tokens/UsdxlAToken.sol";
import {UsdxlVariableDebtToken} from "src/contracts/facilitators/hyfi/tokens/UsdxlVariableDebtToken.sol";
import {UsdxlInterestRateStrategy} from "src/contracts/facilitators/hyfi/interestStrategy/UsdxlInterestRateStrategy.sol";
import {UsdxlFlashMinter} from "src/contracts/facilitators/flashMinter/UsdxlFlashMinter.sol";

import {Gsm} from "src/contracts/facilitators/gsm/Gsm.sol";
import {FixedFeeStrategy} from "src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {FixedPriceStrategy} from "src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";

import {HyperTestnetReservesConfigs} from "@hypurrfi/deployments/configs/HyperTestnetReservesConfigs.sol";
import {DeployUsdxlUtils} from "src/deployments/utils/DeployUsdxlUtils.sol";
import {DeployUsdxlFileUtils} from "src/deployments/utils/DeployUsdxlFileUtils.sol";

import "forge-std/console.sol";

contract HyperTestnetUsdxlConfigs is HyperTestnetReservesConfigs, Constants {}
