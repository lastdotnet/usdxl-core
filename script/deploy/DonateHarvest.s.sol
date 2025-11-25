// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GsmWithHyFiPoolV2} from "src/contracts/facilitators/gsm/GsmWithHyFiPoolV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DonateHarvest is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("EXECUTOR_PRIVATE_KEY"));
        donateHarvest(0x6Ee5923f5166f8407500A3e51c818aCD5aC81DA9, 0xA23710d9D6E27C2A246b3C0D0dA0448437352D3a, 0.9e6);
    }

    function donateHarvest(address oldGsmProxy, address newGsmProxy, uint256 amount) public {
        GsmWithHyFiPoolV2(payable(oldGsmProxy)).harvestInterestTo(vm.addr(vm.envUint("EXECUTOR_PRIVATE_KEY")));
        IERC20(GsmWithHyFiPoolV2(payable(newGsmProxy)).UNDERLYING_ASSET()).approve(address(newGsmProxy), amount);
        GsmWithHyFiPoolV2(payable(newGsmProxy)).harvestDonate(amount);
        console2.log("Harvest donated successfully");
    }
}