// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IUsdxlConfigsTypes {
    struct UsdxlDeployRegistry {
        address usdxlATokenImpl;
        address usdxlATokenProxy;
        address usdxlFlashMinterImpl;
        address usdxlOracle;
        address usdxlTokenImpl;
        address usdxlTokenProxy;
        address usdxlVariableDebtTokenImpl;
        address usdxlVariableDebtTokenProxy;
    }
}
