const { ethers, upgrades } = require("hardhat");
const {BN, expectEvent, time, expectRevert} = require('@openzeppelin/test-helpers');
const { expect } = require("chai");

const toWei = (value) => web3.utils.toWei(String(value));
const LINK = "0x514910771AF9Ca656af840dff83E8264EcF986CA";


describe("Lottery", () => {
    let lottery;
    let admin;
    let alice;
    let bob;
    let random;


    before(async () => {
        [admin, alice, bob, random] = await ethers.getSigners();
        const Lottery = await ethers.getContractFactory("Lottery");

        lottery = await upgrades.deployProxy(Lottery, [admin.address]);
        await lottery.deployed();
    });


    describe("Token", () => {
        it("should get balance of contract", async () => {
            expect(Number(await lottery.getBalance())).to.equal(0);
        });
    });
});