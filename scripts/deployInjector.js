const hre = require("hardhat");

const ADMIN_ADDRESS = "0x854B004700885A61107B458f11eCC169A019b764" // Zen
const UPKEEP_CALLER_ADDRESSES = ["0x854B004700885A61107B458f11eCC169A019b764"] // Zen
const TOKEN_ADDRESS = "0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035" // USDC on zkevm
const MIN_WAIT_PERIOD = 60 * 60 * 6; // 6 days
const MAX_INJECTION_REWARD = 5;

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