const { ethers, upgrades } = require("hardhat");
const {BN, expectEvent, time, expectRevert} = require('@openzeppelin/test-helpers');
const { expect } = require("chai");
//const { verifyMessage } = require("@ethersproject/wallet");

const toWei = (value) => web3.utils.toWei(String(value));
const LINK = "0x514910771AF9Ca656af840dff83E8264EcF986CA";
const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

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
    let admin;
    let alice;
    let bob;
    let random;


    before(async () => {
        [admin, alice, bob, random] = await ethers.getSigners();

        // LINK CONTRACT
        link = await ethers.getContractAt("IERC20", LINK);

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
        lottery = await upgrades.deployProxy(Lottery, [admin.address, vrfCoordinator.address, 5]);
        await lottery.deployed();
    });


    describe("Random number", () => {
        it("should get a random number", async () => {
            const distribution = [3000, 7000]; // 30% and 70%
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
    });


    describe("Lottery", () => {
        it("should lottery",  async () => {
            
        });
    });
});