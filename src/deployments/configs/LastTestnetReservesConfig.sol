// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {MockAggregator} from '@aave/core-v3/contracts/mocks/oracle/CLAggregators/MockAggregator.sol';
import {IAaveOracle} from '@aave/core-v3/contracts/interfaces/IAaveOracle.sol';
import {IPoolConfigurator} from '@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol';
import {ConfiguratorInputTypes} from '@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol';
import {IDefaultInterestRateStrategyV2} from '@aave/core-v3/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';
import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import 'forge-std/console.sol';

contract LastTestnetReservesConfig {
  function _deployTestnetTokens(
    address deployer
  )
    internal
    returns (
        address[] memory tokens,
        address[] memory oracles
    )
  { 
    tokens  = new address[](1);

    tokens[0] = address(new GhoToken(deployerAddress));

    oracles = new address[](1);

    oracles[0] = address(new MockAggregator(1.005e8));

    return (tokens, oracles);
  }

  function _fetchTestnetTokens(
    address deployer
  )
    internal
    returns (
        address[] memory tokens
    )
  { 
    tokens  = new address[](1);
    
    tokens[0] = address(0x0); // GHO

    return tokens;
  }

function _setAssetSources(
    address[] memory tokens,
    address[] memory oracles
  )
    internal
  { 
    // set oracles
    _getAaveOracle().setAssetSources(tokens, oracles);
  }

  function _initReserves(
    address[] memory tokens
  ) 
    internal
  {
    ConfiguratorInputTypes.InitReserveInput[] memory inputs = new ConfiguratorInputTypes.InitReserveInput[](1);

    IDefaultInterestRateStrategyV2.InterestRateData memory rateData = IDefaultInterestRateStrategyV2.InterestRateData({
      optimalUsageRatio: uint16(80_00),
      baseVariableBorrowRate: uint32(1_00),
      variableRateSlope1: uint32(4_00),
      variableRateSlope2: uint32(60_00)
    });

    inputs[0] = ConfiguratorInputTypes.InitReserveInput({
      aTokenImpl: address(0xEcfc9497777345BEda45506deA064c2e17B06B8c), // Address of the aToken implementation
      variableDebtTokenImpl: address(0x49526edA124F2295BBF0f02817D1bB27E1C6F23E ), // Address of the variable debt token implementation
      useVirtualBalance: false, // TODO is this important? not mentioned in code or spark interface
      interestRateStrategyAddress: address(0xDeaeA8D8769a14092d381Ac44D9cfB5638D68478), // Address of the interest rate strategy
      underlyingAsset: address(tokens[0]), // GHO address
      treasury: address(0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518), // Address of the treasury
      incentivesController: address(0x21455b64CD8f992B2500a55243d2C179a77C83A1), // Address of the incentives controller
      aTokenName: 'USDXL Aave',
      aTokenSymbol: 'awUSDXL',
      variableDebtTokenName: 'Test USDXL Variable Debt Aave',
      variableDebtTokenSymbol: 'variableDebtTestUSDXL',
      params: bytes(''), // Additional parameters for initialization
      interestRateData: abi.encode(rateData)
    });
    
    // set reserves configs
    _getPoolConfigurator().initReserves(inputs);
  }

  function _enableCollateral(
    address[] memory tokens
  )
    internal
  {
    _getPoolConfigurator().configureReserveAsCollateral(
      tokens[0],
      8000, // LTV (80%)
      9000, // Liq. threshold (90%)
      10500 // Liq. bonus (5% tax)
    );
  }

  function _enableBorrowing(
    address[] memory tokens
  )
    internal
  {
    _getPoolConfigurator().setReserveBorrowing(tokens[0], true);
  }

  function _getAaveOracle()
    internal
    pure
    returns (
      IAaveOracle
    )
  {
    return IAaveOracle(0xE6C26ED28215f2bb33C3F97768d250eFC98586b4);
  }

  function _getPoolConfigurator()
    internal
    pure
    returns (
      IPoolConfigurator
    )
  {
    return IPoolConfigurator(0x4c1E6019200329A039d5AD5b577838967250c0C3);
  }
}
