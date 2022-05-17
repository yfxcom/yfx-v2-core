const {ethers, upgrades} = require("hardhat");

let WHT = "0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F"

async function main() {
    let [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    let overrides = {gasLimit: 10000000, gasPrice: 2250000000};

    const Manager = await ethers.getContractFactory('Manager');
    const manager = await Manager.deploy(deployer.address);
    await manager.deployed();
    console.log("manager:" + manager.address);

    const User = await ethers.getContractFactory('User');
    const user = await User.deploy(manager.address, WHT);
    await user.deployed();
    console.log("user:" + user.address);

    const MarketCalc = await ethers.getContractFactory('MarketCalc');
    const marketCalc = await MarketCalc.deploy();
    await marketCalc.deployed();
    console.log("MarketCalc:" + marketCalc.address);

    const Router = await ethers.getContractFactory('Router');
    const router = await Router.deploy(manager.address, marketCalc.address);
    await router.deployed();
    console.log("router:" + router.address);

    const MakerFactory = await ethers.getContractFactory('MakerFactory');
    const makerFactory = await MakerFactory.deploy(manager.address);
    await makerFactory.deployed();
    console.log("maker:" + makerFactory.address);

    const MarketFactory = await ethers.getContractFactory('MarketFactory');
    const marketFactory = await MarketFactory.deploy(manager.address, marketCalc.address);
    await marketFactory.deployed();
    console.log("market:" + marketFactory.address);

    let r;
    r = await manager.connect(deployer).notifyTaker(user.address, overrides);
    r = await manager.connect(deployer).notifySigner(deployer.address, overrides);
    r = await manager.connect(deployer).notifyController(deployer.address, overrides);
    r = await manager.connect(deployer).notifyFeeOwner(deployer.address, overrides);
    r = await manager.connect(deployer).notifyRiskFundingOwner(deployer.address, overrides);
    r = await manager.connect(deployer).notifyPoolFeeOwner(deployer.address, overrides);
    r = await manager.connect(deployer).changeCancelBlockElapse(100, overrides);
    r = await manager.connect(deployer).changeOpenLongBlockElapse(200, overrides);
    r = await manager.connect(deployer).notifyRouter(router.address, overrides);
    r = await manager.connect(deployer).unpause(overrides);
    r = await user.connect(deployer).addToken(WHT, overrides);
    console.log(r.hash);
}

main().then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
