// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from '@aave/core-v3/contracts/interfaces/IAaveOracle.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol';
import {ConfiguratorInputTypes} from '@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol';

import {IUsdxlToken} from 'src/contracts/gho/interfaces/IGhoToken.sol';
import {UsdxlToken} from 'src/contracts/gho/GhoToken.sol';
import {UsdxlOracle} from 'src/contracts/facilitators/aave/oracle/GhoOracle.sol';
import {UsdxlAToken} from 'src/contracts/facilitators/aave/tokens/GhoAToken.sol';
import {UsdxlVariableDebtToken} from 'src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {UsdxlInterestRateStrategy} from 'src/contracts/facilitators/aave/interestStrategy/GhoInterestRateStrategy.sol';
import {UsdxlFlashMinter} from 'src/contracts/facilitators/flashMinter/GhoFlashMinter.sol';

import 'forge-std/console.sol';

contract LastTestnetReservesConfig {

  UsdxlAToken usdxlAToken;
  UsdxlVariableDebtToken usdxlVariableDebtToken;
  
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

    tokens[0] = address(new UsdxlToken(deployer));

    oracles = new address[](1);

    oracles[0] = address(new UsdxlOracle());

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
    
    tokens[0] = address(_getUsdxlToken()); // USDXL

    return tokens;
  }

function _setUsdxlOracle(
    address[] memory tokens,
    address[] memory oracles
  )
    internal
  { 
    // set oracles
    _getAaveOracle().setAssetSources(tokens, oracles);
  }

  function _initializeUsdxlReserve(
    address[] memory tokens
  ) 
    internal
  {
    ConfiguratorInputTypes.InitReserveInput[] memory inputs = new ConfiguratorInputTypes.InitReserveInput[](1);

    usdxlAToken = new UsdxlAToken(
      _getPoolInstance()
    );

    usdxlVariableDebtToken = new UsdxlVariableDebtToken(
      _getPoolInstance()
    );

    UsdxlInterestRateStrategy usdxlInterestRateStrategy = new UsdxlInterestRateStrategy(
      0x270542372e5a73c39E4290291AB88e2901cCEF2D, // PoolAddressesProvider
      15000000000000000000000000 // base variable borrow rate (1.5%)
    );

    inputs[0] = ConfiguratorInputTypes.InitReserveInput({
      aTokenImpl: address(usdxlAToken), // Address of the aToken implementation
      variableDebtTokenImpl: address(usdxlVariableDebtToken), // Address of the variable debt token implementation
      useVirtualBalance: false, // true for all normal assets and should be false only in special cases (ex. GHO) where an asset is minted instead of supplied.
      interestRateStrategyAddress: address(usdxlInterestRateStrategy), // Address of the interest rate strategy
      underlyingAsset: address(tokens[0]), // GHO address
      treasury: address(0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518), // Address of the treasury
      incentivesController: address(0x21455b64CD8f992B2500a55243d2C179a77C83A1), // Address of the incentives controller
      aTokenName: 'USDXL Aave',
      aTokenSymbol: 'awUSDXL',
      variableDebtTokenName: 'Test USDXL Variable Debt Aave',
      variableDebtTokenSymbol: 'variableDebtTestUSDXL',
      params: bytes('0x10'), // Additional parameters for initialization
      interestRateData: bytes('')
    });
    
    // set reserves configs
    _getPoolConfigurator().initReserves(inputs);
  }

  function _enableUsdxlBorrowing(
    address[] memory tokens
  )
    internal
  {
    _getPoolConfigurator().setReserveBorrowing(tokens[0], true);
  }

  function _addUsdxlATokenAsEntity()
    internal
  {
    _getUsdxlToken().addFacilitator(
      address(_getUsdxlATokenProxy()),
      'Aave V3 Last Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _addUsdxlFlashMinterAsEntity(
    address[] memory tokens
  )
    internal
  {
    UsdxlFlashMinter usdxlFlashMinter = new UsdxlFlashMinter(
      tokens[0], // GHO token
      0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518, // TreasuryProxy
      0, // fee in bips for flash-minting (covered on repay)
      0x270542372e5a73c39E4290291AB88e2901cCEF2D // PoolAddressesProvider
    );

    UsdxlToken(tokens[0]).addFacilitator(
      address(usdxlFlashMinter),
      'Aave V3 Last Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _setUsdxlAddresses()
    internal
  {
    // usdxlAToken.updateUsdxlTreasury(0xa2CCdD20525d5225b4AB08c10D1aFfb6de84D518);

    // UsdxlAToken(_getUsdxlATokenProxy()).setVariableDebtToken(_getUsdxlVariableDebtToken());

    //deploy new impl
    // UsdxlVariableDebtToken newDebtTokenImpl = new UsdxlVariableDebtToken(_getPoolInstance());

    // upgrade debt token impl
    // _getPoolConfigurator().updateVariableDebtToken(
    //   ConfiguratorInputTypes.UpdateDebtTokenInput({
    //     asset: address(_getUsdxlToken()),
    //     incentivesController: address(0x21455b64CD8f992B2500a55243d2C179a77C83A1),
    //     name: 'Test USDXL Variable Debt Aave',
    //     symbol: 'variableDebtTestUSDXL',
    //     implementation: address(0x0bb30e5523b9EDD240F81d498FfA24fEdbb4055f),
    //     params: bytes('0x10')
    //   })
    // );

    //set aToken
    
    UsdxlVariableDebtToken(_getUsdxlVariableDebtToken()).setAToken(address(0x43FF14af721DC22e891cA16A1504692aFcf0a06b));
  }

  function _setDiscountTokenAndStrategy(
    address discountRateStrategy,
    address discountToken
  )
    internal
  {
    usdxlVariableDebtToken = UsdxlVariableDebtToken(0x9A29D4ad8fa79C328c4350BF771399fD2f991dC4);
    if (discountRateStrategy != address(0))
      usdxlVariableDebtToken.updateDiscountRateStrategy(discountRateStrategy);
    if (discountToken != address(0))
      usdxlVariableDebtToken.updateDiscountToken(discountToken);
  }

  function _borrowUsdxl(
    uint256 amount,
    address onBehalfOf
  )
    internal
  {
    _getPoolInstance().borrow(
      address(_getUsdxlToken()),
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
    _getUsdxlToken().approve(address(_getPoolInstance()), amount);
    _getPoolInstance().repay(
      address(_getUsdxlToken()),
      amount,
      2, // interest rate mode
      onBehalfOf
    );
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

  function _getPoolInstance()
    internal
    pure
    returns (
      IPool
    )
  {
    return IPool(0xBD2f32C02140641f497B0Db7B365122214f7c548);
  }

  function _getUsdxlToken()
    internal
    pure
    returns (
      IUsdxlToken
    )
  {
    return IUsdxlToken(0x17a44c591ac723D76050Fe6bf02B49A0CC8F3994);
  }

  function _getUsdxlATokenProxy()
    internal
    pure
    returns (
      address
    )
  {
    return 0x43FF14af721DC22e891cA16A1504692aFcf0a06b;
  }

  function _getUsdxlVariableDebtToken()
    internal
    pure
    returns (
      address
    )
  {
    return 0x9A29D4ad8fa79C328c4350BF771399fD2f991dC4;
  }
}
