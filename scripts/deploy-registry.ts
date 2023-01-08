import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { SparkbloxRegistry } from "typechain/contracts";
import { contractAddr } from "../contractAddr"

async function main() {
  const [account]: SignerWithAddress[] = await ethers.getSigners();
  console.log(account.address, ":", ethers.utils.formatEther(await account.getBalance()));

  const addrForwarder: string = contractAddr.Forwarder;

  const sbRegistry: SparkbloxRegistry = await ethers
    .getContractFactory("SparkbloxRegistry")
    .then(f => f.deploy(addrForwarder));

  console.log(
    "Deploying SparkbloxRegistry contract:", sbRegistry.deployTransaction.hash,
    "Address:", sbRegistry.address
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
