// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAaveOracle} from '@aave/core-v3/contracts/interfaces/IAaveOracle.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPoolConfigurator} from '@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol';
import {ConfiguratorInputTypes} from '@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol';
import {IDefaultInterestRateStrategy} from '@aave/core-v3/contracts/interfaces/IDefaultInterestRateStrategy.sol';
import {AdminUpgradeabilityProxy} from '@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol';
import {Constants} from 'src/test/helpers/Constants.sol';

import {IUsdxlToken} from 'src/contracts/usdxl/interfaces/IUsdxlToken.sol';
import {UsdxlToken} from 'src/contracts/usdxl/UsdxlToken.sol';
import {UsdxlOracle} from 'src/contracts/facilitators/hyfi/oracle/UsdxlOracle.sol';
import {UsdxlAToken} from 'src/contracts/facilitators/hyfi/tokens/UsdxlAToken.sol';
import {UsdxlVariableDebtToken} from 'src/contracts/facilitators/hyfi/tokens/UsdxlVariableDebtToken.sol';
import {UsdxlInterestRateStrategy} from 'src/contracts/facilitators/hyfi/interestStrategy/UsdxlInterestRateStrategy.sol';
import {UsdxlFlashMinter} from 'src/contracts/facilitators/flashMinter/UsdxlFlashMinter.sol';

import {Gsm} from 'src/contracts/facilitators/gsm/Gsm.sol';
import {FixedFeeStrategy} from 'src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol';
import {FixedPriceStrategy} from 'src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol';

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import {HyperTestnetReservesConfigs} from '@hypurrfi/deployments/configs/HyperTestnetReservesConfigs.sol';

import 'forge-std/console.sol';

contract HyperTestnetUsdxlConfigs is HyperTestnetReservesConfigs, Constants {

  IUsdxlToken usdxlToken;
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

    usdxlToken = IUsdxlToken(tokens[0]);

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

    usdxlToken = _getUsdxlToken();
    
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
    address token
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

    // IDefaultInterestRateStrategy.InterestRateData memory rateData = IDefaultInterestRateStrategy.InterestRateData({
    //   optimalUsageRatio: uint16(80_00),
    //   baseVariableBorrowRate: uint32(1_00),
    //   variableRateSlope1: uint32(4_00),
    //   variableRateSlope2: uint32(60_00)
    // });

    // inputs[0] = ConfiguratorInputTypes.InitReserveInput({
    //   aTokenImpl: address(usdxlAToken), // Address of the aToken implementation
    //   variableDebtTokenImpl: address(usdxlVariableDebtToken), // Address of the variable debt token implementation
    //   useVirtualBalance: false, // true for all normal assets and should be false only in special cases (ex. USDXL) where an asset is minted instead of supplied.
    //   interestRateStrategyAddress: deployRegistry.defaultInterestRateStrategy, // Address of the interest rate strategy
    //   underlyingAsset: usdxlToken, // USDXL address
    //   treasury: deployRegistry.treasury, // Address of the treasury
    //   incentivesController: deployRegistry.rewardsControllerProxy, // Address of the incentives controller
    //   aTokenName: 'USDXL ',
    //   aTokenSymbol: 'awUSDXL',
    //   variableDebtTokenName: 'Test USDXL Variable Debt Aave',
    //   variableDebtTokenSymbol: 'variableDebtTestUSDXL',
    //   params: bytes('0x10'), // Additional parameters for initialization
    //   interestRateData: abi.encode(rateData)
    // });

    IERC20Metadata tokenMetadata = IERC20Metadata(token);

    inputs[0] = ConfiguratorInputTypes.InitReserveInput({
      aTokenImpl: address(usdxlAToken), // Address of the aToken implementation
      stableDebtTokenImpl: address(deployRegistry.disabledStableDebtTokenImpl), // Disabled - not using stable debt in this implementation
      variableDebtTokenImpl: address(usdxlVariableDebtToken), // Address of the variable debt token implementation
      underlyingAssetDecimals: tokenMetadata.decimals(),
      interestRateStrategyAddress: deployRegistry.defaultInterestRateStrategy, // Address of the interest rate strategy
      underlyingAsset: address(token), // Address of the underlying asset
      treasury: deployRegistry.treasury, // Address of the treasury
      incentivesController: deployRegistry.incentives, // Address of the incentives controller
      aTokenName: string(abi.encodePacked(tokenMetadata.symbol(), " Hypurr")),
      aTokenSymbol: string(abi.encodePacked("hy", tokenMetadata.symbol())),
      variableDebtTokenName: string(abi.encodePacked(tokenMetadata.symbol(), " Variable Debt Hypurr")),
      variableDebtTokenSymbol: string(abi.encodePacked("variableDebt", tokenMetadata.symbol())),
      stableDebtTokenName: "", // Empty as stable debt is disabled
      stableDebtTokenSymbol: "", // Empty as stable debt is disabled
      params: bytes("") // Additional parameters for initialization
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
    // pull aToken proxy from reserves config
    _getUsdxlToken().addFacilitator(
      address(_getUsdxlATokenProxy()),
      'Aave V3 Hyper Testnet Market', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _addUsdxlFlashMinterAsEntity(
    address[] memory tokens
  )
    internal
  {
    UsdxlFlashMinter usdxlFlashMinter = new UsdxlFlashMinter(
      address(_getUsdxlToken()), // USDXL token
      deployRegistry.treasury, // TreasuryProxy
      0, // fee in bips for flash-minting (covered on repay)
      deployRegistry.poolAddressesProvider // PoolAddressesProvider
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
    usdxlAToken.updateUsdxlTreasury(deployRegistry.treasury);

    UsdxlAToken(_getUsdxlATokenProxy()).setVariableDebtToken(_getUsdxlVariableDebtToken());

    //set aToken
    UsdxlVariableDebtToken(_getUsdxlVariableDebtToken()).setAToken(_getUsdxlATokenProxy());
  }

  function _setDiscountTokenAndStrategy(
    address discountRateStrategy,
    address discountToken
  )
    internal
  {
    usdxlVariableDebtToken = UsdxlVariableDebtToken(_getUsdxlVariableDebtToken());
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

  function _launchGsm(
    address token,
    address gsmOwner
  )
    internal
  {
    FixedPriceStrategy fixedPriceStrategy = new FixedPriceStrategy(
      DEFAULT_FIXED_PRICE,
      address(token),
      ERC20(token).decimals()
    );
    FixedFeeStrategy fixedFeeStrategy = new FixedFeeStrategy(
      0.02e4, // 2% for buys
      0  // 0% for sells
    );

    Gsm gsm = new Gsm(
      address(_getUsdxlToken()),
      address(token),
      address(fixedPriceStrategy)
    );

    AdminUpgradeabilityProxy gsmProxy = new AdminUpgradeabilityProxy(
      address(gsm),
      address(0), //TODO: set admin to timelock
      ''
    );

    Gsm usdxlGsm = Gsm(address(gsmProxy));

    usdxlGsm.initialize(
      gsmOwner,
      deployRegistry.treasury,
      uint128(
        8_000_000 * 
        (10 ** ERC20(token).decimals())
      )
    );
  }

  function _getUsdxlToken()
    internal
    view
    returns (
      IUsdxlToken
    )
  {
    if (address(usdxlToken) != address(0))
      return IUsdxlToken(address(usdxlToken));
    return IUsdxlToken(address(0x9edA7E43821EedFb677A69066529F16DB3A2dD73));
  }

  function _getUsdxlATokenProxy()
    internal
    view
    returns (
      address
    )
  {
    // read from reserves config
    return _getPoolInstance().getReserveData(address(usdxlToken)).aTokenAddress;
  }

  function _getUsdxlVariableDebtToken()
    internal
    view
    returns (
      address 
    )
  {
    // read from reserves config
    return _getPoolInstance().getReserveData(address(usdxlToken)).variableDebtTokenAddress;
  }
}
