// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from '@aave/core-v3/contracts/interfaces/IAaveOracle.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol';
import {ConfiguratorInputTypes} from '@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol';
import {AaveV3SetupBatch} from '@aave/core-v3/deployments/projects/aave-v3-batched/batches/AaveV3SetupBatch.sol';
import {MarketReport} from '@aave/core-v3/deployments/interfaces/IMarketReportTypes.sol';
import {IDefaultInterestRateStrategyV2} from '@aave/core-v3/contracts/interfaces/IDefaultInterestRateStrategyV2.sol';

import {IGhoToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {GhoToken} from 'src/contracts/gho/GhoToken.sol';
import {GhoOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';
import {GhoAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {GhoVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {GhoInterestRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoInterestRateStrategy.sol';
import {GhoFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

import 'forge-std/console.sol';

contract HyperTestnetReservesConfig {

  IGhoToken ghoToken;
  GhoAToken ghoAToken;
  GhoVariableDebtToken ghoVariableDebtToken;

  AaveV3SetupBatch public constant MARKET_REPORT = AaveV3SetupBatch(0x114e4d85Db6E7082CC4366b849648ABE288b77eC);
  
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

    tokens[0] = address(new GhoToken(deployer));

    oracles = new address[](1);

    oracles[0] = address(new GhoOracle());

    ghoToken = IGhoToken(tokens[0]);

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

    ghoToken = _getGhoToken();
    
    tokens[0] = address(_getGhoToken()); // GHO

    return tokens;
  }

function _setGhoOracle(
    address[] memory tokens,
    address[] memory oracles
  )
    internal
  { 
    // set oracles
    _getAaveOracle().setAssetSources(tokens, oracles);
  }

  function _initializeGhoReserve(
    address[] memory tokens
  ) 
    internal
  {
    ConfiguratorInputTypes.InitReserveInput[] memory inputs = new ConfiguratorInputTypes.InitReserveInput[](1);

    ghoAToken = new GhoAToken(
      _getPoolInstance()
    );

    ghoVariableDebtToken = new GhoVariableDebtToken(
      _getPoolInstance()
    );

    MarketReport memory marketReport = _getMarketReport();

    IDefaultInterestRateStrategyV2.InterestRateData memory rateData = IDefaultInterestRateStrategyV2.InterestRateData({
      optimalUsageRatio: uint16(80_00),
      baseVariableBorrowRate: uint32(1_00),
      variableRateSlope1: uint32(4_00),
      variableRateSlope2: uint32(60_00)
    });

    inputs[0] = ConfiguratorInputTypes.InitReserveInput({
      aTokenImpl: address(ghoAToken), // Address of the aToken implementation
      variableDebtTokenImpl: address(ghoVariableDebtToken), // Address of the variable debt token implementation
      useVirtualBalance: false, // true for all normal assets and should be false only in special cases (ex. GHO) where an asset is minted instead of supplied.
      interestRateStrategyAddress: marketReport.defaultInterestRateStrategy, // Address of the interest rate strategy
      underlyingAsset: tokens[0], // GHO address
      treasury: marketReport.treasury, // Address of the treasury
      incentivesController: marketReport.rewardsControllerProxy, // Address of the incentives controller
      aTokenName: 'USDXL Aave',
      aTokenSymbol: 'awUSDXL',
      variableDebtTokenName: 'Test USDXL Variable Debt Aave',
      variableDebtTokenSymbol: 'variableDebtTestUSDXL',
      params: bytes('0x10'), // Additional parameters for initialization
      interestRateData: abi.encode(rateData)
    });
    
    // set reserves configs
    _getPoolConfigurator().initReserves(inputs);
  }

  function _enableGhoBorrowing(
    address[] memory tokens
  )
    internal
  {
    _getPoolConfigurator().setReserveBorrowing(tokens[0], true);
  }

  function _addGhoATokenAsEntity()
    internal
  {
    // pull aToken proxy from reserves config
    _getGhoToken().addFacilitator(
      address(_getGhoATokenProxy()),
      'Aave V3 Hyper Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _addGhoFlashMinterAsEntity(
    address[] memory tokens
  )
    internal
  {
    MarketReport memory marketReport = _getMarketReport();

    GhoFlashMinter ghoFlashMinter = new GhoFlashMinter(
      address(_getGhoToken()), // GHO token
      marketReport.treasury, // TreasuryProxy
      0, // fee in bips for flash-minting (covered on repay)
      marketReport.poolAddressesProvider // PoolAddressesProvider
    );

    GhoToken(tokens[0]).addFacilitator(
      address(ghoFlashMinter),
      'Aave V3 Last Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _setGhoAddresses()
    internal
  {
    MarketReport memory marketReport = _getMarketReport();

    ghoAToken.updateGhoTreasury(marketReport.treasury);

    GhoAToken(_getGhoATokenProxy()).setVariableDebtToken(_getGhoVariableDebtToken());

    //set aToken
    GhoVariableDebtToken(_getGhoVariableDebtToken()).setAToken(_getGhoATokenProxy());
  }

  function _setDiscountTokenAndStrategy(
    address discountRateStrategy,
    address discountToken
  )
    internal
  {
    ghoVariableDebtToken = GhoVariableDebtToken(_getGhoVariableDebtToken());
    if (discountRateStrategy != address(0))
      ghoVariableDebtToken.updateDiscountRateStrategy(discountRateStrategy);
    if (discountToken != address(0))
      ghoVariableDebtToken.updateDiscountToken(discountToken);
  }

  function _borrowUsdxl(
    uint256 amount,
    address onBehalfOf
  )
    internal
  {
    _getPoolInstance().borrow(
      address(_getGhoToken()),
      amount,
      2, // interest rate mode
      0,
      onBehalfOf
    );
  }

  function _repayUsdxl(
    uint256 amount,
    address onBehalfOf
  )
    internal
  {
    _getGhoToken().approve(address(_getPoolInstance()), amount);
    _getPoolInstance().repay(
      address(_getGhoToken()),
      amount,
      2, // interest rate mode
      onBehalfOf
    );
  }

  function _getAaveOracle()
    internal
    view
    returns (
      IAaveOracle
    )
  {
    return IAaveOracle(_getMarketReport().aaveOracle);
  }

  function _getPoolConfigurator()
    internal
    view
    returns (
      IPoolConfigurator
    )
  {
    return IPoolConfigurator(_getMarketReport().poolConfiguratorProxy);
  }

  function _getPoolInstance()
    internal
    view
    returns (
      IPool
    )
  {
    return IPool(_getMarketReport().poolProxy);
  }

  function _getMarketReport()
    internal
    view
    returns (
      MarketReport memory
    ) {
      return AaveV3SetupBatch(MARKET_REPORT).getMarketReport();
  }

  function _getGhoToken()
    internal
    view
    returns (
      IGhoToken
    )
  {
    if (address(ghoToken) != address(0))
      return IGhoToken(address(ghoToken));
    return IGhoToken(address(0));
  }

  function _getGhoATokenProxy()
    internal
    view
    returns (
      address
    )
  {
    // read from reserves config
    return _getPoolInstance().getReserveData(address(ghoToken)).aTokenAddress;
  }

  function _getGhoVariableDebtToken()
    internal
    view
    returns (
      address
    )
  {
    // read from reserves config
    return _getPoolInstance().getReserveData(address(ghoToken)).variableDebtTokenAddress;
  }
}
