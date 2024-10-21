// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";
import {ChildChainGaugeInjectorV2Factory} from "../contracts/injectorFactoryV2.sol";

/// @notice Deploys the v2 infrastructure for the injectors in all chains in `foundry.toml` in the following order:
/// 1. {ChildChainGaugeInjectorV2} -> singleton/implementation purposes (helps verifying in etherscan etc)
/// 2. {ChildChainGaugeInjectorV2Factory}
contract InjectorInfraMultiChainDeployment is Script {
    enum Chains {
        ARBITRUM,
        BASE,
        FRAXTAL,
        GNOSIS,
        OPTIMISM,
        POLYGON,
        AVALANCHE,
        ZKEVM,
        MODE
    }

    // injector infrastructure
    ChildChainGaugeInjectorV2 injectorImpl;
    ChildChainGaugeInjectorV2Factory injectorFactory;

    mapping(Chains chain => string rpcAlias) public availableChains;

    constructor() {
        availableChains[Chains.ARBITRUM] = "arbitrum";
        availableChains[Chains.BASE] = "base";
        availableChains[Chains.FRAXTAL] = "fraxtal";
        availableChains[Chains.GNOSIS] = "gnosis";
        availableChains[Chains.OPTIMISM] = "optimism";
        availableChains[Chains.POLYGON] = "polygon";
        availableChains[Chains.AVALANCHE] = "avalanche";
        availableChains[Chains.ZKEVM] = "zkevm";
        availableChains[Chains.MODE] = "mode";
    }

    /// @dev broadcast transaction modifier
    /// @param pk private key to broadcast transaction
    modifier broadcast(uint256 pk) {
        vm.startBroadcast(pk);

        _;

        vm.stopBroadcast();
    }

    function run() public {
        // read pk from `.env`
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // @note the array can be updated depending on your target chains to deploy
        // @note by default the script will deploy in all chains available in the toml file
        Chains[] memory targetDeploymentChains = new Chains[](8);

        targetDeploymentChains[0] = Chains.ARBITRUM;
        targetDeploymentChains[1] = Chains.BASE;
        targetDeploymentChains[3] = Chains.GNOSIS;
        targetDeploymentChains[4] = Chains.OPTIMISM;
        targetDeploymentChains[5] = Chains.POLYGON;
        targetDeploymentChains[6] = Chains.AVALANCHE;
        targetDeploymentChains[7] = Chains.ZKEVM;
        targetDeploymentChains[8] = Chains.MODE;
        // @note fraxtal rpc gives sometimes problems

        for (uint256 i = 0; i < targetDeploymentChains.length; i++) {
            _deploy(targetDeploymentChains[i], pk);
        }
    }

    /// @dev Helper to point into a specific chain
    /// @param _targetChain chain to deploy
    /// @param _pk private key to broadcast transaction
    function _deploy(Chains _targetChain, uint256 _pk) internal {
        vm.createSelectFork(availableChains[_targetChain]);

        _infraDeployment(_pk);
    }

    /// @dev Helper to deploy the factory and singleton
    /// @param _pk private key to broadcast transaction
    function _infraDeployment(uint256 _pk) internal broadcast(_pk) {
        // 1. {ChildChainGaugeInjectorV2}
        injectorImpl = new ChildChainGaugeInjectorV2();

        // 2. {ChildChainGaugeInjectorV2Factory}
        injectorFactory = new ChildChainGaugeInjectorV2Factory(address(injectorImpl));
    }
}