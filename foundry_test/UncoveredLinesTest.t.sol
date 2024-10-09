// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IChildChainGauge} from "../contracts/interfaces/balancer/IChildChainGauge.sol";

import {ChildChainGaugeInjectorV2} from "../contracts/ChildChainGaugeInjectorV2.sol";

/// @notice Scope of the file is to test uncovered reverts, setters and getters:
/// 1. revert: `InjectorNotDistributor`
/// 2. revert: `ExceedsTotalInjectorProgramBudget`
/// 3. revert: `OnlyKeepers`
/// 4. getter: `getBalanceDelta` (cases-> deficit, exact balance and surplus)
/// 5. getter: `getFullSchedule` (check: expected values)
// @audit https://github.com/BalancerMaxis/ChildGaugeInjectorV2/issues/31 ?
contract UncoveredLinesTest is BaseFixture {
    function test_revertWhen_InjectorNotDistributor() public {
        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        address[] memory recipients = new address[](1);
        recipients[0] = GAUGE;

        vm.prank(inj.owner());
        vm.expectRevert(abi.encodeWithSelector(ChildChainGaugeInjectorV2.InjectorNotDistributor.selector, GAUGE, USDT));
        inj.addRecipients(recipients, 50e18, 4, uint56(block.timestamp + 1 days));
    }

    function test_revertWhen_ExceedsTotalInjectorProgramBudget() public {
        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        _enableInjectorAsDistributor(address(inj));

        uint256 dummyMaxTotalDue = 100e18;
        vm.startPrank(inj.owner());
        inj.setMaxTotalDue(dummyMaxTotalDue);
        assertEq(inj.MaxTotalDue(), dummyMaxTotalDue);

        address[] memory recipients = new address[](2);
        recipients[0] = GAUGE;
        recipients[1] = GAUGE_2;

        uint256 amountPerPeriod = 250e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                ChildChainGaugeInjectorV2.ExceedsTotalInjectorProgramBudget.selector, amountPerPeriod
            )
        );
        inj.addRecipients(recipients, 250e18, 1, uint56(block.timestamp + 1 days));
    }

    function test_revertWhen_NotKeepers() public {
        address NOT_KEEPER_AGENT = address(543485484845);

        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        address[] memory needsFunding = new address[](1);
        needsFunding[0] = GAUGE;

        vm.prank(NOT_KEEPER_AGENT);
        vm.expectRevert(abi.encodeWithSelector(ChildChainGaugeInjectorV2.OnlyKeepers.selector, NOT_KEEPER_AGENT));
        inj.performUpkeep(abi.encode(needsFunding));
    }

    function testGetBalance_When_Deficit() public {
        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        _enableInjectorAsDistributor(address(inj));

        address[] memory recipients = new address[](1);
        recipients[0] = GAUGE;
        uint256 amountPerPeriod = 250e18;
        vm.prank(inj.owner());
        inj.addRecipients(recipients, amountPerPeriod, 1, uint56(block.timestamp + 1 days));

        // send partially
        deal(USDT, address(inj), 50e18);

        int256 expectedDeficit = -1 * int256(amountPerPeriod - IERC20(USDT).balanceOf(address(inj)));

        // should encounter DEFICIT
        assertEq(inj.getBalanceDelta(), expectedDeficit);
    }

    function testGetBalance_When_ExactBalance() public {
        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        _enableInjectorAsDistributor(address(inj));

        address[] memory recipients = new address[](1);
        recipients[0] = GAUGE;
        uint256 amountPerPeriod = 250e18;
        vm.prank(inj.owner());
        inj.addRecipients(recipients, amountPerPeriod, 1, uint56(block.timestamp + 1 days));

        // send full `amountPerPeriod`
        deal(USDT, address(inj), amountPerPeriod);

        // should encounter EXACT
        assertEq(inj.getBalanceDelta(), 0);
    }

    function testGetBalance_When_Surplus() public {
        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        _enableInjectorAsDistributor(address(inj));

        address[] memory recipients = new address[](1);
        recipients[0] = GAUGE;
        uint256 amountPerPeriod = 250e18;
        vm.prank(inj.owner());
        inj.addRecipients(recipients, amountPerPeriod, 1, uint56(block.timestamp + 1 days));

        // send full `amountPerPeriod` * 3
        deal(USDT, address(inj), amountPerPeriod * 3);

        int256 expectedSurplus = int256(IERC20(USDT).balanceOf(address(inj)) - amountPerPeriod);
        // should encounter SURPLUS
        assertEq(inj.getBalanceDelta(), expectedSurplus);
    }

    function testGetFullSchedule() public {
        ChildChainGaugeInjectorV2 inj = ChildChainGaugeInjectorV2(_deployDummyInjector());

        _enableInjectorAsDistributor(address(inj));

        address[] memory recipients = new address[](2);
        recipients[0] = GAUGE;
        recipients[1] = GAUGE_2;

        vm.prank(inj.owner());
        inj.addRecipients(recipients, 250e18, 5, uint56(block.timestamp + 1 days));

        (
            address[] memory gauges,
            uint256[] memory amountsPerPeriod,
            uint8[] memory maxPeriods,
            uint8[] memory currentPeriods,
            uint56[] memory lastTimestamps,
            uint56[] memory doNotStartBeforeTimestamps
        ) = inj.getFullSchedule();

        for (uint256 i = 0; i < gauges.length; i++) {
            assertEq(gauges[i], recipients[i]);
            assertEq(amountsPerPeriod[i], 250e18);
            assertEq(maxPeriods[i], 5);
            assertEq(currentPeriods[i], 0);
            assertEq(lastTimestamps[i], uint56(0));
            assertEq(doNotStartBeforeTimestamps[i], uint56(block.timestamp + 1 days));
        }
    }
}
