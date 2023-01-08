// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "../prebuilts/NFTCollection.sol";

contract DynamicCollection is NFTCollection {
    using StringsUpgradeable for uint256;
    ///@dev Token ID => sketchId of NFT a wallet has claimed
    mapping(uint256 => uint256) public sketchToToken;

    ///@dev Token ID => hash of NFT a wallet has claimed
    mapping(uint256 => uint256) public hashToToken;

    ///@dev salephase => sketchId for category support
    mapping(uint256 => uint256[]) public sketchIdsBySalePhaseId;
    /*/////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
                                    Events
     ////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    ///@dev Emitted when minting with hashes and sketchIds
    event HashesAdded(address minter, uint256[] hashes);

    ///@dev Emitted when original mint -> revert transaction
    event RevertedOldMint(
        address receiver,
        uint256 quantity,
        uint256 pricePerToken,
        uint256 salesPhaseId,
        bytes32[] _proofs,
        uint256 _quantityLimitPerWallet
    );

    ///@dev Emitted when old corssmint -> revert the transaction
    event RevertedOldCrossmint(address receiver, uint256 quantity, uint256 pricePerToken, uint256 salesPhaseId);

    ///@dev Emitted when old setSalesphase -> revert the transaction
    event RevertedOldSalesPhases(SalesPhase[] _salePhase, bool _resetMintEligibility);

    /* ///////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
                                    Custom function for Orkhan project    
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// */

    ///@dev customize mint function for Orkhan project with sketchId and hash
    function mintTo(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet,
        uint256[] calldata _hashes,
        uint256[] calldata _sketchIds
    ) external payable nonReentrant {
        require(_msgSender() == tx.origin, "BOT");
        require(_msgSender() != crossmintAddy, "CrossMint");
        require(_hashes.length == _sketchIds.length, "HashData length must match SketchData length");
        require(_quantity == _hashes.length, "Quantity not match hash_data length");

        uint256 tokenIdToMint = nextTokenIdToMint;

        verifyMint(_salesPhaseId, _msgSender(), _quantity, _pricePerToken, _proofs, _quantityLimitPerWallet);

        // If there's a price, collect price.
        collectMintPrice(_quantity, _pricePerToken);

        // Mint the relevant NFTs to minter.
        _mintTo(_receiver, _salesPhaseId, _quantity, _hashes, _sketchIds);

        emit TokensMinted(_salesPhaseId, _msgSender(), _receiver, tokenIdToMint, _quantity);
    }

    ///@dev revert tx when trigger original mintTo with out hash and skethId
    function mintTo(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) external payable override {
        emit RevertedOldMint(_receiver, _quantity, _pricePerToken, _salesPhaseId, _proofs, _quantityLimitPerWallet);
        revert("Unable function");
    }

    ///@dev mint NFT with Credit card
    function mintWithCrossmint(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        uint256[] calldata _hashes,
        uint256[] calldata _sketchIds
    ) external payable nonReentrant {
        require(_msgSender() == crossmintAddy, "Non-CrossMint-Addy");
        require(_hashes.length == _sketchIds.length, "HashData length must match SketchData length");
        require(_quantity == _hashes.length, "Quantity not match hash_data length");

        uint256 tokenIdToMint = nextTokenIdToMint;

        // Get the sales phases.
        uint256 activeConditionId = _salesPhaseId;

        // If there's a price, collect price.
        collectMintPrice(_quantity, _pricePerToken);

        // Mint the relevant NFTs to minter.
        _mintTo(_receiver, activeConditionId, _quantity, _hashes, _sketchIds);

        emit TokensMinted(activeConditionId, _msgSender(), _receiver, tokenIdToMint, _quantity);
    }

    ///@dev override orignal crossmint function to revert when trigger old mint function
    function mintWithCrossmint(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId
    ) external payable override {
        emit RevertedOldCrossmint(_receiver, _quantity, _pricePerToken, _salesPhaseId);
        revert("Unable Function");
    }

    ///@dev mint token with hash and sketch
    function _mintTo(
        address _to,
        uint256 _salesphaseId,
        uint256 _quantityBeingMinted,
        uint256[] calldata _hashes,
        uint256[] calldata _sketchIds
    ) internal {
        validateCategory(_salesphaseId, _sketchIds);
        salesPhase.phases[_salesphaseId].supplyClaimed += _quantityBeingMinted;
        salesPhase.supplyClaimedByWallet[_salesphaseId][_msgSender()] += _quantityBeingMinted;

        // if transfer claimed tokens is called when `to != msg.sender`, it'd use msg.sender's limits.
        // behavior would be similar to `msg.sender` mint for itself, then transfer to `_to`.
        salesPhase.limitLastClaimTimestamp[_salesphaseId][_msgSender()] = block.timestamp;
        walletMintCount[_msgSender()] += _quantityBeingMinted;

        uint256 tokenIdToMint = nextTokenIdToMint;

        for (uint256 i; i < _hashes.length; i++) {
            sketchToToken[tokenIdToMint + i] = _sketchIds[i];
            hashToToken[tokenIdToMint + i] = _hashes[i];
        }
        emit HashesAdded(_msgSender(), _hashes);

        _safeMint(_to, _quantityBeingMinted);

        nextTokenIdToMint = tokenIdToMint + _quantityBeingMinted;
    }

    ///@dev validate if sketchids included in category
    function validateCategory(uint256 _salephaseId, uint256[] memory _sketchIds) public view returns (bool) {
        uint256[] memory sketchIdsOfCurPhase = sketchIdsBySalePhaseId[_salephaseId];

        if (sketchIdsOfCurPhase.length == 0) {
            return true;
        }

        for (uint256 i = 0; i < _sketchIds.length; i++) {
            uint256 _sketchId = _sketchIds[i];
            if (i > 0 && _sketchId == _sketchIds[i - 1]) {
                continue;
            }
            bool bValid = false;

            for (uint256 j = 0; j < sketchIdsOfCurPhase.length; j++) {
                if (_sketchId == sketchIdsOfCurPhase[j]) {
                    bValid = true;
                    break;
                }
            }

            if (bValid == false) {
                revert("sketchIds are invalid");
            }
        }
        return true;
    }

    function tokenURI(uint256 _tokenId) public view override(NFTCollection) returns (string memory) {
        return
            string(
                abi.encodePacked(
                    baseURI,
                    _tokenId.toString(),
                    "/",
                    sketchToToken[_tokenId].toString(),
                    "/",
                    hashToToken[_tokenId].toHexString()
                )
            );
    }

    ///@dev redefine setSalephase to revert the tx when trigger origin settSalePhase method
    function setSalesPhases(SalesPhase[] calldata _phases, bool _resetMintEligibility)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit RevertedOldSalesPhases(_phases, _resetMintEligibility);
        revert("Unable function!");
    }

    ///@dev Let a contract admin set sales phases
    function setSalesPhases(
        SalesPhase[] calldata _phases,
        uint256[][] calldata arrayOfsketchIds,
        bool _resetMintEligibility
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_phases.length == arrayOfsketchIds.length, "Length of sketchId not match to phases' length");

        uint256 existingStartIndex = salesPhase.currentStartId;
        uint256 existingPhaseCount = salesPhase.count;

        uint256 newStartIndex = existingStartIndex;
        if (_resetMintEligibility) {
            newStartIndex = existingStartIndex + existingPhaseCount;
        }

        salesPhase.count = _phases.length;
        salesPhase.currentStartId = newStartIndex;

        uint256 lastConditionStartTimestamp;
        for (uint256 i = 0; i < _phases.length; i++) {
            require(i == 0 || lastConditionStartTimestamp < _phases[i].startTimestamp, "ST");

            uint256 supplyMintedAlready = salesPhase.phases[newStartIndex + i].supplyClaimed;
            require(supplyMintedAlready <= _phases[i].maxClaimableSupply, "max supply minted already");

            salesPhase.phases[newStartIndex + i] = _phases[i];
            salesPhase.phases[newStartIndex + i].supplyClaimed = supplyMintedAlready;

            lastConditionStartTimestamp = _phases[i].startTimestamp;
            sketchIdsBySalePhaseId[newStartIndex + i] = arrayOfsketchIds[i];
        }
    }
}
