// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

import "./ChildChainGaugeInjectorV2.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title ChildChainGaugeInjectorV2Factory
 * @dev Factory contract to deploy instances of ChildChainGaugeInjectorV2 using a proxy pattern for low deployment cost
 */
contract ChildChainGaugeInjectorV2Factory {
    event InjectorCreated(address indexed injector, address[] keeperAddresses, address injectTokenAddress, address owner);


    address public implementation;

    constructor(address logic) {
        implementation = logic;
    }

/**
 * @dev Deploys a new instance of ChildChainGaugeInjectorV2 using Clones.sol
 * @param keeperAddresses The array of addresses of the keeper contracts
 * @param minWaitPeriodSeconds The minimum wait period for address between funding (for security)
 * @param injectTokenAddress The ERC20 token this contract should manage
 * @param maxInjectionAmount The max amount of tokens that should be injected to a single gauge in a single week by this injector.
 * @param owner The owner of the ChildChainGaugeInjectorV2 instance
 * @return The address of the newly deployed ChildChainGaugeInjectorV2 instance
 */
    function createInjector(
        address[] memory keeperAddresses,
        uint256 minWaitPeriodSeconds,
        address injectTokenAddress,
        uint256 maxInjectionAmount,
        address owner
    ) external returns (address) {
        address injector = Clones.clone(implementation);
        ChildChainGaugeInjectorV2(injector).initialize(
            owner,
            keeperAddresses,
            minWaitPeriodSeconds,
            injectTokenAddress,
            maxInjectionAmount
        );
        emit InjectorCreated(injector, keeperAddresses, injectTokenAddress, owner);
        return injector;
    }
}
