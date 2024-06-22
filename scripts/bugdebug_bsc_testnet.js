const { ethers } = require("hardhat");

async function main() {
  // Replace this with your personal test address
  const userAddress = "0x31cC93F11435fe9aB8E6F525214D1ccd5B987396";

  // Token and staking contract addresses
  const tokenAddress = "0xCb4F259fD81Ea1EDAD42022710f75e15c9b510D8";
  const stakingAddress = "0x43D03FD3b833989288C98D9304118738937111f3";

  // Get the token and staking contract factories
  const WBNRY = await ethers.getContractFactory("WBNRY");
  const token = WBNRY.attach(tokenAddress);

  const Staking = await ethers.getContractFactory("Staking");
  const staking = Staking.attach(stakingAddress);

  const tokenAmount = ethers.utils.parseUnits("10", 8); // Adjust the amount and decimals as needed

  // Use ethers.provider to interact with the network
  const provider = ethers.provider;

  // Check balance and allowance
  const balance = await token.balanceOf(userAddress);
  console.log(`User Balance: ${balance.toString()}`);
  const allowance = await token.allowance(userAddress, stakingAddress);
  console.log(`Allowance: ${allowance.toString()}`);

  // Ensure approval
  if (allowance.lt(tokenAmount)) {
    const userSigner = provider.getSigner(userAddress);
    const approveTx = await token.connect(userSigner).approve(stakingAddress, tokenAmount);
    await approveTx.wait();
    console.log("Tokens approved");
  }

  // Attempt to stake
  try {
    const userSigner = provider.getSigner(userAddress);
    const stakeTx = await staking.connect(userSigner).stake(tokenAmount, { gasLimit: 300000 });
    await stakeTx.wait();
    console.log("Tokens staked successfully");
  } catch (error) {
    console.error("Staking failed:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
