// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";

contract FactoryTest is BaseFixture {
    // dummy constants
    uint256 MIN_WAIT_PERIOD_SECONDS = 1 days;
    uint256 MAX_INJECTION_AMOUNT = 1_000e18;
    address OWNER = address(56565);

    event InjectorCreated(
        address indexed injector, address[] keeperAddresses, address injectTokenAddress, address owner
    );

    ChildChainGaugeInjectorV2 injectorFactoryDeployed;

    function testCreateInjector() public {
        address[] memory keeperAddresses = new address[](1);
        keeperAddresses[0] = KEEPER;

        // check: event emitted
        vm.expectEmit(false, true, true, true); // @note topic0 is not checkeds
        emit InjectorCreated(address(0), keeperAddresses, USDT, OWNER);

        // 1. create a new injector via factory
        address injectorDeployed =
            factory.createInjector(keeperAddresses, MIN_WAIT_PERIOD_SECONDS, USDT, MAX_INJECTION_AMOUNT, OWNER);
        injectorFactoryDeployed = ChildChainGaugeInjectorV2(injectorDeployed);

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
