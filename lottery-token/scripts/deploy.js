const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const vrfCoordinator = "0x8C7382F9D8f56b33781fE506E897a4F1e2d17255";
    const linkToken = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
    const keyHash = "0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4";
    const fee = hre.ethers.utils.parseEther("0.1");

    const LotteryToken = await hre.ethers.getContractFactory("LotteryToken");
    const lotteryToken = await LotteryToken.deploy(vrfCoordinator, linkToken, keyHash, fee);

    await lotteryToken.deployed();

    console.log("LotteryToken deployed to:", lotteryToken.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
