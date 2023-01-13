import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { NFTCollection, Forwarder, SparkbloxRegistry, SparkbloxFactory } from "../typechain";
import { INFTSalesPhase } from "../typechain/contracts/interfaces/INFTCollection";
import { BytesLike, ContractReceipt, ContractTransaction } from "ethers";
import MerkleTree from "merkletreejs";
import exp from "constants";
import { token } from "../typechain/@openzeppelin/contracts-upgradeable";
describe("NFTCollection", () => {
    const baseURI: string = "https://test.baseURI/";
    let nftCollection: NFTCollection;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let crossmintAddy: SignerWithAddress;
    let addr3: SignerWithAddress;
    let plateformFeeRecip: SignerWithAddress;
    let sbRegistry: SparkbloxRegistry;
    let sbFactory: SparkbloxFactory;
    let contract: NFTCollection;

    before(async () => {
        [owner, addr1, crossmintAddy, addr3, plateformFeeRecip] = await ethers.getSigners();
    });

    beforeEach(async () => {
        [owner, addr1, crossmintAddy, addr3, plateformFeeRecip] = await ethers.getSigners();

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
        await sbFactory.connect(owner).setDefaultPlatformFee(plateformFeeRecip.address, 100);
        const operator_role = await sbRegistry.OPERATOR_ROLE();
        const isOperatorOnRegistry: boolean = await sbRegistry.hasRole(operator_role, sbFactory.address);

        if (!isOperatorOnRegistry) {
            sbRegistry.grantRole(
                operator_role,
                sbFactory.address
            );
        };

        nftCollection = await ethers
            .getContractFactory("NFTCollection")
            .then(f => f.deploy())
            .then(async f => f.deployed());
        await sbFactory.connect(owner).addImplementation(nftCollection.address);
        const typeOfNFTDrop = await nftCollection.contractType();
        const dataOfnftDrop: any = (
            await nftCollection.
                populateTransaction.
                initialize(
                    "testDrop",
                    "TD",
                    "testContractURI",
                    owner.address,
                    owner.address,
                    1000,
                    1000,
                    crossmintAddy.address,
                    baseURI
                )
        )
            .data;

        let tx: ContractTransaction = await sbFactory
            .connect(owner)
            .deployERC1967Proxy(typeOfNFTDrop, dataOfnftDrop);
        let receipt: ContractReceipt | any = await tx.wait();
        const contractAddy = receipt.events.filter((x: any) => { return x.event == "ERC1967ProxyDeployed" })[0].args.proxy;


        contract = await ethers.getContractAt("NFTCollection", contractAddy);

    });
    describe("test initialize method", () => {

        it("Should revert when call initialize", async () => {

            await expect(contract.initialize("NFTDrop", "ND", "contractURI", owner.address, owner.address, 1000, 100, crossmintAddy.address, baseURI)).to.be.reverted;
        });
    })

    describe("test setContractURI method", () => {
        it("Should set contractURI", async () => {
            await contract.connect(owner).setContractURI("changedURI");
            expect(await contract.contractURI()).to.equal("changedURI");
        });
        it("Should revert when call by no owner", async () => {
            await expect(contract.connect(addr1).setContractURI("changeByNotOwner")).to.be.reverted;
        });
    });

    describe("test setCrossmintAddy method", () => {
        it("Should set setCrossmintAddy", async () => {
            await contract.connect(owner).setCrossmintAddy(addr3.address);
            expect(await contract.crossmintAddy()).to.equal(addr3.address);
        });

        it("Should revert by existing crossmint addy", async () => {

            await expect(contract.connect(owner).setCrossmintAddy(crossmintAddy.address)).to.be.revertedWith("Already exist");
        });

        it("Should revert when call by no owner", async () => {
            await expect(contract.connect(addr1).setCrossmintAddy(crossmintAddy.address)).to.be.reverted;
        });
    });

    describe("test setDefaultRoyaltyInfo method", () => {
        it("Should set Default RoyaltyInfo", async () => {

            await expect(contract.connect(owner).setDefaultRoyaltyInfo(addr3.address, 100))
                .to
                .emit(contract, "DefaultRoyalty")
                .withArgs(addr3.address, 100);

        });

        it("Should revert by greater than MAX_BPS(10_000)", async () => {

            await expect(contract.connect(owner).setDefaultRoyaltyInfo(addr1.address, 10001)).to.be.revertedWith("Exceeds max bps");
        });

        it("Should revert when call by no owner", async () => {
            await expect(contract.connect(addr1).setDefaultRoyaltyInfo(addr1.address, 100)).to.be.reverted;
        });
    });

    describe("test SetMaxTotalSupply method", () => {
        it("Should set correct Max Total supply", async () => {

            await expect(contract.connect(owner).setMaxTotalSupply(10000))
                .to.emit(contract, "MaxTotalSupplyUpdated")
                .withArgs(10000);
        });

        it("Should revert when call by not owner", async () => {
            await expect(contract.connect(addr1).setMaxTotalSupply(10000)).to.be.reverted;
        });
    });

    describe("test SetMaxWalletMintCount method", () => {
        it("Should set correct Max WalletCalimCount", async () => {

            await expect(contract.connect(owner).setMaxWalletMintCount(50))
                .to.emit(contract, "MaxWalletMintCountUpdated")
                .withArgs(50);
        });

        it("Should revert when call by not owner", async () => {
            await expect(contract.connect(addr1).setMaxWalletMintCount(100)).to.be.reverted;
        });
    });

    describe("test setPrimarySaleRecipient method", () => {
        it("Should emit the PrimarySaleRecipientUpdated event", async () => {

            await expect(contract.connect(owner).setPrimarySaleRecipient(owner.address))
                .to.emit(contract, "PrimarySaleRecipientUpdated")
                .withArgs(owner.address);
        });

        it("Should revert when call by not owner", async () => {
            await expect(contract.connect(addr1).setPrimarySaleRecipient(owner.address)).to.be.reverted;
        });
    });

    describe("test setRoyaltyInfoForToken method", () => {
        it("Should emit the RoyaltyForToken event", async () => {

            await expect(contract.connect(owner).setRoyaltyInfoForToken(1, owner.address, 100))
                .to.emit(contract, "RoyaltyForToken")
                .withArgs(1, owner.address, 100);
        });

        it("Should revert when call by not owner", async () => {
            await expect(contract.connect(addr1).setRoyaltyInfoForToken(1, owner.address, 100)).to.be.reverted;
        });

        it("Should revert when royaltyBps is over maxbps", async () => {
            await expect(contract.connect(owner).setRoyaltyInfoForToken(1, owner.address, 10001)).to.be.revertedWith("Exceeds max bps");
        });
    });

    describe("test setSalesPhases method", () => {
        it("Should revert when call by not owner", async () => {
            await expect(contract.connect(addr1)
                .setSalesPhases([],
                    false
                )
            ).to.be.reverted;
        });

        it("Should revert when invalid timeStamp", async () => {
            const timeStamp0 = Date.now();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0 + 100,
                    maxClaimableSupply: 5,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    pricePerToken: 10000000000,
                    tokenIds: [],
                },
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 5,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ]

            await expect(
                contract.connect(owner)
                    .setSalesPhases(salePhases, false)
            ).to.revertedWith("ST");

            await expect(
                contract.connect(owner)
                    .setSalesPhases([salePhases[0]], false)
            ).emit(contract, "SalesPhasesUpdated");

            await expect(
                contract.connect(owner)
                    .setSalesPhases([salePhases[1], salePhases[0]], false)
            ).emit(contract, "SalesPhasesUpdated");

        });

        it("Should emit SalesPhasesUpdated event when call with correct args", async () => {
            const timeStamp0 = Date.now();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0 + 100,
                    maxClaimableSupply: 5,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    pricePerToken: 10000000000,
                    tokenIds: [],
                },
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 5,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ]

            await expect(
                contract.connect(owner)
                    .setSalesPhases([salePhases[1]], false)
            ).emit(contract, "SalesPhasesUpdated");
            await expect(
                contract.connect(owner)
                    .setSalesPhases([salePhases[0]], true)
            ).emit(contract, "SalesPhasesUpdated");
            let salePhase: any = await contract.salesPhase();
            expect(salePhase.currentStartId).to.be.equal(1);
            expect(salePhase.count).to.be.equal(1);
            await expect(
                contract.connect(owner)
                    .setSalesPhases([salePhases[1], salePhases[0]], false)
            ).emit(contract, "SalesPhasesUpdated");

        });

    });
    describe("test getRoyaltyInforForToken method", () => {

        it("Should return default royalty infor", async () => {
            let royaltyInfo: any = await contract.getRoyaltyInfoForToken(0);
            expect(royaltyInfo[0]).to.be.equals(owner.address);
            expect(royaltyInfo[1]).to.be.equals(1000);

            royaltyInfo = await contract.getRoyaltyInfoForToken(1);
            expect(royaltyInfo[0]).to.be.equals(owner.address);
            expect(royaltyInfo[1]).to.be.equals(1000);

            await contract.connect(owner).setDefaultRoyaltyInfo(addr1.address, 100);

            royaltyInfo = await contract.getRoyaltyInfoForToken(1);
            expect(royaltyInfo[0]).to.be.equals(addr1.address);
            expect(royaltyInfo[1]).to.be.equals(100);

            //   royaltyInfo =  await contract.getRoyaltyInfoForToken(1);
            //     expect(royaltyInfo).to.be.equal([owner.address, 1000]);
        });

        it("Sould return rolyalty infor for token core ", async () => {
            let royaltyInfo: any = await contract.getRoyaltyInfoForToken(0);

            expect(royaltyInfo[0]).to.be.equals(owner.address);
            expect(royaltyInfo[1]).to.be.equals(1000);

            await contract.connect(owner).setRoyaltyInfoForToken(2, addr1.address, 300);
            await contract.connect(owner).setRoyaltyInfoForToken(3, addr3.address, 400);
            royaltyInfo = await contract.getRoyaltyInfoForToken(0);
            expect(royaltyInfo[0]).to.be.equals(owner.address);
            expect(royaltyInfo[1]).to.be.equals(1000);

            royaltyInfo = await contract.getRoyaltyInfoForToken(2);
            expect(royaltyInfo[0]).to.be.equals(addr1.address);
            expect(royaltyInfo[1]).to.be.equals(300);

            royaltyInfo = await contract.getRoyaltyInfoForToken(3);
            expect(royaltyInfo[0]).to.be.equals(addr3.address);
            expect(royaltyInfo[1]).to.be.equals(400);
        });

    });
    describe("test setOwner method", () => {
        it("Should revert when no admin call", async () => {
            await (expect(
                contract.connect(addr1)
                    .setOwner(addr1.address)
            )).to.be.reverted;
        });

        it("Should emit OwnerUpdated event when call with valid data", async () => {
            const adminRole: BytesLike = await contract.DEFAULT_ADMIN_ROLE();
            await contract.connect(owner).grantRole(adminRole, addr1.address);
            await (expect(
                contract.connect(owner)
                    .setOwner(addr1.address)
            )).to.emit(contract, "OwnerUpdated")
                .withArgs(owner.address, addr1.address);
        });
    });

    describe("test getDefaultRoyaltyInfo method", () => {
        it("Sould return set info", async () => {
            await contract.connect(owner).setDefaultRoyaltyInfo(addr1.address, 100);

            let royaltyInfo = await contract.getDefaultRoyaltyInfo();
            expect(royaltyInfo[0]).to.be.equals(addr1.address);
            expect(royaltyInfo[1]).to.be.equals(100);

            await contract.connect(owner).setDefaultRoyaltyInfo(addr3.address, 200);
            royaltyInfo = await contract.getDefaultRoyaltyInfo();
            expect(royaltyInfo[0]).to.be.equals(addr3.address);
            expect(royaltyInfo[1]).to.be.equals(200);

        });
    });

    describe("test royaltyInfo method", () => {
        it("Should return default receiver and royaltyAmount", async () => {
            const salePrice = 1000000000000;
            let royaltyInfo = await contract.royaltyInfo(0, salePrice);
            expect(royaltyInfo[0]).to.be.equal(owner.address);
            expect(royaltyInfo[1]).to.be.equal(salePrice / 10);
        });

        it("Should return correnct value when set royaltyinfo for token", async () => {
            await contract.connect(owner)
                .setRoyaltyInfoForToken(1, addr1.address, 100);
            const salePrice = 1000000000000;
            let royaltyInfo = await contract.royaltyInfo(1, salePrice);
            expect(royaltyInfo[0]).to.be.equal(addr1.address);
            expect(royaltyInfo[1]).to.be.equal(salePrice / 100);

        })
    });

    describe("test setWalletMintCount method", async () => {
        it("Should reverted when not admint call", async () => {
            await (expect(
                contract.connect(addr1)
                    .setWalletMintCount(addr3.address, 10)
            )).to.be.reverted;
        })

        it("Should emit WalletMintCountUpdated event", async () => {
            await (expect(
                contract.connect(owner)
                    .setWalletMintCount(addr3.address, 10)
            )).to.emit(contract, "WalletMintCountUpdated")
                .withArgs(addr3.address, 10);
        })
    });

    describe("test mintTo method", () => {
        let tree: MerkleTree;
        beforeEach(async () => {
            const timeStamp0 = (Date.now() / 1000).toFixed(0);
            const whitelist: String[] = [owner.address, addr1.address];
            const leaves: String[] = whitelist.map(x => {

                return ethers.utils.keccak256(
                    ethers.utils.solidityPack(
                        ["address", "uint256"], [x.toLocaleLowerCase(), 10]
                    )
                );
            });

            tree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
            const root: BytesLike = tree.getRoot();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 7,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: root,
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ];
            await contract.connect(owner)
                .setSalesPhases(salePhases, false)
        });

        it("Should be reverted with 'CrossMint' message", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(crossmintAddy).mintTo(
                    addr1.address,
                    5,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 50000000000 }
                )
            )).to.be.revertedWith("CrossMint");
        });

        it("Should be reverted with message 'overQantityPerTx", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    6,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 60000000000 }
                )
            )).to.be.revertedWith("overQuantityPerTx");

        });

        it("Should be reverted with message 'non-whitelisted", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr3.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr3).mintTo(
                    addr3.address,
                    2,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 20000000000 }
                )
            )).to.be.revertedWith("non-whitelisted");

        });

        it("Should be reverted with message '!PriceOrCurrency", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    2,
                    100000000,
                    0,
                    proofs,
                    10,
                    { value: 200000000 }
                )
            )).to.be.revertedWith("!PriceOrCurrency");

        });

        it("Should be reverted with message '!Qty", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    0,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 0 }
                )
            )).to.be.revertedWith("!Qty");

        });

        it("Should be reverted with message '!MaxSupply", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const leaf2: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [owner.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);
            const proofs2: BytesLike[] = tree.getHexProof(leaf2);

            await contract.connect(addr1).mintTo(
                addr1.address,
                4,
                10000000000,
                0,
                proofs,
                10,
                { value: 40000000000 }
            );
            await (expect(
                contract.connect(owner).mintTo(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    proofs2,
                    10,
                    { value: 40000000000 }
                )
            )).to.be.revertedWith("!MaxSupply");

        });

        it("Should be reverted with message 'can't mint yet'", async () => {
            const timeStamp0 = Date.now();
            const whitelist: String[] = [owner.address, addr1.address];
            const leaves: String[] = whitelist.map(x => {

                return ethers.utils.keccak256(
                    ethers.utils.solidityPack(
                        ["address", "uint256"], [x.toLocaleLowerCase(), 10]
                    )
                );
            });

            tree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
            const root: BytesLike = tree.getRoot();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 7,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: root,
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ];
            await contract.connect(owner)
                .setSalesPhases(salePhases, false);

            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 40000000000 }
                )
            )).to.be.revertedWith("cant mint yet");
        });

        it("Should be reverted with message '!must send total price.", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 30000000000 }
                )
            )).to.be.revertedWith("must send total price.");

        });

        it("Should emit 'TokensMinted' event", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 40000000000 }
                )
            )).to.emit(contract, "TokensMinted");

        });


        it("test plateFormFee feature", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            // await sbFactory.connect(owner).setPlatformFee(contract.address, plateformFeeRecip.address, 100);
            const initBalanceOfPlatFormRecip: any = await plateformFeeRecip.getBalance();
            const proofs: BytesLike[] = tree.getHexProof(leaf);
            await (expect(
                contract.connect(addr1).mintTo(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    proofs,
                    10,
                    { value: 40000000000 }
                )
            )).to.emit(contract, "TokensMinted");
            const afterBalanceOfPlatFormRecip: any = await plateformFeeRecip.getBalance();
            const receivedFee = afterBalanceOfPlatFormRecip.sub(initBalanceOfPlatFormRecip);
            const expectedFee = 40000000000 / 100;
            expect(receivedFee).to.be.equal(expectedFee)
        })
    })

    describe("test mintWithCrossmint method", () => {
        let tree: MerkleTree;
        beforeEach(async () => {
            const timeStamp0 = (Date.now() / 1000).toFixed(0);
            const whitelist: String[] = [owner.address, addr1.address];
            const leaves: String[] = whitelist.map(x => {

                return ethers.utils.keccak256(
                    ethers.utils.solidityPack(
                        ["address", "uint256"], [x.toLocaleLowerCase(), 10]
                    )
                );
            });

            tree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
            const root: BytesLike = tree.getRoot();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 7,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: root,
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ];
            await contract.connect(owner)
                .setSalesPhases(salePhases, false)
        });

        it("Should be reverted with 'Non-CrossMint-Addy' message", async () => {
            const leaf: BytesLike = ethers.utils.keccak256(
                ethers.utils.solidityPack(["address", "uint256"], [addr1.address, 10])
            );
            const proofs: BytesLike[] = tree.getHexProof(leaf);

            await (expect(
                contract.connect(addr1).mintWithCrossmint(
                    addr1.address,
                    5,
                    10000000000,
                    0,
                    { value: 50000000000 }
                )
            )).to.be.revertedWith("Non-CrossMint-Addy");
        });

        it("Should be reverted with message 'overQantityPerTx", async () => {

            await (expect(
                contract.connect(crossmintAddy).mintWithCrossmint(
                    addr1.address,
                    6,
                    10000000000,
                    0,
                    { value: 60000000000 }
                )
            )).to.be.revertedWith("overQuantityPerTx");

        });


        it("Should be reverted with message '!PriceOrCurrency", async () => {

            await (expect(
                contract.connect(crossmintAddy).mintWithCrossmint(
                    addr1.address,
                    2,
                    100000000,
                    0,
                    { value: 200000000 }
                )
            )).to.be.revertedWith("!PriceOrCurrency");

        });

        it("Should be reverted with message '!must send total price.", async () => {

            await (expect(
                contract.connect(crossmintAddy).mintWithCrossmint(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    { value: 30000000000 }
                )
            )).to.be.revertedWith("must send total price.");

        });

        it("Should emit 'TokensMinted' event", async () => {

            await (expect(
                contract.connect(crossmintAddy).mintWithCrossmint(
                    addr1.address,
                    4,
                    10000000000,
                    0,
                    { value: 40000000000 }
                )
            )).to.emit(contract, "TokensMinted");

        });
    });

    describe("test tokenURI method", () => {
        let tree;
        beforeEach(async () => {

            const timeStamp0 = (Date.now() / 1000).toFixed(0);
            const whitelist: String[] = [owner.address, addr1.address];
            const leaves: String[] = whitelist.map(x => {

                return ethers.utils.keccak256(
                    ethers.utils.solidityPack(
                        ["address", "uint256"], [x.toLocaleLowerCase(), 10]
                    )
                );
            });

            tree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
            const root: BytesLike = tree.getRoot();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 7,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: root,
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ];
            await contract.connect(owner)
                .setSalesPhases(salePhases, false)

            await contract.connect(crossmintAddy).mintWithCrossmint(
                addr1.address,
                4,
                10000000000,
                0,
                { value: 40000000000 }
            );
        });

        it("Should return tokenURI", async () => {
            expect(await contract.tokenURI(0)).to.be.equal(baseURI + 0);
            expect(await contract.tokenURI(1)).to.be.equal(baseURI + 1);
            expect(await contract.tokenURI(2)).to.be.equal(baseURI + 2);
            expect(await contract.tokenURI(3)).to.be.equal(baseURI + 3);
            await(expect(contract.tokenURI(4))).to.be.revertedWith("No exist token");
        });

    });
    describe("test burn method", () => {
        let tree;
        beforeEach(async () => {

            const timeStamp0 = (Date.now() / 1000).toFixed(0);
            const whitelist: String[] = [owner.address, addr1.address];
            const leaves: String[] = whitelist.map(x => {

                return ethers.utils.keccak256(
                    ethers.utils.solidityPack(
                        ["address", "uint256"], [x.toLocaleLowerCase(), 10]
                    )
                );
            });

            tree = new MerkleTree(leaves, ethers.utils.keccak256, { sortPairs: true });
            const root: BytesLike = tree.getRoot();
            const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
                {
                    startTimestamp: timeStamp0,
                    maxClaimableSupply: 7,
                    supplyClaimed: 0,
                    quantityLimitPerTransaction: 5,
                    waitTimeInSecondsBetweenClaims: 0,
                    merkleRoot: root,
                    pricePerToken: 10000000000,
                    tokenIds: [],
                }
            ];
            await contract.connect(owner)
                .setSalesPhases(salePhases, false)

            await contract.connect(crossmintAddy).mintWithCrossmint(
                addr1.address,
                4,
                10000000000,
                0,
                { value: 40000000000 }
            );
        });

        it("Should revert when invalid tokenId", async () => {
            await (expect(
                contract.connect(owner).burn(0)
            )).to.be.reverted;
        });
        it("Should burn token", async () => {
            await (expect(
                contract.connect(addr1).burn(0)
            )).to.emit(contract, "Transfer");
        })

    });



});