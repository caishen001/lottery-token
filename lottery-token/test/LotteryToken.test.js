const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LotteryToken", function () {
    let LotteryToken;
    let owner;
    let addr1;
    let vrfCoordinator;
    let linkToken;
    let keyHash;
    let fee;

    beforeEach(async function () {
        [owner, addr1] = await ethers.getSigners();
        vrfCoordinator = "0x8C7382F9D8f56b33781fE506E897a4F1e2d17255";
        linkToken = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
        keyHash = "0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4";
        fee = ethers.utils.parseEther("0.1");

        const LotteryTokenFactory = await ethers.getContractFactory("LotteryToken");
        LotteryToken = await LotteryTokenFactory.deploy(vrfCoordinator, linkToken, keyHash, fee);
        await LotteryToken.deployed();
    });

    it("Should mint a token with a unique code", async function () {
        await LotteryToken.mintToken("UNIQUE-CODE-1");
        const tokenId = 0;
        expect(await LotteryToken.tokenUniqueCode(tokenId)).to.equal("UNIQUE-CODE-1");
    });

    it("Should request a random winner", async function () {
        await LotteryToken.mintToken("UNIQUE-CODE-1");
        await LotteryToken.requestRandomWinner();
        // Chainlink VRF fulfillment is asynchronous, so we cannot test the result here.
    });

    it("Should update the prize pool", async function () {
        await owner.sendTransaction({ to: LotteryToken.address, value: ethers.utils.parseEther("1") });
        expect(await LotteryToken.prizePool()).to.equal(ethers.utils.parseEther("1"));
    });
});
