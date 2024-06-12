const {expect, assert} = require("chai");
const hre = require("hardhat");
const gaugeABI = require('../abis/abigauge.json');
const authorizerABI = require('../abis/authadaptabi.json');
const erc20ABI = require('../abis/erc20.json');

const GAUGE = "0x3Eae4a1c2E36870A006E816930d9f55DF0a72a13"
const GAUGE_2 = "0xc7e5FE004416A96Cb2C7D6440c28aE92262f7695"
const LM_MULTISIG = "0xc38c5f97B34E175FFd35407fc91a937300E33860"
const ARBI_LDO_ADDRESS = "0xC3C7d422809852031b44ab29EEC9F1EfF2A58756"
const AUTHORIZER_ADAPTER = "0xAB093cd16e765b5B23D34030aaFaF026558e0A19"
const ARBI_LDO_WHALE = "0x8565faab405b06936014c8b6bd5ab60376cc051b"


async function impersonateAccount(address) {
    return await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    });
}

const currentChainTime = async () => {
    const block = await hre.ethers.provider.getBlock("latest");
    return block.timestamp;
};

describe('ChildChainGaugeInjector', () => {
    let injector
    let owner, addr1, addr2
    let token;
    let gauge;
    let gauge2;

    before(async () => {
        const [ownerSigner, addr1Signer, addr2Signer] = await hre.ethers.getSigners();
        owner = ownerSigner;
        addr1 = addr1Signer;
        addr2 = addr2Signer;

        // Deploy the contract
        const ChildChainGaugeInjector = await hre.ethers.getContractFactory('ChildChainGaugeInjectorV2');
        injector = await ChildChainGaugeInjector.deploy();
        await injector.initialize(
            await owner.getAddress(),
            [await owner.getAddress()],
            3600, // 1 hour min wait period
            ARBI_LDO_ADDRESS,
            BigInt("500000000000000000000")
        );

        const balance = await hre.ethers.provider.getBalance(ownerSigner.address)
        console.log(`Balance of ${ownerSigner.address}:`, hre.ethers.formatEther(balance), "MATIC");

        await ownerSigner.sendTransaction({
            to: LM_MULTISIG,
            value: hre.ethers.parseEther("100")
        });

        await impersonateAccount(LM_MULTISIG);
        const lmMultisigSigner = await hre.ethers.getSigner(LM_MULTISIG);

        gauge = new hre.ethers.Contract(GAUGE, gaugeABI, lmMultisigSigner);
        gauge2 = new hre.ethers.Contract(GAUGE_2, gaugeABI, lmMultisigSigner);

        const authorizer = new hre.ethers.Contract(AUTHORIZER_ADAPTER, authorizerABI, lmMultisigSigner)

        const calldata = gauge.interface.encodeFunctionData("add_reward", [ARBI_LDO_ADDRESS, await injector.getAddress()]);
        await authorizer.performAction(
            GAUGE,
            calldata
        );
        await authorizer.performAction(
            GAUGE_2,
            calldata
        );

        await impersonateAccount(ARBI_LDO_WHALE);
        const whaleSigner = await hre.ethers.getSigner(ARBI_LDO_WHALE);
        token = new hre.ethers.Contract(ARBI_LDO_ADDRESS, erc20ABI, whaleSigner)

        await token.transfer(owner, hre.ethers.parseEther("1000"))
        console.log(`Balance LDO: ${hre.ethers.formatEther(await token.balanceOf(owner))}`);

    });

    it('should pause and unpause the contract', async () => {
        await injector.pause();
        expect(await injector.paused()).to.be.true;

        await injector.unpause();
        expect(await injector.paused()).to.be.false;
    });

    it('should not allow non-owner to pause or unpause', async () => {
        const injectorConnected = injector.connect(addr1);
        const addr1Address = await addr1.getAddress();

        try {
            await injectorConnected.pause();
            expect.fail('Expected an error but did not get one');
        } catch (error) {
            assert.include(error.message, "OwnableUnauthorizedAccount")
            assert.include(error.message, addr1Address)
        }
    });

    it("should calculate spend for timestamp correctly", async function () {
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        const weeklyIncentive = BigInt("200000000000000000000");
        await injector.addRecipients([gauge], weeklyIncentive, 2, 0)

        const currentTime = Math.floor(Date.now() / 1000);
        const oneWeekInSeconds = 7 * 24 * 60 * 60;
        const timestampOneWeekFromNow = currentTime + oneWeekInSeconds;

        let spend = await injector.estimateSpendUntilTimestamp(timestampOneWeekFromNow)
        expect(spend).to.equal(400000000000000000000n);

        await injector.addRecipients([gauge2], weeklyIncentive, 2, 0)

        spend = await injector.estimateSpendUntilTimestamp(timestampOneWeekFromNow)
        expect(spend).to.equal(800000000000000000000n);

        spend = await injector.estimateSpendUntilTimestamp(timestampOneWeekFromNow * 52)
        expect(spend).to.equal(800000000000000000000n);

        await injector.removeRecipients([gauge2])

        spend = await injector.estimateSpendUntilTimestamp(timestampOneWeekFromNow)
        expect(spend).to.equal(400000000000000000000n);
    });

    it("should add a recipient and check the gauge list", async function () {
        const recipients = [GAUGE];
        const amounts = 100;
        const periods = 3;

        // Set the recipient list
        await injector.connect(owner).addRecipients(recipients, amounts, periods, 0);

        // Check the watch list
        expect(await injector.getActiveGaugeList()).to.deep.equal(recipients);

        // Check the account info
        const accountInfo = await injector.getGaugeInfo(GAUGE);
        expect(accountInfo.amountPerPeriod).to.equal(100);
        expect(accountInfo.isActive).to.be.true;
        expect(accountInfo.maxPeriods).to.equal(3);
        expect(accountInfo.periodNumber).to.equal(0);
        expect(accountInfo.lastInjectionTimestamp).to.equal(0);
        expect(accountInfo.doNotStartBeforeTimestamp).to.equal(0);
    });

    it("should be able to call check upkeep", async function () {
        const {upkeepNeeded, performData} = await injector.checkUpkeep("0x");

        expect(typeof upkeepNeeded).to.equal('boolean');
        expect(typeof performData).to.equal('string');
        // Checking if performData is a valid hexadecimal string
        expect(performData).to.match(/^0x[a-fA-F0-9]+$/, 'performData should be a valid hexadecimal string')
    });

    it("should sweep only be callable by owner", async function () {
        try {
            await injector.connect(addr1).sweep(await token.getAddress(), addr1.address);
            expect.fail('Expected an error but did not get one');
        } catch (error) {
            assert.include(error.message, "OwnableUnauthorizedAccount")
        }
    });

    it("should checkSufficientBalances and return false", async function () {
        const injectorAddress = await injector.getAddress();

        await impersonateAccount(injectorAddress);
        const injectorSigner = await hre.ethers.getSigner(injectorAddress);

        token.connect(injectorSigner).transfer(injectorAddress, await token.balanceOf(injectorAddress))
        expect(await token.balanceOf(injectorAddress)).to.equal(0)

        token.connect(owner).transfer(injector.address, 500 * 10 ** 18)

        injector.addRecipients([gauge, gauge2], 150 * 10 ** 18, 10)
        expect(await injector.getBalanceDelta()).to.lessThanOrEqual(0);
    });

    it("should sweep correctly", async function () {
        const ownerBalance = await token.balanceOf(owner.address);
        const injectorBalance = await token.balanceOf(await injector.getAddress())
        const systemBalance = ownerBalance + injectorBalance;

        expect(ownerBalance).to.be.gt(0);

        // Transfer all tokens from admin to injector
        await token.connect(owner).transfer(await injector.getAddress(), ownerBalance);

        expect(await token.balanceOf(owner.address)).to.equal(0);

        // Sweeping the tokens back to admin
        await injector.connect(owner).sweep(await token.getAddress(), owner.address);

        const newAdminBalance = await token.balanceOf(owner.address);
        expect(newAdminBalance).to.be.gte(ownerBalance);

        const newInjectorBalance = await token.balanceOf(await injector.getAddress());
        const newSystemBalance = newInjectorBalance + newAdminBalance;
        expect(newSystemBalance).to.equal(systemBalance);
    });

    it("should perform upkeep flow", async function () {
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        const weeklyIncentive = BigInt("200000000000000000000");
        expect(await token.balanceOf(injectorAddress)).to.equal(0);
        await token.transfer(injectorAddress, weeklyIncentive * 3n)
        await injector.addRecipients([gauge], weeklyIncentive, 2, 0)
        const rewardData = await gauge.reward_data(tokenAddress);

        let [upkeepNeeded, performData] = await injector.checkUpkeep("0x");

        if (!upkeepNeeded) {
            const sleepTime = BigInt(rewardData[1]) - BigInt(await currentChainTime());
            await hre.ethers.provider.send("evm_increaseTime", [sleepTime.toString()]);
            await hre.ethers.provider.send("evm_mine");

            const {upkeepNeeded, performData} = await injector.checkUpkeep("0x");

            expect(upkeepNeeded).to.equal(true);
        }

        const initialGaugeBalance = await token.balanceOf(gaugeAddress);

        expect(await token.balanceOf(injectorAddress)).to.gte(weeklyIncentive);
        expect(await injector.performUpkeep(performData))

        expect(await token.balanceOf(gaugeAddress)).to.equal(initialGaugeBalance + weeklyIncentive);
        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(false);

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 8]);
        await hre.ethers.provider.send("evm_mine");
        console.log(await currentChainTime());

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(true);

        const initialBalance = await token.balanceOf(gaugeAddress);
        await injector.performUpkeep(performData);
        expect(await token.balanceOf(gaugeAddress) - initialBalance).to.equal(weeklyIncentive);

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(false);

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 8]);
        await hre.ethers.provider.send("evm_mine");
        console.log(await currentChainTime());

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(false);
    });

    it("should not run too soon", async function () {
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        const weeklyIncentive = BigInt("200000000000000000000");
        await injector.addRecipients([gauge], weeklyIncentive, 2, 0)

        await token.transfer(injectorAddress, weeklyIncentive * 2n)
        let rewardData = await gauge.reward_data(tokenAddress);
        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        if (!upkeepNeeded) {
            const sleepTime = BigInt(rewardData[1]) - BigInt(await currentChainTime());
            await hre.ethers.provider.send("evm_increaseTime", [sleepTime.toString()]);
            await hre.ethers.provider.send("evm_mine");
            const {upkeepNeeded, performData} = await injector.checkUpkeep("0x");
            expect(upkeepNeeded).to.equal(true);
        }
        expect(await token.balanceOf(injectorAddress)).to.greaterThanOrEqual(weeklyIncentive)
        await injector.performUpkeep(performData);
        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        rewardData = await gauge.reward_data(tokenAddress);
        [distributor, periodFinished, rate, lastUpdated, integral] = rewardData;
        let sleepTime = Math.floor(Math.random() * 60 * 60 * 24 * 6) + 1;
        await hre.ethers.provider.send("evm_increaseTime", [sleepTime]);
        await hre.ethers.provider.send("evm_mine");
        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(false);

        sleepTime = BigInt(rewardData[1]) - BigInt(await currentChainTime());
        await hre.ethers.provider.send("evm_increaseTime",[sleepTime.toString()]);
        await hre.ethers.provider.send("evm_mine");
        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(true);
    });

    it("should work with a long delay", async function () {
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        const weeklyIncentive = BigInt("200000000000000000000");
        const transferAmount = BigInt("200000000000000000000");
        await injector.addRecipients([gauge], weeklyIncentive, 2, 0)
        await token.transfer(injectorAddress, transferAmount)
        let rewardData = await gauge.reward_data(tokenAddress);

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        if (!upkeepNeeded) {
            const sleepTime = BigInt(rewardData[1]) - BigInt(await currentChainTime());
            await hre.ethers.provider.send("evm_increaseTime", [sleepTime.toString()]);
            await hre.ethers.provider.send("evm_mine");
            const {upkeepNeeded, performData} = await injector.checkUpkeep("0x");
            expect(upkeepNeeded).to.equal(true);
        }
        expect(await token.balanceOf(injectorAddress)).to.greaterThanOrEqual(weeklyIncentive)
        let sleepTime = Math.floor(Math.random() * ((60*60*24*365) - (60*60*4) + 1)) + (60*60*4);
        await hre.ethers.provider.send("evm_increaseTime", [sleepTime]);
        await hre.ethers.provider.send("evm_mine");
        await injector.performUpkeep(performData);

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(false);
    });

    it("should not work with short delay", async function () {
        await hre.ethers.provider.send("evm_increaseTime", [Math.floor(Math.random() * ((60*60*24*365) - (60*60*4) + 1)) + (60*60*4)]);
        await hre.ethers.provider.send("evm_mine");
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        const weeklyIncentive = BigInt("200000000000000000000");
        const transferAmount = BigInt("200000000000000000000");

        await token.transfer(injectorAddress, transferAmount)
        let rewardData = await gauge.reward_data(tokenAddress);

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        if (!upkeepNeeded) {
            const sleepTime = BigInt(rewardData[1]) - BigInt(await currentChainTime());
            await hre.ethers.provider.send("evm_increaseTime", [sleepTime.toString()]);
            await hre.ethers.provider.send("evm_mine");
            const {upkeepNeeded, performData} = await injector.checkUpkeep("0x");
            expect(upkeepNeeded).to.equal(true);
        }
        expect(await token.balanceOf(injectorAddress)).to.greaterThanOrEqual(weeklyIncentive)
        await injector.performUpkeep(performData);

        let sleepTime = Math.floor(Math.random() * ((60 * 60 * 24 * 7 - 1) - 1 + 1)) + (1);
        await hre.ethers.provider.send("evm_increaseTime", [sleepTime]);
        await hre.ethers.provider.send("evm_mine");

        [upkeepNeeded, performData] = await injector.checkUpkeep("0x");
        expect(upkeepNeeded).to.equal(false);
    });

    it("should handle manual deposit correctly", async function () {
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        const amount = hre.ethers.parseEther("100");

        await token.connect(owner).transfer(injectorAddress, hre.ethers.parseEther("500"));

        // Perform the manual deposit
        await injector.connect(owner).manualDeposit(gaugeAddress, tokenAddress, amount);

        // Retrieve the reward data and check the timestamp
        const rewardData = await gauge.reward_data(tokenAddress);
        expect(rewardData.lastUpdateTime).to.equal(await hre.ethers.provider.getBlock('latest').timestamp);
    });


    it("should set distributor to owner correctly", async function () {
        const tokenAddress = await token.getAddress();
        const gaugeAddress = await gauge.getAddress();
        const injectorAddress = await injector.getAddress();

        let rewardData = await gauge.reward_data(tokenAddress);

        expect(rewardData.distributor).to.equal(injectorAddress);
        await injector.connect(owner).changeDistributor(gaugeAddress, tokenAddress, owner.address);

        rewardData = await gauge.reward_data(tokenAddress);
        expect(rewardData.distributor).to.equal(await injector.owner());
    });

    it('should set and retrieve keeper registry address correctly', async () => {
        const newKeeperAddress = await addr1.getAddress();
        await injector.setKeeperAddresses([newKeeperAddress]);
        const keeperAddresses = await injector.getKeeperAddresses();

        expect(keeperAddresses).to.include(newKeeperAddress);
    });

});
