import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { SparkbloxFactory, SparkbloxRegistry } from "typechain/contracts";
import { contractAddr } from "../contractAddr"

async function main() {
  const [account]: SignerWithAddress[] = await ethers.getSigners();
  console.log(account.address, ":", ethers.utils.formatEther(await account.getBalance()));

  const addrForwarder: string = contractAddr.Forwarder;
  const addrRegistry: string = contractAddr.Registry;

  const sbRegistry: SparkbloxRegistry = await ethers.getContractAt("SparkbloxRegistry", addrRegistry);

  const isAdminOnRegistry: boolean = await sbRegistry.hasRole(
    // ethers.utils.solidityKeccak256(["string"], ["DEFAULT_ADMIN_ROLE"]),
    "0x0000000000000000000000000000000000000000000000000000000000000000", 
    account.address
  );
  if (!isAdminOnRegistry) {
    throw new Error("Account is not admin on registry");
  }

  const sbFactory: SparkbloxFactory = await ethers
    .getContractFactory("SparkbloxFactory")
    .then(f => f.deploy(addrForwarder, addrRegistry));
  
  console.log(
    "Deploying SparkbloxFactory contract:", sbFactory.deployTransaction.hash,
    "Address:", sbFactory.address
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
