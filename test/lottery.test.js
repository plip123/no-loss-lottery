const { ethers, upgrades } = require("hardhat");
const {BN, expectEvent, time, expectRevert} = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
//const { verifyMessage } = require("@ethersproject/wallet");

const toWei = (value) => web3.utils.toWei(String(value));
const LINK = "0x514910771AF9Ca656af840dff83E8264EcF986CA";
const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const USDT = "0xdac17f958d2ee523a2206206994597c13d831ec7";

// Aave Pools
const ADAI_ADDRESS = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";
const AUSDC_ADDRESS = "0xBcca60bB61934080951369a648Fb03DF4F96263C";
const AUSDT_ADDRESS = "0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811";
const ATUSD_ADDRESS = "0xA361718326c15715591c299427c62086F69923D9";
const ABUSD_ADDRESS = "0xA361718326c15715591c299427c62086F69923D9";
const LENDING_POOL_ADDRESS = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";

describe("Lottery", () => {
    let lottery;
    let swapper;
    let vrfCoordinator;
    let link;
    let dai;
    let usdt;
    let admin;
    let alice;
    let bob;
    let random;


    before(async () => {
        [admin, alice, bob, random] = await ethers.getSigners();

        // LINK CONTRACT
        link = await ethers.getContractAt("IERC20", LINK);
        // DAI
        dai = await ethers.getContractAt("IERC20", DAI);
        // USDT
        usdt = await ethers.getContractAt("IERC20", USDT);

        // Swapper
        const Swapper = await ethers.getContractFactory("Swapper");
        swapper = await upgrades.deployProxy(Swapper, [admin.address, 10]);
        await swapper.deployed();

        // VRFCoordinator Mock
        const VrfCoordinator = await ethers.getContractFactory("VRFCoordinatorMock");
        vrfCoordinator = await VrfCoordinator.deploy(LINK);
        await vrfCoordinator.deployed();

        // Lottery contract
        const Lottery = await ethers.getContractFactory("Lottery");
        lottery = await upgrades.deployProxy(Lottery, [admin.address, vrfCoordinator.address]);
        await lottery.deployed();
    });


    describe("Lottery", () => {
        it("should get a random number", async () => {
            const distribution = [5000, 5000]; // 50% and 50%
            const tokens = [DAI, LINK];
            await swapper
            .connect(alice)
            .swap(tokens, distribution, { value: toWei(1) });
            let balanceLINK = await link.balanceOf(alice.address);
            await link.connect(alice).transfer(lottery.address, balanceLINK);
            balanceLINK = await link.balanceOf(alice.address);
            const lotteryLINK = await link.balanceOf(lottery.address);

            const transaction = await lottery.getRandomNumber();
            const tx_receipt = await transaction.wait();
            const requestId = tx_receipt.events[2].topics[0];
            const randomNumber = Math.floor(Math.random() * 999999999999999) + 1;

            await vrfCoordinator.callBackWithRandomness(
                requestId,
                ethers.BigNumber.from(randomNumber),
                lottery.address
            );
            expect(Number(await lottery.winnerNumber())).to.equal(randomNumber)
        });


        it("should open the lottery",  async () => {
            await expect(lottery.connect(admin).openLottery(DAI, LENDING_POOL_ADDRESS, 5))
            .to.emit(lottery, 'OpenLottery')
            .withArgs(1, 0, DAI, 5);
        });


        it("should buy a ticket",  async () => {
            const distribution = [3000, 7000]; // 30% and 70%
            const tokens = [DAI, USDT];
            await swapper
            .connect(alice)
            .swap(tokens, distribution, { value: toWei(1) });
            const beforeBalance = await dai.balanceOf(alice.address);
            await dai.connect(alice).approve(lottery.address, String(beforeBalance));

            await expect(lottery.connect(alice).buyTicket(DAI))
            .to.emit(lottery, 'NewPlayer')
            .withArgs(alice.address, 1, 1);
        });


        it("The same player should not be allowed to buy a second ticket.",  async () => {
            let errStatus = false;
            try {
                await expect(lottery.connect(alice).buyTicket(USDT))
                .to.emit(lottery, 'NewPlayer')
                .withArgs(alice.address, 1, 1);
            } catch(e) {
                assert(e.toString().includes('You are participating in this lottery'));
                errStatus = true;
            }
            assert(errStatus, 'No failure when the user tried to buy another ticket');
            
        });


        it("should let another player buy a ticket", async () => {
            const distribution = [3000, 7000]; // 30% and 70%
            const tokens = [DAI, USDT];
            await swapper
            .connect(bob)
            .swap(tokens, distribution, { value: toWei(1) });
            const beforeBalance = await dai.balanceOf(bob.address);
            await dai.connect(bob).approve(lottery.address, String(beforeBalance));

            await expect(lottery.connect(bob).buyTicket(DAI))
            .to.emit(lottery, 'NewPlayer')
            .withArgs(bob.address, 2, 1);
        });


        it("should start a lottery", async () => {
            const block = await ethers.provider.getBlock();
            const days = 24 * 60 * 60;

            // 2 days later
            // await ethers.provider.send("evm_increaseTime", [days])
            // await ethers.provider.send("evm_mine");
            for (let i = 0; i < 2; i++) {
                await ethers.provider.send("evm_increaseTime", [days])
                await ethers.provider.send("evm_mine");
            }
            
            await expect(lottery.connect(admin).startLottery())
            .to.emit(lottery, 'StartLottery')
            .withArgs(1, 1, 10, 2);
        });


        it("should close lottery and announce winner", async () => {
            const block = await ethers.provider.getBlock();
            const days = 24 * 60 * 60;

            // 5 days later
            // await ethers.provider.send("evm_increaseTime", [days])
            // await ethers.provider.send("evm_mine");
            for (let i = 0; i < 5; i++) {
                await ethers.provider.send("evm_increaseTime", [days])
                await ethers.provider.send("evm_mine");
            }

            let errStatus = false;
            try {
                await expect(lottery.connect(admin).closeLottery())
                .to.emit(lottery, 'CloseLottery')
                .withArgs(1, alice.address, 2, 2);
            } catch(e) {
                assert(e.toString().includes('expected'));
                errStatus = true;
            }
            assert(errStatus, 'It did not fail because the final winners result could have been different from the one shown.');
        });


        it("should claim the prize", async () => {
            await lottery.connect(bob).claim(1,2);
        });
    });
});