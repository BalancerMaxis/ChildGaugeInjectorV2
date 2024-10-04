## Child Chain Gauge Injector V2

The ChildChainGaugeInjectorV2 was built to encapsulate over a year of learnings that came from operating Injector V1 in the wild.  The primary goal of this contract is to provide a more flexible and robust system for scheduling a steady stream of single token rewards to ChildChainGauges.  

The contract is designed to be a distributor for the ChildChainGauge, and has functionality to return distributorship to the owner.  The owner is also able to sweep all funds.
 
In such, this contract is not at all intended to be an onchain promise, but more of a way to automate the distribution of rewards to the ChildChainGauge.  The contract is designed to be operated by a Chainlink Keeper, and the owner is able to add new schedules without implicating the already running schedules for a gauge.  It can easily be used with other keepers that adapt to the chainlink interface.

The primary changes in this contract from V1 are: 

 - Modular configuration, the owner can adjust 1 schedule at a time instead of always overwriting the whole list.
 - More safeguards to enable the owner to prevent accidental scheduling mistakes therefore overspending budgets in the injector.
   - maxInjectionAmount: Don't inject more than this in a single tx ever.
   - maxInjectionAmountPerPeriod: Do not allow schedule changes that would lead the sum of all active schedules for one period to exceed this amount.
   - maxTotalDue: Do not allow schedule changes that would lead the sum of all active schedules for all remaining periods to exceed this amount.



## Deploying an injector using the factory
Go to the factory contract on the chain you need on etherscan, and call createInjector with the following parameters:

| Parameter            | Description                                                                                                                                                                                       |
|----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| keeperAddress[]      | A list of addresses that can trigger a due injection.  To start perhaps add your EOA, can include zero address in list to allow anyone to upkeep.                                                 |
| minWaitPeriodSeconds | A gauge should only be ready every 7 days.  This is a safeguard against something that should never happen, by default set to 6 days or 518400                                                    |
| injectTokenAddress | An Injector runs on a single token.  Specify which one here.  For multiple tokens use multiple injectors                                                                                          |
 | maxInjectionAmount | The maximum amount of tokens that can be injected in a single transaction. Set it to something sane for your token/budget or 0 for no limit.  This is to prevent catostrophic scehduling mistakes |
 | owner| The owner of the injector.  This address can add and remove schedules, and sweep tokens.  Can be changed, if you're not sure set to your EOA.                                                     |



