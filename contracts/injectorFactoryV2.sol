// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

import "./ChildChainGaugeInjectorV2.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {IKeeperRegistrar} from "./interfaces/chainlink/IKeeperRegistrar.sol";
import {IKeeperRegistryMaster} from "./interfaces/chainlink/IKeeperRegistryMaster.sol";

/**
 * @title ChildChainGaugeInjectorV2Factory
 * @dev Factory contract to deploy instances of ChildChainGaugeInjectorV2 using a proxy pattern for low deployment cost
 */
contract ChildChainGaugeInjectorV2Factory {
    event InjectorCreated(
        address indexed injector, address[] keeperAddresses, address injectTokenAddress, address owner
    );

    error UpkeepZero();

    address public immutable implementation;

    address[] private deployedInjectors;

    IERC20 constant LINK = IERC20(0xE2e73A1c69ecF83F464EFCE6A5be353a37cA09b2);

    IKeeperRegistrar constant CL_REGISTRAR = IKeeperRegistrar(0x0F7E163446AAb41DB5375AbdeE2c3eCC56D9aA32);

    IKeeperRegistryMaster constant CL_REGISTRY = IKeeperRegistryMaster(0x299c92a219F61a82E91d2062A262f7157F155AC1);

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
        address owner,
        bool registerUpkeep
    ) external returns (address) {
        address injector = Clones.clone(implementation);
        ChildChainGaugeInjectorV2(injector).initialize(
            owner, keeperAddresses, minWaitPeriodSeconds, injectTokenAddress, maxInjectionAmount
        );
        emit InjectorCreated(injector, keeperAddresses, injectTokenAddress, owner);
        deployedInjectors.push(injector);

        if (registerUpkeep) {
            uint256 upkeepId = _registerUpkeep(injector, owner);
            address[] memory keepers = new address[](1);
            keepers[0] = CL_REGISTRY.getForwarder(upkeepId);
            ChildChainGaugeInjectorV2(injector).setKeeperAddresses(keepers);
        }
        return injector;
    }

    /**
     * @dev Returns the array of addresses of deployed injectors, note that not all injectors on the list may be active or functional
     * @return The array of addresses of deployed injectors
     */
    function getDeployedInjectors() external view returns (address[] memory) {
        return deployedInjectors;
    }

    /**
     * @notice Registers an injector in the Chainlink Keeper Registry
     * @param _injector The address of the injector to be registered
     */
    function _registerUpkeep(address _injector, address _owner) internal returns (uint256 upkeepId_) {
        IKeeperRegistrar.RegistrationParams memory registrationParams = IKeeperRegistrar.RegistrationParams({
            name: "ChildChainGaugeInjectorV2",
            encryptedEmail: "",
            upkeepContract: _injector,
            gasLimit: 2_000_000,
            adminAddress: _owner,
            triggerType: 0,
            checkData: "",
            triggerConfig: "",
            offchainConfig: "",
            amount: 1e18
        });

        upkeepId_ = CL_REGISTRAR.registerUpkeep(registrationParams);
        if (upkeepId_ == 0) revert UpkeepZero();
    }
}
