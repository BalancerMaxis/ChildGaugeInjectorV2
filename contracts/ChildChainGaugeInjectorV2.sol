// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/balancer/IChildChainGauge.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title The ChildChainGaugeInjectorV2 Contract
 * @author 0xtritium.eth
 * @notice This contract is a chainlink automation compatible interface to automate regular payment of non-BAL tokens to a child chain gauge.
 * @notice This contract is meant to run/manage a single token.  This is almost always the case for a DAO trying to use such a thing.
 * @notice This contract will only function if it is configured as the distributor for a token/gauge it is operating on.
 * @notice This contract is Ownable and  has lots of sweep functionality to allow the owner to work with the contract or get tokens out should there be a problem.
 * see https://docs.chain.link/chainlink-automation/utility-contracts/
 */
contract ChildChainGaugeInjectorV2 is
Ownable2Step,
Pausable,
Initializable,
KeeperCompatibleInterface
{
    using EnumerableSet for EnumerableSet.AddressSet;

    event GasTokenWithdrawn(uint256 amountWithdrawn, address recipient);
    event KeeperRegistryAddressUpdated(address[] oldAddresses, address[] newAddresses);
    event MinWaitPeriodUpdated(uint256 oldMinWaitPeriod, uint256 newMinWaitPeriod);
    event MaxInjectionAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MaxGlobalAmountPerPeriodUpdated(uint256 oldAmount, uint256 newAmount);
    event MaxTotalDueUpdated(uint256 oldAmount, uint256 newAmount);
    event ERC20Swept(address indexed token, address recipient, uint256 amount);
    event EmissionsInjection(address gauge, address token, uint256 amount);
    event SetHandlingToken(address token);
    event PerformedUpkeep(address[] needsFunding);
    event RecipientAdded(
        address gaugeAddress,
        uint256 amountPerPeriod,
        uint256 maxPeriods,
        uint256 periodsExecutedLastProgram,
        uint56 doNotStartBeforeTimestamp,
        bool seenBefore
    );
    event RecipientRemoved(address gaugeAddress);
    event InjectorInitialized(
        address[] keeperAddresses,
        uint256 minWaitPeriodSeconds,
        address injectTokenAddress,
        uint256 maxInjectionAmount
    );

    error OnlyKeepers(address sender);
    error ZeroAddress();
    error RewardTokenError();
    error RemoveNonexistentRecipient(address gaugeAddress);
    error ExceedsMaxInjectionAmount(
        address gaugeAddress,
        uint256 amountsPerPeriod,
        uint256 maxInjectionAmount
    );
    error ExceedsWeeklySpend(uint256 weeklySpend);
    error ExceedsTotalInjectorProgramBudget(uint256 totalDue);
    error InjectorNotDistributor(address gauge, address InjectTokenAddress);

    struct Target {
        uint256 amountPerPeriod;
        bool isActive;
        uint8 maxPeriods;
        uint8 periodNumber;
        uint56 lastInjectionTimestamp; // enough space for 2 trillion years
        uint56 programStartTimestamp;
    }

    EnumerableSet.AddressSet internal ActiveGauges;
    mapping(address => Target) internal GaugeConfigs;

/**
/* @notice The addresses that can call performUpkeep,the 0 address anywhere in this list is a wildcard, in this case anyone can keep.
*/
    address[] public KeeperAddresses;
/**
/* @notice The max amount any 1 schedule can inject in any one round
*/
    uint256 public MaxInjectionAmount;
/**
/* @notice The max amount that can be programmed fire over 1 run on all active periods, add will not work if this is exceed. 0 for unlimited.
*/
    uint256 public MaxGlobalAmountPerPeriod;
/**
/* @notice The max total amount due over all active programs.  New program adds will not be allowed if they exceed this number.  0 for unlimited.
*/
    uint256 public MaxTotalDue;
/**
/* @notice Regardless of other logic, wait at least this long  on each gauge between injections.
*/
    uint256 public MinWaitPeriodSeconds;
/**
/* @notice The token this injector operates on.
*/
    address public InjectTokenAddress;

    constructor()  Ownable(msg.sender) {}

/*
 * @notice Initializes the ChildChainGaugeInjector logic contract.
 * @param owner of the injector. Has special privileges.
 * @param keeperAddresses The addresses of the keeper contracts
 * @param minWaitPeriodSeconds The minimum wait period for address between funding (for security)
 * @param injectTokenAddress The ERC20 token this contract should mange
 * @param maxInjectionAmount The max amount of tokens that should be injected to a single gauge in a single week by this injector.
 */
    function initialize(
        address owner,
        address[] memory keeperAddresses,
        uint256 minWaitPeriodSeconds,
        address injectTokenAddress,
        uint256 maxInjectionAmount
    ) external initializer {
        _transferOwnership(owner);
        KeeperAddresses = keeperAddresses;
        MinWaitPeriodSeconds = minWaitPeriodSeconds;
        InjectTokenAddress = injectTokenAddress;
        MaxInjectionAmount = maxInjectionAmount;
        emit InjectorInitialized(
            keeperAddresses,
            minWaitPeriodSeconds,
            injectTokenAddress,
            maxInjectionAmount
        );
    }

/**
 * @notice Injects funds into the gauges provided
 * @param gauges the list of gauges to fund (addresses must be pre-approved)
 */
    function _injectFunds(address[] memory gauges) internal whenNotPaused {
        uint256 minWaitPeriodSeconds = MinWaitPeriodSeconds;
        IERC20 token = IERC20(InjectTokenAddress);
        uint256 balance = token.balanceOf(address(this));

        for (uint256 idx = 0; idx < gauges.length; idx++) {
            Target storage targetConfig = GaugeConfigs[gauges[idx]];
            IChildChainGauge gauge = IChildChainGauge(gauges[idx]);
            uint256 current_gauge_emissions_end = gauge
                .reward_data(address(token))
                .period_finish;

            if (
                targetConfig.lastInjectionTimestamp + minWaitPeriodSeconds <= block.timestamp && // Not too recent based on minWaitPeriodSeconds
                targetConfig.programStartTimestamp <= block.timestamp &&  // Not before program start time
                current_gauge_emissions_end <= block.timestamp && // This token is currently not streaming on this gauge
                targetConfig.periodNumber < targetConfig.maxPeriods && // We have not already executed the last period
                balance >= targetConfig.amountPerPeriod && // We have enough coins to pay
                targetConfig.amountPerPeriod <= MaxInjectionAmount && //  We are not trying to inject more than the global max for 1 injection
                targetConfig.isActive // The gauge is marked active in the injector
            ) {
                SafeERC20.forceApprove(
                    token,
                    gauges[idx],
                    targetConfig.amountPerPeriod
                );

                gauge.deposit_reward_token(
                    address(token),
                    targetConfig.amountPerPeriod
                );

                targetConfig.lastInjectionTimestamp = uint56(block.timestamp);
                targetConfig.periodNumber++;
                emit EmissionsInjection(
                    gauges[idx],
                    address(token),
                    targetConfig.amountPerPeriod
                );
            }
        }
    }

/**
 *  @notice This is to allow the owner to manually trigger an injection of funds in place of the keeper
 * @notice without abi encoding the gauge list
 * @param gauges array of gauges to inject tokens to
 */
    function injectFunds(address[] memory gauges) external onlyOwner {
        _injectFunds(gauges);
    }

/**
 * @notice Get list of addresses that are ready for new token injections and return keeper-compatible payload
 * @notice calldata required by the chainlink interface but not used in this case, use 0x
 * @return upkeepNeeded signals if upkeep is needed
 * @return performData is an abi encoded list of addresses that need funds
 */
    function checkUpkeep(
        bytes calldata
    )
    external
    view
    override
    whenNotPaused
    returns (bool upkeepNeeded, bytes memory performData)
    {
        address[] memory ready = getReadyGauges();
        upkeepNeeded = ready.length > 0;
        performData = abi.encode(ready);
        return (upkeepNeeded, performData);
    }

/**
 * @notice Called by keeper to send funds to underfunded addresses
 * @param performData The abi encoded list of addresses to fund
 */
    function performUpkeep(
        bytes calldata performData
    ) external override onlyKeeper whenNotPaused {
        address[] memory needsFunding = abi.decode(performData, (address[]));
        _injectFunds(needsFunding);
        emit PerformedUpkeep(needsFunding);
    }
/**
 * @notice Adds/updates a list of recipients with the same configuration
 * @param recipients A list of gauges to be setup with the defined params amounts
 * @param amountPerPeriod the wei amount of tokens per period that each listed gauge should receive
 * @param maxPeriods The number of weekly periods the specified amount should be paid to the specified gauge over
 * @param doNotStartBeforeTimestamp A timestamp that injections should not start before. Use 0 to start as soon as gauges are ready.
 */
    function addRecipients(
        address[] calldata recipients,
        uint256 amountPerPeriod,
        uint8 maxPeriods,
        uint56 doNotStartBeforeTimestamp
    ) public onlyOwner {
        bool update;
        uint8 executedPeriods;
        // Check that we are not violating MaxInjectionAmount - we use recipients[0] here as address because in this
        // case all added gauges violate MaxInjectionAmount and the event takes a single address, so the first one breaks it.
        if (MaxInjectionAmount > 0 && MaxInjectionAmount < amountPerPeriod) {
            revert ExceedsMaxInjectionAmount(
                recipients[0],
                amountPerPeriod,
                MaxInjectionAmount
            );
        }
        for (uint i = 0; i < recipients.length; i++) {
            // Check that this is a gauge and it is ready for us to inject to it
            IChildChainGauge gauge = IChildChainGauge(recipients[i]);
            if (
                gauge.reward_data(InjectTokenAddress).distributor != address(this)
            ) {
                revert InjectorNotDistributor(
                    address(gauge),
                    InjectTokenAddress
                );
            }

            // enumerableSet returns false if Already Exists
            update = ActiveGauges.add(recipients[i]);
            executedPeriods = 0;

            if (!update && GaugeConfigs[recipients[i]].isActive) {
                executedPeriods = GaugeConfigs[recipients[i]].periodNumber;
            }
            Target memory target = GaugeConfigs[recipients[i]]; // Preserve lastInjectionTimestamp
            target.isActive = true;
            target.amountPerPeriod = amountPerPeriod;
            target.maxPeriods = maxPeriods;
            target.periodNumber = 0;
            target.programStartTimestamp = doNotStartBeforeTimestamp;
            GaugeConfigs[recipients[i]] = target;
            if (MaxGlobalAmountPerPeriod > 0 && MaxGlobalAmountPerPeriod < getWeeklySpend()) {
                revert ExceedsWeeklySpend(getWeeklySpend());
            }
            if (MaxTotalDue > 0 && MaxTotalDue < getTotalDue()) {
                revert ExceedsTotalInjectorProgramBudget(getTotalDue());
            }

            emit RecipientAdded(
                recipients[i],
                amountPerPeriod,
                maxPeriods,
                executedPeriods,
                doNotStartBeforeTimestamp,
                update
            );
        }
    }

/**
 * @notice Removes Recipients
 * @param recipients A list of recipients to remove
 */
    function removeRecipients(address[] calldata recipients) public onlyOwner {
        for (uint i = 0; i < recipients.length; i++) {
            if (ActiveGauges.remove(recipients[i])) {
                GaugeConfigs[recipients[i]].isActive = false;
                emit RecipientRemoved(recipients[i]);
            } else {
                revert RemoveNonexistentRecipient(recipients[i]);
            }
        }
    }
/**
  * @notice Withdraws the contract balance
 */
    function withdrawGasToken(address payable dest) external onlyOwner {
        address payable recipient = dest;
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        uint256 amount = address(this).balance;
        recipient.transfer(amount);
        emit GasTokenWithdrawn(amount, recipient);
    }

/**
 * @notice Sweep the full contract's balance for a given ERC-20 token
 * @param token The ERC-20 token which needs to be swept
 */
    function sweep(address token, address dest) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(token), dest, balance);
        emit ERC20Swept(token, owner(), balance);
    }

/**
 * @notice Manually deposit an amount of tokens to the gauge - Does not check MaxInjectionAmount
 * @param gauge The Gauge to set distributor to injector owner
 * @param reward_token Reward token you are seeding
 * @param amount Amount to deposit
 */
    function manualDeposit(
        address gauge,
        address reward_token,
        uint256 amount
    ) external onlyOwner {
        IChildChainGauge gaugeContract = IChildChainGauge(gauge);
        IERC20 token = IERC20(reward_token);
        SafeERC20.forceApprove(token, gauge, amount);
        gaugeContract.deposit_reward_token(reward_token, amount);
        emit EmissionsInjection(gauge, reward_token, amount);
    }
/**
* @notice Get's the full injector schedule in 1 call.  All lists are ordered such that the same member across all arrays represents one program.
 * @return gauges Currently scheduled gauges
 * @return amountsPerPeriod how much token in wei is paid to the gauge per period
 * @return maxPeriods the max number of periods this program will run for
 * @return lastTimestamps the last timestamp the injector ran for this gauge
 * @return doNotStartBeforeTimestamps a timestamp this schedule should not start before

 */

/**
* @notice Gets all current schedule information as a set of arrays
*/
    function getFullSchedule() public view returns (address[] memory, uint256[] memory, uint8[] memory, uint56[] memory, uint56[] memory) {
        address[] memory gauges = getActiveGaugeList();
        uint len = gauges.length;
        uint256[] memory amountsPerPeriod = new uint256[](len);
        uint8[] memory maxPeriods = new uint8[](len);
        uint56[] memory lastTimestamps = new uint56[](len);
        uint56[] memory doNotStartBeforeTimestamps = new uint56[](len);

        for (uint256 i = 0; i < gauges.length; i++) {
            Target memory target = GaugeConfigs[gauges[i]];
            amountsPerPeriod[i] = target.amountPerPeriod;
            maxPeriods[i] = target.maxPeriods;
            lastTimestamps[i] = target.lastInjectionTimestamp;
            doNotStartBeforeTimestamps[i] = target.programStartTimestamp;
        }
        return (gauges, amountsPerPeriod, maxPeriods, lastTimestamps, doNotStartBeforeTimestamps);
    }

/**
 * @notice Gets the total amount of tokens due to complete the program.
 * @return totalDue The total amount of tokens required in the contract balance to pay out all programmed injections across all gauges.
 */
    function getTotalDue() public view returns (uint256 totalDue) {
        address[] memory gaugeList = getActiveGaugeList();
        for (uint256 idx = 0; idx < gaugeList.length; idx++) {
            Target memory target = GaugeConfigs[gaugeList[idx]];
            totalDue +=
                (target.maxPeriods - target.periodNumber) *
                target.amountPerPeriod;
        }
        return totalDue;
    }
/**
 * @notice Gets the total weekly spend
 * @return weeklySpend  The total amount of tokens required to fulfil all active programs for 1 period.
 */
    function getWeeklySpend() public view returns (uint256 weeklySpend){
        address[] memory gauges = getActiveGaugeList();
        for (uint256 i = 0; i < gauges.length; i++) {
            Target memory target = GaugeConfigs[gauges[i]];
            if (target.periodNumber < target.maxPeriods) {
                weeklySpend += target.amountPerPeriod;
            }
        }
        return weeklySpend;
    }

/**
 * @notice Gets the difference between the total amount scheduled and the balance in the contract.
 * @return delta is 0 if balances match, negative if injector balance is in deficit to service all loaded programs, and positive if there is a surplus.
 */
    function getBalanceDelta() public view returns (int256 delta) {
        uint256 balance = IERC20(InjectTokenAddress).balanceOf(address(this));
        uint256 totalDue = getTotalDue();

        if (balance >= totalDue) {
            delta = int256(balance) - int256(totalDue);
        } else {
            delta = -1 * int256(totalDue - balance);
        }
    }

/**
* @notice Estimates the spend until a given timestamp
* @param timestamp The timestamp to estimate spend until
* @return spendUntilTimestamp The total amount of tokens required to fulfil all active programs until the given timestamp
*/
    function estimateSpendUntilTimestamp(uint256 timestamp) public view returns (uint256 spendUntilTimestamp) {
        address[] memory gauges = getActiveGaugeList();
        for (uint256 i = 0; i < gauges.length; i++) {
            Target memory target = GaugeConfigs[gauges[i]];
            for (uint256 j = target.periodNumber; j < target.maxPeriods; j++) {
                if (block.timestamp + (j * 604800) <= timestamp) {
                    spendUntilTimestamp += target.amountPerPeriod;
                }
            }
        }
        return spendUntilTimestamp;
    }

/**
 * @notice Gets a list of addresses that are ready to inject
 * @notice This is done by checking if the current period has ended, and should inject new funds directly after the end of each period.
 * @return list of addresses that are ready to inject
 */
    function getReadyGauges() public view returns (address[] memory) {
        address[] memory gaugeList = getActiveGaugeList();
        address[] memory ready = new address[](gaugeList.length);
        uint256 maxInjectionAmount = MaxInjectionAmount;
        address tokenAddress = InjectTokenAddress;
        uint256 count = 0;
        uint256 minWaitPeriod = MinWaitPeriodSeconds;
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        Target memory target;
        for (uint256 idx = 0; idx < gaugeList.length; idx++) {
            target = GaugeConfigs[gaugeList[idx]];
            IChildChainGauge gauge = IChildChainGauge(gaugeList[idx]);
            uint256 current_gauge_emissions_end = gauge
                .reward_data(tokenAddress)
                .period_finish;
            if (target.amountPerPeriod > maxInjectionAmount) {
                revert ExceedsMaxInjectionAmount(
                    gaugeList[idx],
                    target.amountPerPeriod,
                    maxInjectionAmount
                );
            }
            if (
                target.lastInjectionTimestamp + minWaitPeriod <= block.timestamp &&
                target.programStartTimestamp <= block.timestamp &&
                current_gauge_emissions_end <= block.timestamp &&
                balance >= target.amountPerPeriod &&
                target.periodNumber < target.maxPeriods &&
                target.amountPerPeriod <= maxInjectionAmount &&
                gauge.reward_data(tokenAddress).distributor == address(this)
            ) {
                ready[count] = gaugeList[idx];
                count++;
                balance -= target.amountPerPeriod;
            }
        }
        if (count != gaugeList.length) {
            // ready is a list large enough to hold all possible gauges
            // count is the number of ready gauges that were inserted into ready
            // this assembly shrinks ready to length count such that it removes empty elements
            assembly {
                mstore(ready, count)
            }
        }
        return ready;
    }

/**
 * @notice Return a list of active gauges
 */
    function getActiveGaugeList() public view returns (address[] memory) {
        uint256 len = ActiveGauges.length();
        address[] memory activeGauges = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            activeGauges[i] = ActiveGauges.at(i);
        }
        return activeGauges;
    }

/**
 * @notice Gets configuration information for an address on the gauge list
 * @param targetAddress return Target struct for a given gauge according to the current scheduled distributions
 */
    function getGaugeInfo(
        address targetAddress
    )
    external
    view
    returns (
        uint256 amountPerPeriod,
        bool isActive,
        uint8 maxPeriods,
        uint8 periodNumber,
        uint56 lastInjectionTimestamp,
        uint56 doNotStartBeforeTimestamp
    )
    {
        Target memory target = GaugeConfigs[targetAddress];
        return (
            target.amountPerPeriod,
            target.isActive,
            target.maxPeriods,
            target.periodNumber,
            target.lastInjectionTimestamp,
            target.programStartTimestamp
        );
    }

/**
* @notice Set distributor from the injector back to the owner.
* @notice You will have to call set_reward_distributor back to the injector FROM the current distributor if you wish to continue using the injector
* @notice be aware that the only addresses able to call set_reward_distributor is the current distributor, so make the right person has control over the new address.
* @param gauge address The Gauge to set distributor for
* @param reward_token address Token you are setting the distributor for
* @param distributor address The new distributor
*/
    function changeDistributor(
        address gauge,
        address reward_token,
        address distributor
    ) external onlyOwner {
        IChildChainGauge(gauge).set_reward_distributor(
            reward_token,
            distributor
        );
    }


    function getKeeperAddresses() external view returns (address[] memory) {
        return KeeperAddresses;
    }

/**
 * @notice Sets the keeper addresses
 * @param keeperAddresses The array of addresses of the keeper contracts, the 0 address anywhere in this list is a wildcard, all addresses can keep
 */
    function setKeeperAddresses(address[] memory keeperAddresses) external onlyOwner {
        emit KeeperRegistryAddressUpdated(KeeperAddresses, keeperAddresses);
        KeeperAddresses = keeperAddresses;
    }

/**
 * @notice Sets the minimum wait period (in seconds) for addresses between injections
 */
    function setMinWaitPeriodSeconds(uint256 period) external onlyOwner {
        emit MinWaitPeriodUpdated(MinWaitPeriodSeconds, period);
        MinWaitPeriodSeconds = period;
    }

/**
 * @notice Sets global MaxInjectionAmount for the injector
 * @param amount The max amount that the injector will allow to be paid to a single gauge in single programmed injection
 */
    function setMaxInjectionAmount(uint256 amount) external onlyOwner {
        emit MaxInjectionAmountUpdated(MaxInjectionAmount, amount);
        MaxInjectionAmount = amount;
    }

    function setMaxGlobalAmountPerPeriod(uint256 amount) external onlyOwner {
        emit MaxGlobalAmountPerPeriodUpdated(MaxGlobalAmountPerPeriod, amount);
        MaxGlobalAmountPerPeriod = amount;
    }

    function setMaxTotalDue(uint256 amount) external onlyOwner {
        emit MaxTotalDueUpdated(MaxTotalDue, amount);
        MaxTotalDue = amount;
    }
/**
 * @notice Pauses the contract, which prevents executing performUpkeep
 */
    function pause() external onlyOwner {
        _pause();
    }

/**
 * @notice Unpauses the contract
 */
    function unpause() external onlyOwner {
        _unpause();
    }

    modifier onlyKeeper() {
        if (KeeperAddresses.length > 0) {
            bool isKeeper = false;
            for (uint i = 0; i < KeeperAddresses.length; i++) {
                if (msg.sender == KeeperAddresses[i] || KeeperAddresses[i] == address(0)) {
                    isKeeper = true;
                    break;
                }
            }
            if (!isKeeper) {
                revert OnlyKeepers(msg.sender);
            }
        }
        _;
    }
}
