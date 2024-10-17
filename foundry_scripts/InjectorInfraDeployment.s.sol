// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";
import {ChildChainGaugeInjectorV2Factory} from "../contracts/injectorFactoryV2.sol";

/// @notice Deploys the v2 infrastructure for the injectors in the following order:
/// 1. {ChildChainGaugeInjectorV2} -> singleton/implementation purposes (helps verifying in etherscan etc)
/// 2. {ChildChainGaugeInjectorV2Factory}
contract InjectorInfraDeployment is Script {
    // injector infrastructure
    ChildChainGaugeInjectorV2 injectorImpl;
    ChildChainGaugeInjectorV2Factory injectorFactory;

 function run() public {
    // read pk from `.env`
    uint256 pk = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(pk);

    // 1. {ChildChainGaugeInjectorV2}
    injectorImpl = new ChildChainGaugeInjectorV2();

    // 2. {ChildChainGaugeInjectorV2Factory}
    injectorFactory = new ChildChainGaugeInjectorV2Factory(address(injectorImpl));
 }
}