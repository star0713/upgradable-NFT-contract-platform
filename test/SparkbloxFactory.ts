import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Forwarder, NFTCollection, NFTDrop, NFTDrop__factory, SparkbloxFactory, SparkbloxFactory__factory, SparkbloxRegistry, SparkbloxRegistry__factory } from "../typechain";
import { Bytecode } from "hardhat/internal/hardhat-network/stack-traces/model";
import { BigNumberish, BytesLike } from "ethers";

describe("SparkbloxFactory", () => {
    let sbRegistry: SparkbloxRegistry;
    let sbFactory: SparkbloxFactory;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;
    let addr3: SignerWithAddress;
    let platefromFeeRecip: SignerWithAddress;
    let nftDropCollection: NFTDrop;
    let nftCollection: NFTCollection;
    beforeEach(async () => {
        [owner, addr1, addr2, addr3, platefromFeeRecip] = await ethers.getSigners();

        const forwarder: Forwarder = await ethers
            .getContractFactory("Forwarder")
            .then(f => f.deploy())
            .then(async (f) => {
                return await f.deployed();
            });
        sbRegistry = await ethers
            .getContractFactory("SparkbloxRegistry")
            .then(f => f.deploy(forwarder.address))
            .then(async (f) => {
                return await f.deployed();
            });
        sbFactory = await ethers
            .getContractFactory("SparkbloxFactory")
            .then(f => f.deploy(forwarder.address, sbRegistry.address))
            .then(async (f) => {
                return await f.deployed();
            });

        const operator_role = await sbRegistry.OPERATOR_ROLE();
        const isOperatorOnRegistry: boolean = await sbRegistry.hasRole(operator_role, sbFactory.address);

        if (!isOperatorOnRegistry) {
            sbRegistry.grantRole(
                operator_role,
                sbFactory.address
            );
        };

        nftDropCollection = await ethers
            .getContractFactory("NFTDrop")
            .then(f => f.deploy())
            .then(async f => f.deployed());

        nftCollection = await ethers
            .getContractFactory("NFTCollection")
            .then(f => f.deploy())
            .then(async f => f.deployed());

    });
    describe("test addImplementation method", () => {
        it("Should revert with message 'not admin.' when caller is not admin", async () => {
            await expect(
                sbFactory
                    .connect(addr1)
                    .addImplementation(nftDropCollection.address)
            ).to.be.revertedWith("not admin.");

        });

        it("Should revert when implementation has not contractType",
            async () => {
                await expect(
                    sbFactory
                        .connect(owner)
                        .addImplementation(sbRegistry.address)
                ).to.be.reverted;
            }
        );

        it("Should emit ImplementationAdded event when successful",
            async () => {
                await expect(
                    sbFactory
                        .connect(owner)
                        .addImplementation(nftDropCollection.address)
                ).to.emit(sbFactory, "ImplementationAdded");
            }
        );

    });
    describe("test setDefaultPlatformFee method", () => {
        it("Should revert with message 'not admin.' when caller is not admin", async () => {
            await expect(
                sbFactory
                    .connect(addr1)
                    .setDefaultPlatformFee(platefromFeeRecip.address, 100)
            ).to.be.revertedWith("not admin.");

        });

        it("Should emit ImplementationAdded event when successful",
            async () => {
                await expect(
                    sbFactory
                        .connect(owner)
                        .setDefaultPlatformFee(platefromFeeRecip.address, 100)
                ).to.emit(sbFactory, "DefaultPlatformFeeUpdated")
                    .withArgs(platefromFeeRecip.address, 100);
            }
        );

    });

    describe("test approveImplementation method", () => {

        beforeEach(async () => {
            await sbFactory.connect(owner).addImplementation(nftDropCollection.address);
            await sbFactory.connect(owner).addImplementation(nftCollection.address);

        });

        it("Should be reverted with not admin", async () => {
            await expect(
                sbFactory
                    .connect(addr1)
                    .approveImplementation(nftDropCollection.address, false)
            ).to.be.revertedWith("not admin.");

            await expect(
                sbFactory
                    .connect(addr1)
                    .approveImplementation(nftCollection.address, false)
            ).to.be.revertedWith("not admin.");
        });

        it("Should emit ImplementationApproved event when successful", async () => {
            await expect(
                sbFactory
                    .connect(owner)
                    .approveImplementation(nftDropCollection.address, false)
            ).to.emit(sbFactory, "ImplementationApproved").withArgs(nftDropCollection.address, false);

            await expect(
                sbFactory
                    .connect(owner)
                    .approveImplementation(nftCollection.address, false)
            ).to.emit(sbFactory, "ImplementationApproved").withArgs(nftCollection.address, false);
        })
    });

    describe("test deployERC1967Proxy method", () => {
        let typeOfDropcollection: BytesLike;
        let typeOfNFTcollection: BytesLike;
        let dataOfnftDrop: BytesLike|any;
        let dataOfnftCollection: BytesLike|any;

        beforeEach(async () => {
            await sbFactory.connect(owner).addImplementation(nftDropCollection.address);
            await sbFactory.connect(owner).addImplementation(nftCollection.address);
            typeOfDropcollection = await nftDropCollection.contractType();
            typeOfNFTcollection = await nftCollection.contractType();
            dataOfnftDrop = (await nftDropCollection.populateTransaction.initialize("testDrop", "TD", "testContractURI", addr1.address, addr1.address, 1000, addr2.address)).data;
            dataOfnftCollection = (await nftCollection.populateTransaction.initialize("testNFT", "TN", "testContractURI", addr1.address, addr1.address, 1000, 1000, addr2.address, "https://test.baseURI/")).data

        });

        it("Should emit ERC1967proxyDeployed event and Added of registry", async () => {
            await (
                expect(
                    sbFactory
                        .connect(owner)
                        .deployERC1967Proxy(typeOfDropcollection, dataOfnftDrop)
                )
            )
                .to.emit(sbFactory, 'ERC1967ProxyDeployed')
                .to.emit(sbRegistry, "Added");

            await (
                expect(
                    sbFactory
                        .connect(owner)
                        .deployERC1967Proxy(typeOfNFTcollection, dataOfnftCollection)
                )
            )
                .to.emit(sbFactory, 'ERC1967ProxyDeployed')
                .to.emit(sbRegistry, "Added");
        });
    });

    describe("test removeImplementation", () => {
        beforeEach(async () => {
            await sbFactory.connect(owner).addImplementation(nftDropCollection.address);
        });

        it("Should be reverted with not admin", async () => {
            await expect(
                sbFactory
                    .connect(addr1)
                    .removeImplementation(nftDropCollection.address)
            )
                .to.be.revertedWith("not admin.");
        });

        it("Should be reverted when no match implementation", async () => {
            await expect(
                sbFactory
                    .connect(owner)
                    .removeImplementation(nftDropCollection.address)
            ).to.emit(sbFactory, "ImplementationRemoved");
            await expect(
                sbFactory
                    .connect(owner)
                    .removeImplementation(nftDropCollection.address)
            ).to.be.revertedWith("No match implementation");
            await expect(
                sbFactory
                    .connect(owner)
                    .removeImplementation(nftCollection.address)
            ).to.be.revertedWith("No match implementation");

        });
        it("Should be emit ImplementationRemoved event when successful", async () => {
            await expect(
                sbFactory
                    .connect(owner)
                    .removeImplementation(nftDropCollection.address)
            ).to.emit(sbFactory, "ImplementationRemoved");

        });
    });

    describe("test getImplementation method", () => {
        let typeOfDropcollection: BytesLike
        let typeOfNFTcollection: BytesLike;
        let versionOfDropcollection: BigNumberish;
        let versionOfNFTcollection: BigNumberish;
        beforeEach(async () => {
            await sbFactory.connect(owner).addImplementation(nftDropCollection.address);
            await sbFactory.connect(owner).addImplementation(nftCollection.address);
            typeOfDropcollection = await nftDropCollection.contractType();
            typeOfNFTcollection = await nftCollection.contractType();
            versionOfDropcollection = await nftDropCollection.contractVersion();
            versionOfNFTcollection = await nftCollection.contractVersion();
        })
        it("return implementation address", async () => {
            const impCollectionAddr = await sbFactory.getImplementation(typeOfNFTcollection, versionOfNFTcollection);
            const impDropAddr = await sbFactory.getImplementation(typeOfDropcollection, versionOfDropcollection);

            expect(impCollectionAddr).to.be.equal(nftCollection.address);
            expect(impDropAddr).to.be.equal(nftDropCollection.address);
        });
    });


    describe("test getLatestImplementation method", () => {
        let typeOfDropcollection: BytesLike
        let typeOfNFTcollection: BytesLike;

        beforeEach(async () => {
            await sbFactory.connect(owner).addImplementation(nftDropCollection.address);
            await sbFactory.connect(owner).addImplementation(nftCollection.address);
            typeOfDropcollection = await nftDropCollection.contractType();
            typeOfNFTcollection = await nftCollection.contractType();
        });

        it("return latest implementation address", async () => {
            const impCollectionAddr = await sbFactory.getLatestImplementation(typeOfNFTcollection);
            const impDropAddr = await sbFactory.getLatestImplementation(typeOfDropcollection);

            expect(impCollectionAddr).to.be.equal(nftCollection.address);
            expect(impDropAddr).to.be.equal(nftDropCollection.address);
        });
    });

    


})