import { task } from "hardhat/config";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { Forwarder, SparkbloxRegistry, SparkbloxFactory, NFTDrop, NFTCollection } from "typechain/contracts/extensions";

task("deploy", "Deploy all smart contracts and set the configs")
	.setAction(async (_args, { ethers }) => {
		const [account]: SignerWithAddress[] = await ethers.getSigners();
		console.log(account.address, ":", ethers.utils.formatEther(await account.getBalance()));

		/************************* deploy Forwarder contract *************************/
		const forwarder: Forwarder = await ethers
			.getContractFactory("Forwarder")
			.then(f => f.deploy())
			.then(async (f) => await f.deployed());

		console.log(
			"Deploying Forwarder contract:", forwarder.deployTransaction.hash,
			"Address:", forwarder.address
		);

		/************************* deploy Registry contract *************************/
		const sbRegistry: SparkbloxRegistry = await ethers
			.getContractFactory("SparkbloxRegistry")
			.then(f => f.deploy(forwarder.address))
			.then(async (f) => await f.deployed());

		console.log(
			"Deploying SparkbloxRegistry contract:", sbRegistry.deployTransaction.hash,
			"Address:", sbRegistry.address
		);

		/************************* deploy Factory contract *************************/
		const sbFactory: SparkbloxFactory = await ethers
			.getContractFactory("SparkbloxFactory")
			.then(f => f.deploy(forwarder.address, sbRegistry.address))
			.then(async (f) => await f.deployed());
		
		console.log(
			"Deploying SparkbloxFactory contract:", sbFactory.deployTransaction.hash,
			"Address:", sbFactory.address
		);

		/************************* grant OPERATOR_ROLE for Factory contract address on Registry contract *************************/
		const operator_role = ethers.utils.solidityKeccak256(["string"], ["OPERATOR_ROLE"]);
		const isOperatorOnRegistry: boolean = await sbRegistry.hasRole(
			operator_role,
			sbFactory.address
		);
		if (!isOperatorOnRegistry) {
			sbRegistry.grantRole(
				operator_role,
				sbFactory.address
			);
		}

		console.log(
			"Granted OPERATOR_ROLE for Factory contract address on Registry contract\n",
			"OPERATOR_ROLE:",
			operator_role, "\n",
			"Factory contract address:", sbFactory.address
		);

		/************************* deploy NFTDrop(Logic) contract *************************/
		const sbLogicDrop: NFTDrop = await ethers
			.getContractFactory("NFTDrop")
			.then(f => f.deploy())
			.then(async (f) => await f.deployed());
		
		console.log(
			"Deploying NFTDrop(Logic) contract:", sbLogicDrop.deployTransaction.hash,
			"Address:", sbLogicDrop.address
		);

		/************************* add NFTDrop(Logic) contract as implementation in Factory contract *************************/
		await sbFactory.addImplementation(sbLogicDrop.address);
		console.log("NFTDrop(Logic) is added to Factory");

		/* *********************** deploy NFTCollection(Logic) contract ***********************/
		const sbLogicCollection: NFTCollection = await ethers
			.getContractFactory("NFTCollection")
			.then(f => f.deploy())
			.then(async (f) => {
				return await f.deployed();
			});
		console.log(
			"Deploying NFTCollection(Logic) contract", sbLogicCollection.deployTransaction.hash,
			"Address:", sbLogicCollection.address
		);

		/*********************** add NFTCollection(Logic) contract as implementation in Factory contract ***********************/  
		await sbFactory.addImplementation(sbLogicCollection.address);
		console.log("NFTCollection(Logic) is added to Factory");
		
		/* =========================================================================================================== */
		/************************* verify all deployed contracts *************************/
		await run("verify:verify", {
			address: forwarder.address,
			contract: "contracts/extensions/Forwarder.sol:Forwarder"
		});
		console.log("Forwarder contract has verified successfully!\n");

		await run("verify:verify", {
			address: sbRegistry.address,
			contract: "contracts/SparkbloxRegistry.sol:SparkbloxRegistry",
			constructorArguments: [
				forwarder.address
			]
		});
		console.log("SparkbloxRegistry contract has verified successfully!\n");

		await run("verify:verify", {
			address: sbFactory.address,
			contract: "contracts/SparkbloxFactory.sol:SparkbloxFactory",
			constructorArguments: [
				forwarder.address,
				sbRegistry.address
			]
		});
		console.log("SparkbloxFactory contract has verified successfully!\n");

		await run("verify:verify", {
			address: sbLogicDrop.address,
			contract: "contracts/prebuilts/NFTDrop.sol:NFTDrop",
		});
		console.log("NFTDrop(Logic) contract has verified successfully!\n");

		await run("verify:verify", {
			address: sbLogicCollection.address,
			contract: "contracts/prebuilts/NFTCollection.sol:NFTCollection",
		});
		console.log("NFTCollection(Logic) contract has verified successfully!\n");
	});