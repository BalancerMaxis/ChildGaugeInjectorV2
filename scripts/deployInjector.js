const hre = require("hardhat");

const ADMIN_ADDRESS = "0xc38c5f97B34E175FFd35407fc91a937300E33860" // Balancer Maxi LM Multisig on polygon
const UPKEEP_CALLER_ADDRESSES = ["0x08a8eea76D2395807Ce7D1FC942382515469cCA1"] // Chainlink Registry on polygon
const TOKEN_ADDRESS = "0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3" // BAL on BASE
const MIN_WAIT_PERIOD = 60 * 60 * 6; // 6 days
const MAX_INJECTION_REWARD = 1000;

async function main() {
    const Injector = await hre.ethers.getContractFactory("ChildChainGaugeInjectorV2");
    const injector = await Injector.deploy();

    await injector.waitForDeployment();

    console.log("Injector deployed to:", await injector.getAddress());

    await injector.initialize(ADMIN_ADDRESS, UPKEEP_CALLER_ADDRESSES, MIN_WAIT_PERIOD, TOKEN_ADDRESS, MAX_INJECTION_REWARD);
    console.log("Injector initialized with values:", {
        ADMIN_ADDRESS,
        UPKEEP_CALLER_ADDRESSES,
        MIN_WAIT_PERIOD,
        TOKEN_ADDRESS,
        MAX_INJECTION_REWARD
    });
}


main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });