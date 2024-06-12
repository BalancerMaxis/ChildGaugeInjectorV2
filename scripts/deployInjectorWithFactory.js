const hre = require("hardhat");
const FACTORY_ABI = require("../artifacts/contracts/injectorFactoryV2.sol/ChildChainGaugeInjectorV2Factory.json")

const FACTORY_ADDRESS = "0x55b97552F113dED48feD75Bc4d9bBe26e7a47De2" // address of the deployed factory on your chain
const ADMIN_ADDRESS = "0xc38c5f97B34E175FFd35407fc91a937300E33860" // Balancer Maxi LM Multisig on polygon
const UPKEEP_CALLER_ADDRESS = ["0xc38c5f97B34E175FFd35407fc91a937300E33860"]
const TOKEN_ADDRESS = "0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3" // BAL on BASE
const MIN_WAIT_PERIOD = 60 * 60 * 6; // 6 days
const MAX_INJECTION_REWARD = 1000;

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const iface = new hre.ethers.Interface(FACTORY_ABI.abi);
    const injectorFactory = new hre.ethers.Contract(
        FACTORY_ADDRESS,
        FACTORY_ABI.abi,
        deployer
    )

    const tx = await injectorFactory.createInjector(UPKEEP_CALLER_ADDRESS, MIN_WAIT_PERIOD, TOKEN_ADDRESS, MAX_INJECTION_REWARD, ADMIN_ADDRESS);
    const receipt = await tx.wait();

    let injectorAddress;
    for (const log of receipt.logs) {
        if (log.fragment && log.fragment.name === 'InjectorCreated') {
            injectorAddress = log.args.injector;
            break;
        } else {
            try {
                const parsedLog = iface.parseLog(log);
                if (parsedLog.name === 'InjectorCreated') {
                    injectorAddress = parsedLog.args.injector;
                    break;
                }
            } catch (error) {
                // Ignore logs that do not match the event signature
            }
        }
    }

    if (injectorAddress) {
        console.log('Injector address:', injectorAddress);
    } else {
        console.error('InjectorCreated event not found in the transaction logs.');
    }

    console.log("Injector initialized with values:", {
        ADMIN_ADDRESS,
        UPKEEP_CALLER_ADDRESS,
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