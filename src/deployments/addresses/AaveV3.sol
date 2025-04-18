// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {Errors} from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";
import {ConfiguratorInputTypes} from "@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {IACLManager as BasicIACLManager} from "@aave/core-v3/contracts/interfaces/IACLManager.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {IDefaultInterestRateStrategy} from "@aave/core-v3/contracts/interfaces/IDefaultInterestRateStrategy.sol";
import {IReserveInterestRateStrategy} from "@aave/core-v3/contracts/interfaces/IReserveInterestRateStrategy.sol";
import {IPoolDataProvider as IAaveProtocolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {AggregatorInterface} from "@aave/core-v3/contracts/dependencies/chainlink/AggregatorInterface.sol";

interface IACLManager is BasicIACLManager {
    function hasRole(bytes32 role, address account) external view returns (bool);

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);

    function renounceRole(bytes32 role, address account) external;

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;
}
