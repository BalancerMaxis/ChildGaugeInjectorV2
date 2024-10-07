// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

/// @notice Scope of the file is to test uncovered reverts, setters and getters:
/// 1. revert: `InjectorNotDistributor`
/// 2. revert: `ExceedsTotalInjectorProgramBudget`
/// 3. revert: `OnlyKeepers`
/// 4. getter: `getBalanceDelta` (cases-> deficit, exact balance and surplus)
/// 5. getter: `getFullSchedule` (check: expected values)
// @audit https://github.com/BalancerMaxis/ChildGaugeInjectorV2/issues/31 ?
contract UncoveredLinesTest is BaseFixture {
    function test_revertWhen_InjectorNotDistributor() public {}

    function test_revertWhen_ExceedsTotalInjectorProgramBudget() public {}

    function test_revertWhen_NotKeepers() public {}

    function testGetBalance_When_Deficit() public {}

    function testGetBalance_When_ExactBalance() public {}

    function testGetBalance_When_Surplus() public {}

    function testGetFullSchedule() public {}
}
