// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";
import {ChildChainGaugeInjectorV2Factory} from "../contracts/injectorFactoryV2.sol";

contract BaseFixture is Test {
    // injector instance
    ChildChainGaugeInjectorV2 injector;

    // factory instance
    ChildChainGaugeInjectorV2Factory factory;

    // constants
    address constant GAUGE = 0x3Eae4a1c2E36870A006E816930d9f55DF0a72a13;
    address constant GAUGE_2 = 0xc7e5FE004416A96Cb2C7D6440c28aE92262f7695;
    address constant LM_MULTISIG = 0xc38c5f97B34E175FFd35407fc91a937300E33860;
    address constant AUTHORIZER_ADAPTER = 0xAB093cd16e765b5B23D34030aaFaF026558e0A19;
    address constant TEST_TOKEN_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    // token address constants
    address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    // agents
    address constant KEEPER = address(5);

    function setUp() public {
        injector = new ChildChainGaugeInjectorV2();
        factory = new ChildChainGaugeInjectorV2Factory(address(injector));

        assert(factory.implementation() == address(injector));
    }
}
