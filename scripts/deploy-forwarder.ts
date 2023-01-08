import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Forwarder } from "typechain/contracts/extensions";

async function main() {
  const [account]: SignerWithAddress[] = await ethers.getSigners();
  console.log(account.address, ":", ethers.utils.formatEther(await account.getBalance()));

  const forwarder: Forwarder = await ethers
    .getContractFactory("Forwarder")
    .then(f => f.deploy());

  console.log(
    "Deploying Forwarder contract:", forwarder.deployTransaction.hash,
    "Address:", forwarder.address
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
