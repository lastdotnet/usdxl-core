// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {stdJson} from "forge-std/StdJson.sol";
import {DeployUsdxlFileUtils} from "src/deployments/utils/DeployUsdxlFileUtils.sol";
import {VmSafe} from "forge-std/Vm.sol";

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
import {IUsdxlConfigsTypes} from "src/deployments/interfaces/IUsdxlConfigsTypes.sol";

import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {AdminUpgradeabilityProxy} from
    "@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol";
import {IDeployConfigTypes} from "@hypurrfi/deployments/interfaces/IDeployConfigTypes.sol";
import {DeployHyFiUtils} from "@hypurrfi/deployments/utils/DeployHyFiUtils.sol";
import {IERC20Metadata} from "@hypurrfi/contracts/dependencies/openzeppelin/interfaces/IERC20Metadata.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolConfigurator} from "@aave/core-v3/contracts/interfaces/IPoolConfigurator.sol";
import {HyFiOracle} from "@hypurrfi/core/contracts/misc/HyFiOracle.sol";
import {ConfiguratorInputTypes} from "@aave/core-v3/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ZeroDiscountRateStrategy} from "src/contracts/facilitators/hyfi/interestStrategy/ZeroDiscountRateStrategy.sol";
import {console2} from "forge-std/console2.sol";

abstract contract DeployUsdxlUtils is DeployHyFiUtils, IUsdxlConfigsTypes {
    using DeployUsdxlFileUtils for string;
    using stdJson for string;

    string usdxlConfig;

    IUsdxlToken public usdxlToken;
    UsdxlAToken public usdxlAToken;
    address public usdxlTokenProxy;
    UsdxlVariableDebtToken public usdxlVariableDebtToken;
    UsdxlOracle public usdxlOracle;
    UsdxlInterestRateStrategy public usdxlInterestRateStrategy;
    UsdxlFlashMinter public flashMinter;
    UsdxlDeployRegistry public usdxlDeployRegistry;
    IDeployConfigTypes.HypurrDeployRegistry hypurrDeployRegistry;
    UpgradeableUsdxlToken public usdxlTokenImpl;

    function _deployUsdxl() internal {
        address[] memory tokens = new address[](1);
        address[] memory oracles = new address[](1);

        // 1. Deploy USDXL token implementation and proxy
        usdxlTokenImpl = new UpgradeableUsdxlToken();

        {
            bytes memory initParams = abi.encodeWithSignature("initialize(address)", deployer);

            usdxlTokenProxy = address(
                new TransparentUpgradeableProxy(
                    address(usdxlTokenImpl), usdxlConfig.readAddress(".usdxlAdmin"), initParams
                )
            );
        }

        usdxlToken = IUsdxlToken(usdxlTokenProxy);

        tokens[0] = address(usdxlToken);

        // 2. Deploy USDXL Oracle
        usdxlOracle = new UsdxlOracle();

        oracles[0] = address(usdxlOracle);

        // 3. Deploy USDXL Interest Rate Strategy
        usdxlInterestRateStrategy = new UsdxlInterestRateStrategy(
            hypurrDeployRegistry.poolAddressesProvider,
            usdxlConfig.readUint(".usdxlBorrowRate") // 0.02e27 is 2%
        );

        // 4. Deploy USDXL AToken and Variable Debt Token
        usdxlAToken =
            new UsdxlAToken(IPool(IPoolAddressesProvider(hypurrDeployRegistry.poolAddressesProvider).getPool()));

        usdxlVariableDebtToken = new UsdxlVariableDebtToken(
            IPool(IPoolAddressesProvider(hypurrDeployRegistry.poolAddressesProvider).getPool())
        );

        // 5. Deploy Flash Minter
        flashMinter = new UsdxlFlashMinter(
            address(usdxlToken),
            hypurrDeployRegistry.treasury,
            usdxlConfig.readUint(".usdxlFlashMinterFee"), // 100 is 1%
            hypurrDeployRegistry.poolAddressesProvider
        );

        // 6. Grant facilitator manager role
        _grantFacilitatorManagerRole(deployer);

        // 7. Set USDXL Oracle
        _setUsdxlOracle(tokens, oracles);

        // 8. Set reserve config
        _initializeUsdxlReserve(tokens[0]);

        // 9. Disable stable debt
        _disableStableDebt(tokens);

        // 10. Enable USDXL borrowing
        _enableUsdxlBorrowing();

        // 11. Add USDXL as entity
        _addUsdxlATokenAsEntity();

        // 12. Add USDXL flashminter as entity
        _addUsdxlFlashMinterAsEntity();

        // 13. Revoke facilitator manager role
        _revokeFacilitatorManagerRole(deployer);

        // 14. Set USDXL addresses
        _setUsdxlAddresses();

        ERC20 nonMintableErc20;

        nonMintableErc20 = new ERC20("Discount Token", "DSCNT");

        ZeroDiscountRateStrategy discountRateStrategy;

        discountRateStrategy = new ZeroDiscountRateStrategy();

        _setDiscountTokenAndStrategy(address(discountRateStrategy), address(nonMintableErc20));

        // transfer ownership of usdxlToken to deployer
        UpgradeableUsdxlToken(usdxlTokenProxy).grantRole(
            UpgradeableUsdxlToken(usdxlTokenProxy).DEFAULT_ADMIN_ROLE(), usdxlConfig.readAddress(".usdxlAdmin")
        );
        if (usdxlConfig.readAddress(".usdxlAdmin") != deployer) {
            UpgradeableUsdxlToken(usdxlTokenProxy).revokeRole(
                UpgradeableUsdxlToken(usdxlTokenProxy).DEFAULT_ADMIN_ROLE(), deployer
            );
        }

        // Export contract addresses
        _exportContracts();

        _borrowUsdxl(0.0001e18, deployer);

        console2.log("usdxlToken balance: ", usdxlToken.balanceOf(deployer));

        _repayUsdxl(0.0001e18, deployer);
    }

    function _exportContracts() internal {
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlTokenImpl", address(usdxlToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlTokenProxy", usdxlTokenProxy);
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlOracle", address(usdxlOracle));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlATokenImpl", address(usdxlAToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlVariableDebtTokenImpl", address(usdxlVariableDebtToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlFlashMinterImpl", address(flashMinter));
    }

    function _setDeployRegistry(string memory deployedContracts) internal {
        hypurrDeployRegistry = IDeployConfigTypes.HypurrDeployRegistry({
            hyTokenImpl: deployedContracts.readAddress(".hyTokenImpl"),
            hyFiOracle: deployedContracts.readAddress(".hyFiOracle"),
            aclManager: deployedContracts.readAddress(".aclManager"),
            admin: deployedContracts.readAddress(".admin"),
            defaultInterestRateStrategy: deployedContracts.readAddress(".defaultInterestRateStrategy"),
            deployer: deployedContracts.readAddress(".deployer"),
            emissionManager: deployedContracts.readAddress(".emissionManager"),
            incentives: deployedContracts.readAddress(".incentives"),
            incentivesImpl: deployedContracts.readAddress(".incentivesImpl"),
            pool: deployedContracts.readAddress(".pool"),
            poolAddressesProvider: deployedContracts.readAddress(".poolAddressesProvider"),
            poolAddressesProviderRegistry: deployedContracts.readAddress(".poolAddressesProviderRegistry"),
            poolConfigurator: deployedContracts.readAddress(".poolConfigurator"),
            poolConfiguratorImpl: deployedContracts.readAddress(".poolConfiguratorImpl"),
            poolImpl: deployedContracts.readAddress(".poolImpl"),
            protocolDataProvider: deployedContracts.readAddress(".protocolDataProvider"),
            disabledStableDebtTokenImpl: deployedContracts.readAddress(".disabledStableDebtTokenImpl"),
            treasury: deployedContracts.readAddress(".treasury"),
            treasuryImpl: deployedContracts.readAddress(".treasuryImpl"),
            uiIncentiveDataProvider: deployedContracts.readAddress(".uiIncentiveDataProvider"),
            uiPoolDataProvider: deployedContracts.readAddress(".uiPoolDataProvider"),
            variableDebtTokenImpl: deployedContracts.readAddress(".variableDebtTokenImpl"),
            walletBalanceProvider: deployedContracts.readAddress(".walletBalanceProvider"),
            wrappedHypeGateway: deployedContracts.readAddress(".wrappedHypeGateway")
        });
    }

    function _deployGsm(address token, address gsmOwner, uint256 maxCapacity) internal returns (address gsmProxy) {
        // Deploy price and fee strategies
        FixedPriceStrategy fixedPriceStrategy = new FixedPriceStrategy(
            1e8, // Default price of $1.00
            address(token),
            IERC20Metadata(token).decimals()
        );

        FixedFeeStrategy fixedFeeStrategy = new FixedFeeStrategy(
            0.02e4, // 2% for buys
            0 // 0% for sells
        );

        // Deploy GSM implementation
        Gsm gsmImpl = new Gsm(address(usdxlToken), address(token), address(fixedPriceStrategy));

        // Deploy and initialize GSM proxy
        AdminUpgradeabilityProxy proxy = new AdminUpgradeabilityProxy(
            address(gsmImpl),
            address(0), // TODO: set admin to timelock
            ""
        );

        Gsm(address(proxy)).initialize(gsmOwner, hypurrDeployRegistry.treasury, uint128(maxCapacity));

        // Export contracts
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmImpl", address(gsmImpl));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmProxy", address(proxy));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmFixedPriceStrategyImpl", address(fixedPriceStrategy));
        DeployUsdxlFileUtils.exportContract(instanceId, "gsmFixedFeeStrategyImpl", address(fixedFeeStrategy));

        return address(proxy);
    }

    function _grantFacilitatorManagerRole(address deployer) internal {
        UpgradeableUsdxlToken(address(usdxlTokenProxy)).grantRole(
            UpgradeableUsdxlToken(address(usdxlTokenProxy)).FACILITATOR_MANAGER_ROLE(), deployer
        );
    }

    function _revokeFacilitatorManagerRole(address deployer) internal {
        UpgradeableUsdxlToken(address(usdxlTokenProxy)).revokeRole(
            UpgradeableUsdxlToken(address(usdxlTokenProxy)).FACILITATOR_MANAGER_ROLE(), deployer
        );
    }

    function _setUsdxlOracle(address[] memory tokens, address[] memory oracles) internal {
        // set oracles
        _getHyFiOracle().setAssetSources(tokens, oracles);
    }

    function _initializeUsdxlReserve(address token) internal {
        ConfiguratorInputTypes.InitReserveInput[] memory inputs = new ConfiguratorInputTypes.InitReserveInput[](1);

        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlATokenImpl", address(usdxlAToken));
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlVariableDebtTokenImpl", address(usdxlVariableDebtToken));

        IERC20Metadata tokenMetadata = IERC20Metadata(token);

        inputs[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl: address(usdxlAToken), // Address of the aToken implementation
            stableDebtTokenImpl: address(hypurrDeployRegistry.disabledStableDebtTokenImpl), // Disabled - not using stable debt in this implementation
            variableDebtTokenImpl: address(usdxlVariableDebtToken), // Address of the variable debt token implementation
            underlyingAssetDecimals: tokenMetadata.decimals(),
            interestRateStrategyAddress: address(usdxlInterestRateStrategy), // Address of the interest rate strategy
            underlyingAsset: address(token), // Address of the underlying asset
            treasury: hypurrDeployRegistry.treasury, // Address of the treasury
            incentivesController: hypurrDeployRegistry.incentives, // Address of the incentives controller
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
        DeployUsdxlFileUtils.exportContract(instanceId, "usdxlATokenProxy", _getUsdxlATokenProxy());
        DeployUsdxlFileUtils.exportContract(
            instanceId, "usdxlVariableDebtTokenProxy", _getUsdxlVariableDebtTokenProxy()
        );
    }

    function _disableStableDebt(address[] memory tokens) internal {
        for (uint256 i; i < tokens.length;) {
            // Disable stable borrowing
            _getPoolConfigurator().setReserveStableRateBorrowing(tokens[i], false);
            unchecked {
                i++;
            }
        }
    }

    function _updateUsdxlInterestRateStrategy() internal {
        UsdxlInterestRateStrategy interestRateStrategy =
            new UsdxlInterestRateStrategy(address(hypurrDeployRegistry.poolAddressesProvider), usdxlConfig.readUint(".usdxlBorrowRate"));

        _getPoolConfigurator().setReserveInterestRateStrategyAddress(
            address(_getUsdxlToken()), address(interestRateStrategy)
        );
    }

    function _enableUsdxlBorrowing() internal {
        _getPoolConfigurator().setReserveBorrowing(address(usdxlTokenProxy), true);
    }

    function _addUsdxlATokenAsEntity() internal {
        // pull aToken proxy from reserves config
        _getUsdxlToken().addFacilitator(
            address(_getUsdxlATokenProxy()),
            "HypurrFi Market Loans", // entity label
            1e24 // entity mint limit (1mil)
        );
    }

    function _addUsdxlFlashMinterAsEntity() internal {
        _getUsdxlToken().addFacilitator(
            address(flashMinter),
            "HypurrFi Market Flash Loans", // entity label
            1e27 // entity mint limit (1bil)
        );
    }

    function _setUsdxlAddresses() internal {
        UsdxlAToken usdxlATokenProxy = UsdxlAToken(_getUsdxlATokenProxy());
        usdxlATokenProxy.updateUsdxlTreasury(hypurrDeployRegistry.treasury);

        UsdxlAToken(_getUsdxlATokenProxy()).setVariableDebtToken(_getUsdxlVariableDebtTokenProxy());

        // set aToken
        UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy()).setAToken(_getUsdxlATokenProxy());
    }

    function _setDiscountTokenAndStrategy(address discountRateStrategy, address discountToken) internal {
        usdxlVariableDebtToken = UsdxlVariableDebtToken(_getUsdxlVariableDebtTokenProxy());
        if (discountRateStrategy != address(0)) {
            usdxlVariableDebtToken.updateDiscountRateStrategy(discountRateStrategy);
        }
        if (discountToken != address(0)) {
            usdxlVariableDebtToken.updateDiscountToken(discountToken);
        }
    }

    function _borrowUsdxl(uint256 amount, address onBehalfOf) internal {
        _getPoolInstance().borrow(
            address(_getUsdxlToken()),
            amount,
            2, // interest rate mode
            0,
            onBehalfOf
        );
    }

    function _repayUsdxl(uint256 amount, address onBehalfOf) internal {
        usdxlToken.approve(address(_getPoolInstance()), amount);
        _getPoolInstance().repay(
            address(_getUsdxlToken()),
            amount,
            2, // interest rate mode
            onBehalfOf
        );
    }

    function _supplyCollateral(address token, address user, uint256 amount) internal {
        ERC20(token).approve(address(_getPoolInstance()), amount);

        _getPoolInstance().supply(token, amount, user, 0);
    }

    function _getUsdxlToken() internal view returns (IUsdxlToken) {
        return IUsdxlToken(usdxlTokenProxy);
    }

    function _getUsdxlATokenProxy() internal view returns (address) {
        // read from reserves config
        return _getPoolInstance().getReserveData(address(usdxlToken)).aTokenAddress;
    }

    function _getUsdxlVariableDebtTokenProxy() internal view returns (address) {
        // read from reserves config
        return _getPoolInstance().getReserveData(address(usdxlToken)).variableDebtTokenAddress;
    }

    function _getHyFiOracle() internal view returns (HyFiOracle) {
        return HyFiOracle(hypurrDeployRegistry.hyFiOracle);
    }

    function _getPoolConfigurator() internal view returns (IPoolConfigurator) {
        return IPoolConfigurator(hypurrDeployRegistry.poolConfigurator);
    }

    function _getPoolAddressesProvider() internal view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(hypurrDeployRegistry.poolAddressesProvider);
    }

    function _getPoolInstance() internal view returns (IPool) {
        return IPool(hypurrDeployRegistry.pool);
    }
}
