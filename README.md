# periodicRewardsInjector

## Intro
The ChildChainGaugeInjector is designed to manage weekly injections of non-bal tokens into  Child Chain layer zero gauges based on a predefined keeper using chainlink keepers.
It is meant to be deployed for a single ERC20 reward token, but can manage any number of gauges for that token.

It allows the configured admin to define a list of schedules, and then can be operated by [Chainlink Automation](https://automation.chain.link/).

Methods exists to add new schedules without implicating the already running schedules for a gauge.

The contract also includes functionality for the owner to sweep ERC20 tokens and gas tokens in order to allow the contract to be easily decommissioned should there be any issues or it is no longer needed.


### The Child Chain Gauge runs on weekly epochs:

- Only the defined distributor for a given token may inject rewards.  
- The injector uses changes to period_finish on the gauge contract to understand epochs and runs once per epoch as early as possible.

This contract is intended to operate as the distributor, and has functionality to return distributorship to the owner

### The watchlist

The injector runs using a watch list. The watch list is defined as the tuple of [gaugeAddress, amountPerPeriod, maxPeriods, doNotStartBeforeTimestamp].

For every streamer address, assuming a sufficent token balance, the injector will inject the specified amounts each epoch until it has done so maxPeriods time.

It's possible to add new recipients and configurations without altering or including the old ones (difference to v1).

This list is defined by calling the function `addRecipients(streamerAddresses, amountsPerPeriod, maxPeriods, doNotStartBeforeTimestamp)` on the deployed injector.


### Balances
The injector uses ERC20 balances in the injector contract to pay rewards.  The upkeeps will not run if there is not enough tokens in the contract to satisfy all currently due injections.

The following usage pattern can be followed to maintain proper balances at all times:

#### When setting schedule
- Transfer the exact amount required for the entire program (all streams, all amounts, all periods)
- Use `addRecipients(streamerAddresses, amountsPerPeriod, maxPeriods, doNotStartBeforeTimestamp)`


#### To abort a schedule midway through or reset
- Use `removeRecipients(recipients)` to one or multiple configurations from the list.
- Use `sweep(token)` to transfer any remaining tokens back to the owner.
- Now you can use the normal process to set a new schedule.

## Deployment and operations

### Dependancies/environment setup
This repo requires hardhat to work.

#### Install
```
npm install
```

Make sure you have npx installed.

```
npm install -g npx
```

#### Add .env
As the injector is integrated and works with existing gauges, the local hardhat environment forks the current Polygon network.
To do that it requires an alchemy key. If you would like to verify your contracts. Please add an API Key for Etherscan for each network.

```
ALCHEMY_KEY=XXX
ETHERSCAN_POLYGON_API_KEY=XXX
PRIVATE_KEY=XXX
```

#### Run tests
```
npx hardhat test
```

#### Adding new networks
You can add new networks in hardhat.config.js under the network tab.

### Deploying an injector
You can either deploy an injector using an already deployed factory in [scripts/deployInjectorWithFactory.js](./scripts/deployInjectorWithFactory.js) or you can deploy the injector on your own [scripts/deployInjector.js](./scripts/deployInjector.js).
You will need to edit it and change the following

- update ADMIN_ADDRESS to point to the address that should admin the injector
- update UPKEEP_CALLER_ADDRESS to point to the address of the chainlink registry keeper who will be calling this address. You can find the Chainlink registry addresses here: [Chainlink Docs](https://docs.chain.link/chainlink-automation/supported-networks/#configurations)
- update TOKEN_ADDRESS to be the token you want to be handled by this contract (note that the Balancer Maxi's must whitelist a token on a gauge before it can be distributed).
- update MIN_WAIT_PERIOD if needed. Default is 6 days. This is the minimum wait period for injections for an address between funding (for security)

Once everything looks good run `npx hardhat run scripts/deployInjectorWithFactory.js --network <network name>` or `npx hardhat run scripts/deployInjector.js --network <network name>`.

This should deploy the contract and return the deployed address.  Write it down/check it on etherscan and make sure it is there.

Now verify the contract with `npx hardhat verify --network <network name> <DEPLOYED_ADDRESS>`.

For example `npx hardhat verify --network polygon 0xb7aCdc1Ae11554dfe98aA8791DCEE0F009155D5e`.


#### Accepting Admin
Ownership of the injector is accepted by running acceptOwnership() on the contract from an address that has been granted ownership by the prior owner.
If the owner is an EOA, that address can use etherscan.


#### Registering the upkeep with chainlink
Registering a chainlink upkeep involves paying some money into the chainlink registrar.  After that, chainlink will check
the contract each block to see if it is ready to run.  When it signifies it is, it will run the specified call data and execute the transfer and notify.
Note that as part of this process some LINK must be paid into the upkeep contract.  For sidechains, 3 LINK should usually be enough.  These steps assume the specified link is sitting in the multisig where the payload is executed.

The resulting payload should register the upkeep. You can then find your registed upkeep by going to [Chainlink automation dashboard](https://automation.chain.link/arbitrum).  Select the chain you deployed on.  Then scroll down to recent upkeeps.  The name you specified should show up at or near the top of that list.  Click on it.
Write down that link and/or the upkeep id.  This is the page where you can monitor your link balance.  To topup, connect to this dapp with wallet connect and use the top-up action to send in more link.  You can also stop the automation and recover deposited and unspent link this way.
