// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GsmWithHyFiPool} from "src/contracts/facilitators/gsm/GsmWithHyFiPool.sol";
import {GsmWithHyFiPoolV2} from "src/contracts/facilitators/gsm/GsmWithHyFiPoolV2.sol";
import {Gsm} from "src/contracts/facilitators/gsm/Gsm.sol";
import {FixedPriceStrategy} from "src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IUsdxlToken} from "src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IGsmFeeStrategy} from "src/contracts/facilitators/gsm/feeStrategy/interfaces/IGsmFeeStrategy.sol";
import {WhalesTestBase, IStaticATokenLM} from "src/test/base/WhalesTestBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IGsmStructs} from "src/contracts/facilitators/gsm/interfaces/IGsmStructs.sol";
import {MockGluexRouter} from "src/test/mocks/gluex/MockGluexRouter.sol";

contract TestGsmWithHyFiPoolUpgradeV2 is WhalesTestBase {
    // HyperEVM Aave V3 addresses
    address constant AAVE_V3_POOL = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    address constant AAVE_V3_POOL_ADDRESSES_PROVIDER = 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594;
    address constant AAVE_V3_PRICE_ORACLE = 0x9BE2ac1ff80950DCeb816842834930887249d9A8;

    // Balancer addresses
    address constant BALANCER_ROUTER = 0xA8920455934Da4D853faac1f94Fe7bEf72943eF1;
    address constant BALANCER_GYRO_POOL = 0x7029f8637a9DcF42f7aEEB1461f059e3cad0A119;
    address constant BALANCER_WEIGHTED_POOL = 0x779e573851d184707FC92D637570Db28AD14637F;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // GlueX addresses
    address public GLUEX_ROUTER;

    // Old deployments
    GsmWithHyFiPool constant oldGsmProxy = GsmWithHyFiPool(0xcb17105F6A7A75D1F1C91317a4621d9AaAfe96Fd);
    GsmWithHyFiPool constant oldGsmImpl = GsmWithHyFiPool(0x66705fBe2D859F3A5f968dD3FFB4aaFc5cAAd5f2);
    ProxyAdmin constant oldProxyAdmin = ProxyAdmin(0x582668B6AA564Bdb6380d5c4f80A59C49C65cA83);
    FixedPriceStrategy constant oldPriceStrategy = FixedPriceStrategy(0x617607aFAAf5ad91978CeC822157447B56368af3);
    FixedFeeStrategy constant oldFeeStrategy = FixedFeeStrategy(0x19673ba9e4Cb592E41aECb1b087e2b0eE9c70639);

    // New deployments
    GsmWithHyFiPoolV2 public newGsmImpl;
    GsmWithHyFiPoolV2 public upgradedGsm;
    FixedPriceStrategy public newPriceStrategy;
    FixedFeeStrategy public newFeeStrategy;
    TransparentUpgradeableProxy public newGsmProxy;
    ProxyAdmin public newProxyAdmin;

    // Shared state
    uint256 oldTotalDepositedInHyFiPool;
    uint256 oldHarvestableUnderlyingBalance;
    address hyToken;

    // Test users
    address admin = 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb;
    address user1 = makeAddr("user");
    address user2 = makeAddr("user2");

    function setUp() public {
        // Fork Ethereum mainnet
        vm.createSelectFork("mainnet", 20085575);
        
        vm.startPrank(user1);

        console2.log('deploying new GsmWithHyFiPoolV2');

        GLUEX_ROUTER = address(new MockGluexRouter());
        console2.log('GLUEX_ROUTER address:', GLUEX_ROUTER);

        newGsmImpl = new GsmWithHyFiPoolV2(
            USDXL,
            USDT0,
            oldGsmProxy.PRICE_STRATEGY(),
            AAVE_V3_POOL_ADDRESSES_PROVIDER,
            BALANCER_ROUTER,
            PERMIT2,
            GLUEX_ROUTER
        );

        console2.log('newGsmImpl address:', address(newGsmImpl));
        
        vm.stopPrank();

        vm.prank(admin);
        // TransparentUpgradeableProxy(payable(address(oldGsmProxy))).changeAdmin(address(oldProxyAdmin)); ///////

       oldProxyAdmin.getProxyAdmin(TransparentUpgradeableProxy(payable(address(oldGsmProxy))));

       oldProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(oldGsmProxy))));
        
        vm.stopPrank();
    }

    function testUpgrade() public {
        // Get old GSM state before upgrade
        address oldTreasury = oldGsmProxy.getUsdxlTreasury();
        uint128 oldExposureCap = oldGsmProxy.getExposureCap();
        uint256 oldRevision = oldGsmProxy.GSM_REVISION();
        oldTotalDepositedInHyFiPool = oldGsmProxy.totalDepositedInHyFiPool();
        oldHarvestableUnderlyingBalance = oldGsmProxy.getHarvestableUnderlyingBalance();
        bool initialFrozenState = oldGsmProxy.getIsFrozen();

        // oldProxyAdmin.getProxyAdmin(TransparentUpgradeableProxy(payable(address(oldGsmProxy))));

        bytes memory initializeData = abi.encodeWithSelector(
            newGsmImpl.initializeWithPool.selector,
            address(0),
            address(0),
            0,
            address(0)
        );

        console2.log("initializeData:");
        console2.logBytes(initializeData);

        vm.prank(admin);
        oldProxyAdmin.upgradeAndCall(TransparentUpgradeableProxy(payable(address(oldGsmProxy))), address(newGsmImpl), initializeData);

        // Cast proxy to new implementation
        upgradedGsm = GsmWithHyFiPoolV2(address(oldGsmProxy));
        hyToken = address(upgradedGsm.HYTOKEN());

        console2.log('gsm upgraded to revision:', upgradedGsm.GSM_REVISION());

        newFeeStrategy = new FixedFeeStrategy(200, 0);

        vm.startPrank(admin);
        upgradedGsm.grantRole(upgradedGsm.CONFIGURATOR_ROLE(), admin);
        upgradedGsm.updateFeeStrategy(address(newFeeStrategy));
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(oldRevision, 2, "Old GSM revision should be 2");
        assertEq(upgradedGsm.GSM_REVISION(), 3, "GSM revision should be 3 after upgrade");
        assertEq(upgradedGsm.getUsdxlTreasury(), oldTreasury, "Treasury should be preserved");
        assertEq(upgradedGsm.getExposureCap(), oldExposureCap, "Exposure cap should be preserved");
        assertEq(upgradedGsm.getFeeStrategy(), address(oldGsmProxy.getFeeStrategy()), "Fee strategy should be preserved");
        assertEq(upgradedGsm.USDXL_TOKEN(), USDXL, "USDXL token should be preserved");
        assertEq(upgradedGsm.UNDERLYING_ASSET(), USDT0, "Underlying asset should be preserved");
        assertEq(upgradedGsm.PRICE_STRATEGY(), address(oldGsmProxy.PRICE_STRATEGY()), "Price strategy should be preserved");
        assertEq(IGsmFeeStrategy(upgradedGsm.getFeeStrategy()).getSellFee(100e6), 0, "Sell fee should be preserved");
        assertEq(IGsmFeeStrategy(oldFeeStrategy).getBuyFee(100e6), 1e6, "Buy fee should be preserved");
        assertEq(IGsmFeeStrategy(upgradedGsm.getFeeStrategy()).getBuyFee(100e6), 2e6, "Buy fee should be updated");
        assertTrue(upgradedGsm.getIsFrozen() == initialFrozenState, "Frozen state should be preserved");
       
        // Verify new functionality is available
        assertTrue(address(upgradedGsm.HYFI_POOL()) == AAVE_V3_POOL, "HyFi pool should be initialized");
        assertTrue(address(upgradedGsm.HYTOKEN()) == IPool(AAVE_V3_POOL).getReserveData(USDT0).aTokenAddress, "HyToken should be initialized");
        assertTrue(address(upgradedGsm.HYFI_ADDRESSES_PROVIDER()) == AAVE_V3_POOL_ADDRESSES_PROVIDER, "Aave addresses provider should match");

        // verify pool deposit
        assertEq(upgradedGsm.getTotalDepositedInHyFiPool(), oldTotalDepositedInHyFiPool, "Total deposited in HyFi Pool should not change");
        assertEq(upgradedGsm.getHyFiPoolAvailableLiquidity(), oldTotalDepositedInHyFiPool, "HyFi pool available liquidity should be initial USDT0 balance");
        assertEq(upgradedGsm.getAvailableUnderlying(), oldTotalDepositedInHyFiPool, "Available underlying should be initial USDT0 balance");
        assertEq(upgradedGsm.getAvailableUnderlyingViaHyAsset()  - upgradedGsm.getHarvestableUnderlyingBalance(), oldTotalDepositedInHyFiPool, "Available underlying via HyAsset should be initial USDT0 balance");
        assertEq(upgradedGsm.getHarvestableUnderlyingBalance(), oldHarvestableUnderlyingBalance, "Harvestable underlying balance should not change");
        assertEq(upgradedGsm.getTotalUnderlying(), oldTotalDepositedInHyFiPool, "Total underlying should be initial USDT0 balance");
        
        (uint256 underlying, uint256 underlyingViaHyAsset) = upgradedGsm.getBuyLiquidity();
        assertEq(underlying, oldTotalDepositedInHyFiPool, "Underlying should be initial USDT0 balance");
        assertEq(underlyingViaHyAsset - upgradedGsm.getHarvestableUnderlyingBalance(), oldTotalDepositedInHyFiPool, "Underlying via HyAsset should be initial USDT0 balance");
    }

    function testGsmBuyBefore() public {
        vm.startPrank(admin);

        uint256 usdt0Amount = 100e6;
        uint256 buyAmount = 100e18;
        uint256 buyFee = IGsmFeeStrategy(oldGsmProxy.getFeeStrategy()).getBuyFee(buyAmount);

        // Fund user with USDXL for testing
        fundAccount(USDXL, user1, buyAmount + buyFee);

        console2.log("User1 USDXL balance:", IERC20(USDXL).balanceOf(user1));

        // Test buy asset functionality
        vm.startPrank(user1);
        IERC20(USDXL).approve(address(oldGsmProxy), buyAmount + buyFee);
        (uint256 assetAmount, uint256 usdxlSold) = oldGsmProxy.buyAsset(usdt0Amount, user1);
        
        assertTrue(assetAmount == usdt0Amount, "Should receive underlying asset");
        assertTrue(usdxlSold == buyAmount + buyFee, "Should sell USDXL");

        vm.stopPrank();

        console2.log("Basic GSM functionality verified after upgrade");
        console2.log("Asset amount received:", assetAmount);
        console2.log("USDXL sold:", usdxlSold);
    }

    function testGsmBuyAfter() public {
        // First perform the upgrade
        testUpgrade();

        testGsmBuyBefore();
    }

    function testGsmSellBefore() public {
        vm.startPrank(admin);

        uint256 usdxlAmount = 100e18;
        uint256 sellAmount = 100e6;
        //uint256 sellFee = IGsmFeeStrategy(oldGsmProxy.getFeeStrategy()).getSellFee(sellAmount);

        // Fund user with USDT0 for testing
        fundAccount(USDT0, user1, sellAmount);

        // Test sell asset functionality
        vm.startPrank(user1);
        IERC20(USDT0).approve(address(oldGsmProxy), sellAmount);
        (uint256 assetAmount, uint256 ghoBought) = oldGsmProxy.sellAsset(sellAmount, user1);
        
        assertTrue(assetAmount == sellAmount, "Should sell underlying asset");
        assertTrue(ghoBought == usdxlAmount, "Should buy GHO");

        vm.stopPrank();

        console2.log("Basic GSM functionality verified after upgrade");
        console2.log("Asset amount sold:", assetAmount);
        console2.log("GHO bought:", ghoBought);
    }

    function testGsmSellAfter() public {
        // First perform the upgrade
        testUpgrade();

        testGsmSellBefore();
    }

    function testGsmBuyHyBefore() public {
        vm.expectRevert();
        GsmWithHyFiPool(address(oldGsmProxy)).buyHyAsset(100e6, user1);
    }

    function testGsmBuyHyAfter() public {
        testUpgrade();

        vm.startPrank(admin);

        uint256 usdt0Amount = 100e6;
        uint256 buyAmount = 100e18;
        uint256 buyFee = IGsmFeeStrategy(oldGsmProxy.getFeeStrategy()).getBuyFee(buyAmount);

        // Fund user with USDXL for testing
        fundAccount(USDXL, user1, buyAmount + buyFee);

        console2.log("User1 USDXL balance:", IERC20(USDXL).balanceOf(user1));

        // Test buy asset functionality
        vm.startPrank(user1);
        IERC20(USDXL).approve(address(oldGsmProxy), buyAmount + buyFee);
        (uint256 assetAmount, uint256 usdxlSold) = GsmWithHyFiPool(address(oldGsmProxy)).buyHyAsset(usdt0Amount, user1);
        
        assertTrue(assetAmount == usdt0Amount, "Should receive underlying asset");
        assertTrue(usdxlSold == buyAmount + buyFee, "Should sell USDXL");
        assertEq(upgradedGsm.getTotalDepositedInHyFiPool(), oldTotalDepositedInHyFiPool - usdt0Amount, "Total deposited in HyFi Pool should be initial USDT0 balance minus the amount bought");
        assertEq(IERC20(hyToken).balanceOf(address(user1)), usdt0Amount, "HyToken balance should be the amount bought");
        assertEq(IERC20(hyToken).balanceOf(address(oldGsmProxy)) - oldHarvestableUnderlyingBalance - 1, oldTotalDepositedInHyFiPool - usdt0Amount, "HyToken balance should be the initial USDT0 balance minus the amount bought");
        assertEq(IERC20(USDT0).balanceOf(address(oldGsmProxy)), 0, "USDT0 balance should be zero");
        assertEq(IERC20(USDT0).balanceOf(address(user1)), 0, "USDT0 balance should be zero");

        vm.stopPrank();

        console2.log("Basic GSM functionality verified after upgrade");
        console2.log("Asset amount received:", assetAmount);
        console2.log("USDXL sold:", usdxlSold);
    }

    function testGsmSeizeBefore() public {
        assertEq(oldGsmProxy.getIsSeized(), false, "GSM should not be seized");

        uint256 initialUsdt0Balance = IERC20(USDT0).balanceOf(admin);
        vm.startPrank(admin);
        oldGsmProxy.grantRole(oldGsmProxy.LIQUIDATOR_ROLE(), admin);
        oldGsmProxy.seize();
        vm.stopPrank();

        assertEq(IERC20(USDT0).balanceOf(admin), initialUsdt0Balance, "USDT0 balance should be the initial USDT0 balance");
        assertEq(IERC20(USDT0).balanceOf(address(oldGsmProxy)), 0, "USDT0 balance should be zero");

        assertEq(oldGsmProxy.getIsSeized(), true, "GSM should be seized");
    }

    function testGsmSeizeAfter() public {
        testUpgrade();

        testGsmSeizeBefore();
    }

    function testUpgradeGyroPool() public {
        testUpgrade();

        vm.startPrank(admin);

        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);
        upgradedGsm.updateBalancerPool(BALANCER_GYRO_POOL);
        assertEq(upgradedGsm.getBalancerPool(), BALANCER_GYRO_POOL, "Balancer pool should be updated");
        IAccessControl(address(upgradedGsm)).revokeRole(upgradedGsm.HARVESTER_ROLE(), admin);
        
        vm.stopPrank();
    }

    function testUpgradeWeightedPool() public {
        testUpgrade();

        vm.startPrank(admin);

        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);
        upgradedGsm.updateBalancerPool(BALANCER_WEIGHTED_POOL);
        assertEq(upgradedGsm.getBalancerPool(), BALANCER_WEIGHTED_POOL, "Balancer pool should be updated");
        IAccessControl(address(upgradedGsm)).revokeRole(upgradedGsm.HARVESTER_ROLE(), admin);
        
        vm.stopPrank();
    }

    function testCalculateSwapAmountsGyroPool(uint256 harvestAmount) public returns (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) {
        testUpgradeGyroPool();

        (tokenIn, tokensOut, amountsIn) = upgradedGsm.calculateSwapAmounts(harvestAmount);
        console2.log('tokenIn:', tokenIn);
        for (uint256 i = 0; i < tokensOut.length; i++) {
            console2.log('tokensOut[i]:', tokensOut[i]);
            console2.log('amountsIn[i]:', amountsIn[i]);
        }

        return (tokenIn, tokensOut, amountsIn);
    }

    function testCalculateSwapAmountsWeightedPool(uint256 harvestAmount) public returns (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) {
        testUpgradeWeightedPool();

        (tokenIn, tokensOut, amountsIn) = upgradedGsm.calculateSwapAmounts(harvestAmount);
        console2.log('tokenIn:', tokenIn);
        for (uint256 i = 0; i < tokensOut.length; i++) {
            console2.log('tokensOut[i]:', tokensOut[i]);
            console2.log('amountsIn[i]:', amountsIn[i]);
        }

        return (tokenIn, tokensOut, amountsIn);
    }

    function testHarvestLiquidityFullHarvestGyroPool() public {
        (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) = testCalculateSwapAmountsGyroPool(type(uint256).max);

        assertEq(tokenIn, USDT0);
        assertEq(tokensOut.length, 2);
        assertEq(tokensOut[0], 0x3Df418bE6Dad3f824d00A7c516DAd3Ea2A5a79C6);
        assertEq(tokensOut[1], 0xca79db4B49f608eF54a5CB813FbEd3a6387bC645);
        assertEq(amountsIn.length, 2);
        assertEq(amountsIn[0], 8510101406);
        assertEq(amountsIn[1], 997);

        uint256[] memory minAmountOuts = new uint256[](tokensOut.length);
        minAmountOuts[0] = 198728119522562594116;
        minAmountOuts[1] = 79105356360482821617;

        IGsmStructs.SwapParams[] memory swapParams = new IGsmStructs.SwapParams[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; i++) {
            swapParams[i] = IGsmStructs.SwapParams({
                swapData: bytes(""),
                sellToken: tokenIn,
                buyToken: tokensOut[i],
                maxAmountIn: amountsIn[i],
                minAmountOut: 0
            });
            console2.log('gluex router address:', GLUEX_ROUTER);
            console2.log('before encodeGluexCalldata');
            swapParams[i].swapData = MockGluexRouter(payable(GLUEX_ROUTER)).encodeGluexCalldata(tokenIn, tokensOut[i], amountsIn[i], minAmountOuts[i]);
            console2.log('after encodeGluexCalldata');
            (bool success, ) = fundAccount(tokensOut[i], GLUEX_ROUTER, minAmountOuts[i]);
            assertTrue(success, "Funding GLUEX_ROUTER failed");
        }
        // adjust for shares minted
        swapParams[0].swapData = MockGluexRouter(payable(GLUEX_ROUTER)).encodeGluexCalldata(tokenIn, tokensOut[0], amountsIn[0], IStaticATokenLM(STAT_HY_WHYPE).convertToShares(minAmountOuts[0]));
        minAmountOuts[0] = IStaticATokenLM(STAT_HY_WHYPE).convertToShares(minAmountOuts[0]);
        vm.startPrank(admin);

        uint256 minBptAmountOut = upgradedGsm.calculateBptAmountOut(minAmountOuts);
        console2.log('minBptAmountOut:', minBptAmountOut);
        
        vm.expectRevert('AccessControl: account 0xc2b3075fb1ac9f5ecc1e2c07da8bccc43e7083fb is missing role 0x3fc733b4d20d27a28452ddf0e9351aced28242fe03389a653cdb783955316b9b');
        upgradedGsm.harvestLiquidity(swapParams);

        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);
        upgradedGsm.harvestLiquidity(swapParams);
        
        vm.stopPrank();
    }

    function testHarvestLiquiditySmallAmountGyroPool() public {
        (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) = testCalculateSwapAmountsGyroPool(1e4);

        uint256[] memory minAmountOuts = new uint256[](tokensOut.length);
        minAmountOuts[0] = 305760356788316; // amount in WHYPE for stathyWHYPE
        minAmountOuts[1] = 9119938589831; // USDXL dust

        IGsmStructs.SwapParams[] memory swapParams = new IGsmStructs.SwapParams[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; i++) {
            swapParams[i] = IGsmStructs.SwapParams({
                swapData: bytes(""),
                sellToken: tokenIn,
                buyToken: tokensOut[i],
                maxAmountIn: amountsIn[i],
                minAmountOut: 0
            });
            console2.log('tokenOut:', tokensOut[i]);
            console2.log('amountIn:', amountsIn[i]);
            console2.log('minAmountOut:', minAmountOuts[i]);
            if (minAmountOuts[i] == 0) {
                continue;
            }
            swapParams[i].swapData = MockGluexRouter(payable(GLUEX_ROUTER)).encodeGluexCalldata(tokenIn, tokensOut[i], amountsIn[i], minAmountOuts[i]);
            (bool success, ) = fundAccount(tokensOut[i], GLUEX_ROUTER, minAmountOuts[i]);
            assertTrue(success, "Funding GLUEX_ROUTER failed");
        }
        // adjust for shares minted
        swapParams[0].swapData = MockGluexRouter(payable(GLUEX_ROUTER)).encodeGluexCalldata(tokenIn, tokensOut[0], amountsIn[0], IStaticATokenLM(STAT_HY_WHYPE).convertToShares(minAmountOuts[0]));
        minAmountOuts[0] = IStaticATokenLM(STAT_HY_WHYPE).convertToShares(minAmountOuts[0]);
        vm.startPrank(admin);

        uint256 minBptAmountOut = upgradedGsm.calculateBptAmountOut(minAmountOuts);
        console2.log('minBptAmountOut:', minBptAmountOut);

        // return;

        (address token, uint256 amountInRaw, uint256 amountInMax) = abi.decode(hex"000000000000000000000000ca79db4b49f608ef54a5cb813fbed3a6387bc64500000000000000000000000000000000000000000000000000000000021c707d0000000000000000000000000000000000000000000000000000000000000000", (address, uint256, uint256));
        console2.log('token:', token);
        console2.log('amountInRaw:', amountInRaw);
        console2.log('amountInMax:', amountInMax);
        // return;

        vm.expectRevert('AccessControl: account 0xc2b3075fb1ac9f5ecc1e2c07da8bccc43e7083fb is missing role 0x3fc733b4d20d27a28452ddf0e9351aced28242fe03389a653cdb783955316b9b');
        upgradedGsm.harvestLiquidity(swapParams);

        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);
        upgradedGsm.harvestLiquidity(swapParams);
        
        vm.stopPrank();
    } 

    function testHarvestLiquiditySmallAmountWeightedPool() public {
        (address tokenIn, address[] memory tokensOut, uint256[] memory amountsIn) = testCalculateSwapAmountsWeightedPool(1e4);

        uint256[] memory minAmountOuts = new uint256[](tokensOut.length);
        minAmountOuts[0] = 305760356788316; // amount in WHYPE for stathyWHYPE
        minAmountOuts[1] = 9119938589831; // USDXL dust

        IGsmStructs.SwapParams[] memory swapParams = new IGsmStructs.SwapParams[](tokensOut.length);
        for (uint256 i = 0; i < tokensOut.length; i++) {
            swapParams[i] = IGsmStructs.SwapParams({
                swapData: bytes(""),
                sellToken: tokenIn,
                buyToken: tokensOut[i],
                maxAmountIn: amountsIn[i],
                minAmountOut: 0
            });
            console2.log('tokenOut:', tokensOut[i]);
            console2.log('amountIn:', amountsIn[i]);
            console2.log('minAmountOut:', minAmountOuts[i]);
            if (minAmountOuts[i] == 0) {
                continue;
            }
            swapParams[i].swapData = MockGluexRouter(payable(GLUEX_ROUTER)).encodeGluexCalldata(tokenIn, tokensOut[i], amountsIn[i], minAmountOuts[i]);
            (bool success, ) = fundAccount(tokensOut[i], GLUEX_ROUTER, minAmountOuts[i]);
            assertTrue(success, "Funding GLUEX_ROUTER failed");
        }
        // adjust for shares minted
        swapParams[0].swapData = MockGluexRouter(payable(GLUEX_ROUTER)).encodeGluexCalldata(tokenIn, tokensOut[0], amountsIn[0], IStaticATokenLM(STAT_HY_WHYPE).convertToShares(minAmountOuts[0]));
        minAmountOuts[0] = IStaticATokenLM(STAT_HY_WHYPE).convertToShares(minAmountOuts[0]);
        vm.startPrank(admin);

        uint256 minBptAmountOut = upgradedGsm.calculateBptAmountOut(minAmountOuts);
        console2.log('minBptAmountOut:', minBptAmountOut);

        vm.expectRevert('AccessControl: account 0xc2b3075fb1ac9f5ecc1e2c07da8bccc43e7083fb is missing role 0x3fc733b4d20d27a28452ddf0e9351aced28242fe03389a653cdb783955316b9b');
        upgradedGsm.harvestLiquidity(swapParams);

        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);
        upgradedGsm.harvestLiquidity(swapParams);
        
        vm.stopPrank();
    } 

    function testHarvestLiquidityZeroAddressBalancerPool() public {
        testUpgrade();

        vm.startPrank(admin);

        // should fail to update pool w/o harvester role
        vm.expectRevert('AccessControl: account 0xc2b3075fb1ac9f5ecc1e2c07da8bccc43e7083fb is missing role 0x3fc733b4d20d27a28452ddf0e9351aced28242fe03389a653cdb783955316b9b');
        upgradedGsm.updateBalancerPool(BALANCER_GYRO_POOL);

        // grant role
        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);

        // update to non-contract address
        vm.expectRevert('INVALID_BALANCER_POOL');
        upgradedGsm.updateBalancerPool(user1);

        // update to invalid balancer pool
        vm.expectRevert('INVALID_BALANCER_POOL');
        upgradedGsm.updateBalancerPool(address(upgradedGsm));

        vm.stopPrank();
    }

    function testOnlyValidPoolModifier() public {
        testUpgrade();

        vm.startPrank(admin);

        // should fail to update pool w/o harvester role
        vm.expectRevert('INVALID_POOL');
        upgradedGsm.calculateSwapAmounts(1e4);

        vm.expectRevert('INVALID_POOL');
        upgradedGsm.calculateBptAmountOut(new uint256[](1));

        IAccessControl(address(upgradedGsm)).grantRole(upgradedGsm.HARVESTER_ROLE(), admin);
        vm.expectRevert('INVALID_POOL');
        upgradedGsm.harvestLiquidity(new IGsmStructs.SwapParams[](1));

        vm.stopPrank();
    }
}
