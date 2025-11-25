// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GsmWithHyFiPool} from "src/contracts/facilitators/gsm/GsmWithHyFiPool.sol";
import {Gsm} from "src/contracts/facilitators/gsm/Gsm.sol";
import {FixedPriceStrategy} from "src/contracts/facilitators/gsm/priceStrategy/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "src/contracts/facilitators/gsm/feeStrategy/FixedFeeStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IUsdxlToken} from "src/contracts/usdxl/interfaces/IUsdxlToken.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IGsmFeeStrategy} from "src/contracts/facilitators/gsm/feeStrategy/interfaces/IGsmFeeStrategy.sol";
import {WhalesTestBase} from "src/test/base/WhalesTestBase.sol";

contract TestGsmWithHyFiPoolUpgrade is WhalesTestBase {
    // HyperEVM Aave V3 addresses
    address constant AAVE_V3_POOL = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    address constant AAVE_V3_POOL_ADDRESSES_PROVIDER = 0xA73ff12D177D8F1Ec938c3ba0e87D33524dD5594;
    address constant AAVE_V3_PRICE_ORACLE = 0x9BE2ac1ff80950DCeb816842834930887249d9A8;

    // Old deployments
    Gsm constant oldGsmProxy = Gsm(0xcb17105F6A7A75D1F1C91317a4621d9AaAfe96Fd);
    Gsm constant oldGsmImpl = Gsm(0x66705fBe2D859F3A5f968dD3FFB4aaFc5cAAd5f2);
    ProxyAdmin constant oldProxyAdmin = ProxyAdmin(0x582668B6AA564Bdb6380d5c4f80A59C49C65cA83);
    FixedPriceStrategy constant oldPriceStrategy = FixedPriceStrategy(0x617607aFAAf5ad91978CeC822157447B56368af3);
    FixedFeeStrategy constant oldFeeStrategy = FixedFeeStrategy(0x19673ba9e4Cb592E41aECb1b087e2b0eE9c70639);

    // New deployments
    GsmWithHyFiPool public newGsmImpl;
    GsmWithHyFiPool public upgradedGsm;
    FixedPriceStrategy public newPriceStrategy;
    FixedFeeStrategy public newFeeStrategy;
    TransparentUpgradeableProxy public newGsmProxy;
    ProxyAdmin public newProxyAdmin;

    // Shared state
    uint256 initialUsdt0Balance;
    address hyToken;

    // Test users
    address admin = 0xC2b3075fB1AC9f5eCc1e2C07dA8bcCC43e7083fb;
    address user1 = makeAddr("user");
    address user2 = makeAddr("user2");

    function setUp() public {
        // Fork Ethereum mainnet
        vm.createSelectFork("mainnet", 14700000);
        
        vm.startPrank(user1);

        newGsmImpl = new GsmWithHyFiPool(
            USDXL,
            USDT0,
            oldGsmProxy.PRICE_STRATEGY(),
            AAVE_V3_POOL_ADDRESSES_PROVIDER
        );
        
        vm.stopPrank();

        vm.prank(admin);
        TransparentUpgradeableProxy(payable(address(oldGsmProxy))).changeAdmin(address(oldProxyAdmin)); ///////

       oldProxyAdmin.getProxyAdmin(TransparentUpgradeableProxy(payable(address(oldGsmProxy))));

       oldProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(oldGsmProxy))));
        
        vm.stopPrank();
    }

    function testUpgrade() public {
        // Get old GSM state before upgrade
        address oldTreasury = oldGsmProxy.getUsdxlTreasury();
        uint128 oldExposureCap = oldGsmProxy.getExposureCap();
        uint256 oldRevision = oldGsmProxy.GSM_REVISION();
        bool initialFrozenState = oldGsmProxy.getIsFrozen();
        initialUsdt0Balance = IERC20(USDT0).balanceOf(address(oldGsmProxy));

        oldProxyAdmin.getProxyAdmin(TransparentUpgradeableProxy(payable(address(oldGsmProxy))));

        bytes memory initializeData = abi.encodeWithSelector(
            newGsmImpl.initialize.selector,
            address(0),
            address(0),
            0
        );

        console2.log("initializeData:");
        console2.logBytes(initializeData);

        vm.prank(admin);
        oldProxyAdmin.upgradeAndCall(TransparentUpgradeableProxy(payable(address(oldGsmProxy))), address(newGsmImpl), initializeData);
        
        // Cast proxy to new implementation
        upgradedGsm = GsmWithHyFiPool(address(oldGsmProxy));
        hyToken = address(upgradedGsm.HYTOKEN());

        newFeeStrategy = new FixedFeeStrategy(200, 0);

        vm.startPrank(admin);
        upgradedGsm.grantRole(upgradedGsm.CONFIGURATOR_ROLE(), admin);
        upgradedGsm.updateFeeStrategy(address(newFeeStrategy));
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(oldRevision, 1, "Old GSM revision should be 1");
        assertEq(upgradedGsm.GSM_REVISION(), 2, "GSM revision should be 2 after upgrade");
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
        assertEq(upgradedGsm.totalDepositedInHyFiPool(), initialUsdt0Balance, "Total deposited in HyFi Pool should be initial USDT0 balance");
        assertEq(upgradedGsm.getHyFiPoolAvailableLiquidity(), initialUsdt0Balance, "HyFi pool available liquidity should be initial USDT0 balance");
        assertEq(upgradedGsm.getAvailableUnderlying(), initialUsdt0Balance, "Available underlying should be initial USDT0 balance");
        assertEq(upgradedGsm.getAvailableUnderlyingViaHyAsset(), initialUsdt0Balance, "Available underlying via HyAsset should be initial USDT0 balance");
        assertEq(upgradedGsm.getHarvestableUnderlyingBalance(), 0, "Harvestable underlying balance should be 0");
        assertEq(upgradedGsm.getTotalUnderlying(), initialUsdt0Balance, "Total underlying should be initial USDT0 balance");
        
        (uint256 underlying, uint256 underlyingViaHyAsset) = upgradedGsm.getBuyLiquidity();
        assertEq(underlying, initialUsdt0Balance, "Underlying should be initial USDT0 balance");
        assertEq(underlyingViaHyAsset, initialUsdt0Balance, "Underlying via HyAsset should be initial USDT0 balance");
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
        assertEq(upgradedGsm.totalDepositedInHyFiPool(), initialUsdt0Balance - usdt0Amount, "Total deposited in HyFi Pool should be initial USDT0 balance minus the amount bought");
        assertEq(IERC20(hyToken).balanceOf(address(user1)), usdt0Amount, "HyToken balance should be the amount bought");
        assertEq(IERC20(hyToken).balanceOf(address(oldGsmProxy)), initialUsdt0Balance - usdt0Amount, "HyToken balance should be the initial USDT0 balance minus the amount bought");
        assertEq(IERC20(USDT0).balanceOf(address(oldGsmProxy)), 0, "USDT0 balance should be zero");
        assertEq(IERC20(USDT0).balanceOf(address(user1)), 0, "USDT0 balance should be zero");

        vm.stopPrank();

        console2.log("Basic GSM functionality verified after upgrade");
        console2.log("Asset amount received:", assetAmount);
        console2.log("USDXL sold:", usdxlSold);
    }

    function testGsmSeizeBefore() public {
        assertEq(oldGsmProxy.getIsSeized(), false, "GSM should not be seized");

        uint256 initialUsdt0Balance2 = IERC20(USDT0).balanceOf(admin);
        vm.startPrank(admin);
        oldGsmProxy.grantRole(oldGsmProxy.LIQUIDATOR_ROLE(), admin);
        oldGsmProxy.seize();
        vm.stopPrank();

        assertEq(IERC20(USDT0).balanceOf(admin), initialUsdt0Balance2, "USDT0 balance should be the initial USDT0 balance");
        assertEq(IERC20(USDT0).balanceOf(address(oldGsmProxy)), 0, "USDT0 balance should be zero");

        assertEq(oldGsmProxy.getIsSeized(), true, "GSM should be seized");
    }

    function testGsmSeizeAfter() public {
        testUpgrade();

        testGsmSeizeBefore();
    }
}
