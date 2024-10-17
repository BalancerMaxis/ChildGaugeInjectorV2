// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";

contract FactoryTest is BaseFixture {
    function testCreateInjector() public {
        // 1. create a new injector via factory
        address injectorDeployed = _deployDummyInjector();
        ChildChainGaugeInjectorV2 injectorFactoryDeployed = ChildChainGaugeInjectorV2(injectorDeployed);

        // 2. asserts:
        // 2.1. check `getDeployedInjectors` returns the correct number of injectors
        address[] memory injectorsDeployed = factory.getDeployedInjectors();
        assertEq(injectorsDeployed.length, 1);
        assertEq(injectorsDeployed[0], injectorDeployed);

        // 2.2. check params of the injector correctness at deployment time
        assertEq(injectorFactoryDeployed.owner(), OWNER);
        assertEq(injectorFactoryDeployed.getKeeperAddresses()[0], KEEPER);
        assertEq(injectorFactoryDeployed.MinWaitPeriodSeconds(), MIN_WAIT_PERIOD_SECONDS);
        assertEq(injectorFactoryDeployed.InjectTokenAddress(), USDT);
    }
}
