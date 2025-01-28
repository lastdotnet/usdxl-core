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
import {UpgradeableUsdxlToken} from 'src/contracts/usdxl/UpgradeableUsdxlToken.sol';
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
import {TransparentUpgradeableProxy} from 'solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol';

import {HyperTestnetReservesConfigs} from '@hypurrfi/deployments/configs/HyperTestnetReservesConfigs.sol';
import {DeployUtils} from 'src/deployments/utils/DeployUtils.sol';

import 'forge-std/console.sol';

contract HyperTestnetUsdxlConfigs is HyperTestnetReservesConfigs, Constants {

  IUsdxlToken usdxlToken;
  UsdxlAToken usdxlAToken;
  address usdxlTokenProxy;
  UsdxlVariableDebtToken usdxlVariableDebtToken;
  string instanceIdInternal = "hypurrfi-testnet";
  
  function _deployTestnetTokens(
    address deployer,
    address proxyAdmin
  )
    internal
    returns (
        address[] memory tokens,
        address[] memory oracles
    )
  { 
    tokens  = new address[](1);

    UpgradeableUsdxlToken usdxlTokenImpl = new UpgradeableUsdxlToken();

    // proxy deploy and init
    bytes memory usdxlTokenImplParams = abi.encodeWithSignature(
      'initialize(address)',
      deployer
    );
    usdxlTokenProxy = address(new TransparentUpgradeableProxy(
      address(usdxlTokenImpl),
      proxyAdmin,
      usdxlTokenImplParams
    ));

    tokens[0] = address(usdxlTokenProxy);
  
    oracles = new address[](1);

    oracles[0] = address(new UsdxlOracle());

    usdxlToken = IUsdxlToken(tokens[0]);

    DeployUtils.exportContract(instanceIdInternal, "usdxlTokenImpl", address(usdxlTokenImpl));

    DeployUtils.exportContract(instanceIdInternal, "usdxlTokenProxy", address(usdxlTokenProxy));

    DeployUtils.exportContract(instanceIdInternal, "usdxlOracle", address(oracles[0]));

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

  function _grantFacilitatorManagerRole(
    address deployer
  )
    internal
  {
    UpgradeableUsdxlToken(address(usdxlTokenProxy)).grantRole(
        UpgradeableUsdxlToken(address(usdxlTokenProxy)).FACILITATOR_MANAGER_ROLE(),
        deployer
    );
  }

    function _revokeFacilitatorManagerRole(
    address deployer
  )
    internal
  {
    UpgradeableUsdxlToken(address(usdxlTokenProxy)).revokeRole(
        UpgradeableUsdxlToken(address(usdxlTokenProxy)).FACILITATOR_MANAGER_ROLE(),
        deployer
    );
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

  function _updateUsdxlInterestRateStrategy()
    internal
  {
    UsdxlInterestRateStrategy interestRateStrategy = new UsdxlInterestRateStrategy(
      address(deployRegistry.poolAddressesProvider),
      0.02e27
    );

    _getPoolConfigurator().setReserveInterestRateStrategyAddress(address(_getUsdxlToken()), address(interestRateStrategy));
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
    
    DeployUtils.exportContract(instanceIdInternal, "usdxlATokenImpl", address(usdxlAToken));
    DeployUtils.exportContract(instanceIdInternal, "usdxlVariableDebtTokenImpl", address(usdxlVariableDebtToken));

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

    // export contract addresses
    DeployUtils.exportContract(instanceIdInternal, "usdxlATokenProxy", _getUsdxlATokenProxy());
    DeployUtils.exportContract(instanceIdInternal, "usdxlVariableDebtTokenProxy", _getUsdxlVariableDebtTokenProxy());
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
      'HypurrFi Testnet Market Loans', // entity label
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

    DeployUtils.exportContract(instanceIdInternal, "usdxlFlashMinterImpl", address(usdxlFlashMinter));

    IUsdxlToken(tokens[0]).addFacilitator(
      address(usdxlFlashMinter),
      'HypurrFi Testnet Market Flash Loans', // entity label
      1e27 // entity mint limit (100mil)
    );
  }

  function _setUsdxlAddresses()
    internal
  {
    usdxlToken = IUsdxlToken(_getUsdxlToken());
    usdxlAToken = UsdxlAToken(_getUsdxlATokenProxy());
    usdxlAToken.updateUsdxlTreasury(deployRegistry.treasury);

    UsdxlAToken(_getUsdxlATokenProxy()).setVariableDebtToken(_getUsdxlVariableDebtTokenProxy());

    // set aToken
    UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy()).setAToken(_getUsdxlATokenProxy());

    console.log("UsdxlVariableDebtToken AToken: ", UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy()).getAToken());
    console.log("UsdxlAToken VariableDebtToken: ", UsdxlAToken(_getUsdxlATokenProxy()).getVariableDebtToken());

    console.log("UsdxlAToken Proxy: ", _getUsdxlATokenProxy());
    console.log("UsdxlVariableDebtToken Proxy: ", _getUsdxlVariableDebtTokenProxy());
  }

  function _setDiscountTokenAndStrategy(
    address discountRateStrategy,
    address discountToken
  )
    internal
  {
    usdxlVariableDebtToken = UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy());
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

    DeployUtils.exportContract(instanceIdInternal, "gsmFixedPriceStrategyImpl", address(fixedPriceStrategy));
    DeployUtils.exportContract(instanceIdInternal, "gsmFixedFeeStrategyImpl", address(fixedFeeStrategy));

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

    DeployUtils.exportContract(instanceIdInternal, "gsmImpl", address(gsm));
    DeployUtils.exportContract(instanceIdInternal, "gsmProxy", address(gsmProxy));

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
    return IUsdxlToken(usdxlTokenProxy);
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

  function _getUsdxlVariableDebtTokenProxy()
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
