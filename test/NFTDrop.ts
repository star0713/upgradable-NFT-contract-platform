import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { NFTDrop, NFTDrop__factory } from "../typechain";
import { INFTSalesPhase } from "../typechain/contracts/interfaces/INFTCollection";
import { BytesLike } from "ethers";
describe("NFTDrop", function () {
    let nftDrop: NFTDrop;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;
    let addr3: SignerWithAddress;

    before(async () => {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();
        
    });
   

    describe("contract methods test", () => {
        let contract: NFTDrop;
        this.beforeEach(async () => {
            const nftDrop = (await ethers.getContractFactory("NFTDrop", owner)) as NFTDrop__factory;
           
            console.error = function (d){return ;};
        
            contract = await upgrades.deployProxy(
                nftDrop,
                ["NFTDrop", "ND", "contractURI", owner.address, owner.address, 1000, addr2.address],
                { initializer: "initialize", kind: "uups", unsafeAllow: ["delegatecall"] }
            );
            await contract.deployed();
        });

        describe("test initialize method", () => {

            it("Should revert when call initialize", async () => {
               
                await expect(contract.initialize("NFTDrop", "ND", "contractURI", owner.address, owner.address, 1000, addr2.address)).to.be.reverted;
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

                await expect(contract.connect(owner).setCrossmintAddy(addr2.address)).to.be.revertedWith("Already exist");
            });

            it("Should revert when call by no owner", async () => {
                await expect(contract.connect(addr1).setCrossmintAddy(addr2.address)).to.be.reverted;
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

                await expect(contract.connect(owner).setDefaultRoyaltyInfo(addr1.address, 10001)).to.be.revertedWith("> MAX_BPS");
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

        describe("test SetMaxWalletClaimCount method", () => {
            it("Should set correct Max WalletCalimCount", async () => {

                await expect(contract.connect(owner).setMaxWalletClaimCount(50))
                    .to.emit(contract, "MaxWalletClaimCountUpdated")
                    .withArgs(50);
            });

            it("Should revert when call by not owner", async () => {
                await expect(contract.connect(addr1).setMaxWalletClaimCount(10000)).to.be.reverted;
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
                await expect(contract.connect(owner).setRoyaltyInfoForToken(1, owner.address, 10001)).to.be.revertedWith("> MAX_BPS");
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

            it("Should revert when first timeStamp is greater than next timeStamp", async () => {
                const timeStamp1 = Date.now();
                const timeStamp0 = timeStamp1 + 10;

                await expect(
                    contract.connect(owner)
                        .setSalesPhases([
                            {
                                startTimestamp: timeStamp0,
                                maxClaimableSupply: 0,
                                supplyClaimed: 0,
                                quantityLimitPerTransaction: 0,
                                waitTimeInSecondsBetweenClaims: 0,
                                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                                pricePerToken: 10000000000,
                                tokenIds: [],
                            },
                            {
                                startTimestamp: timeStamp1,
                                maxClaimableSupply: 0,
                                supplyClaimed: 0,
                                quantityLimitPerTransaction: 0,
                                waitTimeInSecondsBetweenClaims: 0,
                                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
                                pricePerToken: 10000000000,
                                tokenIds: [],
                            },

                        ],
                            false
                        )
                ).to.be.revertedWith("ST");

            });
            it("Should emit SalesPhasesUpdated event when call with correct args", async () => {
                const timeStamp0 = Date.now();
                const salePhases: INFTSalesPhase.SalesPhaseStruct[] = [
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
                ).to.emit(contract, "SalesPhasesUpdated")

            });
            /* max supply */
            

        });

        describe("test lazyMint method", () => {
            const amount = 3;
            const baseURIForTokens = "https://baseURI/";
            const _data = "0x";
            it("Should revert when call by not minter Role", async () => {
               
                await expect(contract.connect(addr1).lazyMint(amount, baseURIForTokens, _data))
                    .to
                    .be
                    .reverted
            });
            
            it("Should lazyMint correctly", async () => {
                await expect(contract.connect(owner).lazyMint(amount, baseURIForTokens, _data))
                    .to
                    .emit(contract, "TokensLazyMinted");
                expect(await contract.nextTokenIdToMint()).to.be.equal(amount);
                expect(await contract.baseURIIndices(0)).to.be.equal(amount);
                expect(await contract.tokenURI(0)).to.be.equal(baseURIForTokens+0);
                    
            });

        });

        describe("test reveal method", () => {
            const amount = 3;
            const baseURIForTokens = "https://baseURI/";
            const key = "0x";
            let data:BytesLike;
            
            beforeEach(async () => {
               
                const chainId = "1337";
                
                const encryptedURI =await contract.encryptDecrypt(ethers.utils.solidityPack(["string"],[baseURIForTokens]),key);
                const provenanceHash = ethers.utils.keccak256(ethers.utils.solidityPack(["string", "bytes", "uint256"],[baseURIForTokens, key, chainId ]));
                // console.log(provenanceHash,"hash")
                // console.log(encryptedURI,provenanceHash,)
                data = ethers.utils.defaultAbiCoder.encode(["bytes", "bytes32"],[encryptedURI, provenanceHash]);
               
            });

            it("Should revert with message 'invalid index.'", async() => {
              await expect(contract.connect(owner).reveal(0, key)).to.be.revertedWith("invalid index.");
            });

            it("Should reveert with message 'nothing to reveal'", async() => {
                await contract.connect(owner).lazyMint(3,baseURIForTokens, "0x");
                await expect(contract.connect(owner).reveal(0, "0x")).to.be.revertedWith("nothing to reveal.");
            });

            it("Should revert with message 'Incorrect key", async() => {
                await contract.connect(owner).lazyMint(3,baseURIForTokens, data);
                await expect(contract.connect(owner).reveal(0, "0x03")).to.be.revertedWith("Incorrect key");
            });
            
            it("Should revert when call by that has not Mint_role", async () => {
                await contract.connect(owner).lazyMint(3,baseURIForTokens, data);
                await expect(contract.connect(addr1).reveal(0, key)).to.be.reverted;
            });

            it("Should emit NFTRevealed event with param as index and revealedURI", async () => {
                await contract.connect(owner).lazyMint(3,baseURIForTokens, data);
                await expect(contract.connect(owner).reveal(0,key)).to.emit(contract, "NFTRevealed").withArgs(3,baseURIForTokens);
            })
           
        });



    })

});