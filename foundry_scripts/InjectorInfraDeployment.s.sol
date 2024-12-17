// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {MainChainGaugeInjectorV2} from "../contracts/MainChainGaugeInjectorV2.sol";
import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";
import {ChildChainGaugeInjectorV2Factory} from "../contracts/injectorFactoryV2.sol";
import {MainChainGaugeInjectorV2} from "../contracts/MainChainGaugeInjectorV2.sol";
import {MainChainGaugeInjectorV2Factory} from "../contracts/MainInjectorFactoryV2.sol";

/// @notice Deploys the v2 infrastructure for the injectors in the following order:
/// 1. {ChildChainGaugeInjectorV2} -> singleton/implementation purposes (helps verifying in etherscan etc)
/// 2. {ChildChainGaugeInjectorV2Factory}
contract InjectorInfraDeployment is Script {
    // injector infrastructure
    MainChainGaugeInjectorV2 mainInjectorImpl;
    ChildChainGaugeInjectorV2 childInjectorImpl;
    ChildChainGaugeInjectorV2Factory injectorFactory;
    MainChainGaugeInjectorV2Factory mainInjectorFactory;
 function run() public {
    // read pk from `.env`
    uint256 pk = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(pk);

    // 1. {InjectorV2}
    if (block.chainid == 1){
        MainChainGaugeInjectorV2 injectorImpl = new MainChainGaugeInjectorV2();
        MainChainGaugeInjectorV2Factory injectorFactory = new MainChainGaugeInjectorV2Factory(address(injectorImpl));
    } else {
        ChildChainGaugeInjectorV2 injectorImpl = new ChildChainGaugeInjectorV2();
        ChildChainGaugeInjectorV2Factory injectorFactory = new ChildChainGaugeInjectorV2Factory(address(injectorImpl));
    }
 }
}