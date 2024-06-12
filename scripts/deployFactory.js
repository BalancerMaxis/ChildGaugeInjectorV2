const hre = require("hardhat");

const TEMPLATE_CONTRACT_ADDRESS = "0x2F7cD58EBDd5e8f179bde21720eD12429F399a98" // address of a deployed injector on the same chain

async function main() {
    const InjectorFactory = await hre.ethers.getContractFactory("ChildChainGaugeInjectorV2Factory");
    const injectorFactory = await InjectorFactory.deploy(TEMPLATE_CONTRACT_ADDRESS);

    await injectorFactory.waitForDeployment();

    console.log("InjectorFactory deployed to:", await injectorFactory.getAddress());
}


main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });