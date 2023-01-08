import {ethers, upgrades } from "hardhat";
import {getImplementationAddress} from "@openzeppelin/upgrades-core";
const proxyAddress = "0xBB98a3269dab1898d4E1eECa34E7d51B09badd12";

async function main() {
    console.log(proxyAddress, "original NFTCollection (proxy) address");
    const originImpAddress = await getImplementationAddress(ethers.provider, proxyAddress);
    const NFTCollection = await ethers.getContractFactory("NFTCollection");
    await upgrades.forceImport(originImpAddress, NFTCollection );
    const DynamicContract = await ethers.getContractFactory("DynamicCollection");
    console.log("upgrade to Dynamic NFT");
    const dynamicContract = await upgrades.upgradeProxy(proxyAddress, DynamicContract, {unsafeAllow:['delegatecall']});
    console.log(dynamicContract.address, "Dynamic NFT address (should be the same)");
    console.log(await upgrades.erc1967.getImplementationAddress(dynamicContract.address), 'getImplementationAddress');
    console.log(await upgrades.erc1967.getAdminAddress(dynamicContract.address), 'getAdminAddress');
    
}
main().catch((err) =>{
    console.error(err);
    process.exitCode = 1;
});