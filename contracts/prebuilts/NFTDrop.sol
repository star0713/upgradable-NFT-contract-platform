// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//  ==========  External imports    ==========

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

//  ==========  Internal imports    ==========

import "../interfaces/ISparkbloxContract.sol";
import "../interfaces/INFTDrop.sol";
import "../interfaces/IRoyalty.sol";
import "../interfaces/IOwnable.sol";

//  ==========  Features    ==========

import "../lib/MerkleProof.sol";


contract NFTDrop is
    Initializable,
    ISparkbloxContract,
    INFTDrop,
    IRoyalty,
    IOwnable,
    Multicall,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    ERC721EnumerableUpgradeable
{
    using BitMapsUpgradeable for BitMapsUpgradeable.BitMap;
    using StringsUpgradeable for uint256;

    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant MODULE_TYPE = bytes32("NFTDrop");
    uint256 private constant VERSION = 5;

    /// @dev Only transfers to or from TRANSFER_ROLE holders are valid, when transfers are restricted.
    bytes32 private constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    /// @dev Only MINTER_ROLE holders can lazy mint NFTs.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Max bps in the sparkblox system.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev Owner of the contract (purpose: OpenSea compatibility)
    address private _owner;

    /// @dev The next token ID of the NFT to "lazy mint".
    uint256 public nextTokenIdToMint;

      /// @dev The address that receives all primary sales value.
    address public primarySaleRecipient;

    /// @dev The max number of NFTs a wallet can claim.
    uint256 public maxWalletClaimCount;

    /// @dev Global max total supply of NFTs.
    uint256 public maxTotalSupply;

    /// @dev The (default) address that receives all royalty value.
    address private royaltyRecipient;

    /// @dev The (default) % of a sale to take as royalty (in basis points).
    uint16 private royaltyBps;

    /// @dev Contract level metadata.
    string public contractURI;

    /// @dev Largest tokenId of each batch of tokens with the same baseURI
    uint256[] public baseURIIndices;

    /// @dev The set of all sales phases, at any given moment.
    SalesPhaseList public salesPhase;

    /// @dev The EOA address for cross mint
    address public crossmintAddy;

    /*///////////////////////////////////////////////////////////////
                                Mappings
    //////////////////////////////////////////////////////////////*/

    /**
     *  @dev Mapping from 'Largest tokenId of a batch of tokens with the same baseURI'
     *       to base URI for the respective batch of tokens.
     **/
    mapping(uint256 => string) private baseURI;

    /**
     *  @dev Mapping from 'Largest tokenId of a batch of 'delayed-reveal' tokens with
     *       the same baseURI' to encrypted base URI for the respective batch of tokens.
     **/
    mapping(uint256 => bytes) public encryptedData;

    /// @dev Mapping from address => total number of NFTs a wallet has claimed.
    mapping(address => uint256) public walletClaimCount;

    /// @dev Token ID => royalty recipient and bps for token
    mapping(uint256 => RoyaltyInfo) private royaltyInfoForToken;
    
    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when a new sale recipient is set.
    event PrimarySaleRecipientUpdated(address indexed recipient);

    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address _saleRecipient,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _crossmintAddy
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ERC721_init(_name, _symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Initialize this contract's state.
        royaltyRecipient = _royaltyRecipient;
        royaltyBps = uint16(_royaltyBps);
        primarySaleRecipient = _saleRecipient;
        contractURI = _contractURI;
        _owner = tx.origin;

        // Initialize the crossmint EOA addy
        crossmintAddy = _crossmintAddy;

        _setupRole(DEFAULT_ADMIN_ROLE, tx.origin);
        _setupRole(MINTER_ROLE, tx.origin);
        _setupRole(TRANSFER_ROLE, tx.origin);
        _setupRole(TRANSFER_ROLE, address(0));
    }

    /*///////////////////////////////////////////////////////////////
                        Generic contract logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the type of the contract.
    function contractType() external pure returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @dev Returns the version of the contract.
    function contractVersion() external pure returns (uint8) {
        return uint8(VERSION);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return hasRole(DEFAULT_ADMIN_ROLE, _owner) ? _owner : address(0);
    }

    /*///////////////////////////////////////////////////////////////
                        ERC 165 / 721 / 2981 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        for (uint256 i = 0; i < baseURIIndices.length; i += 1) {
            if (_tokenId < baseURIIndices[i]) {
                if (encryptedData[baseURIIndices[i]].length != 0) {
                    return string(abi.encodePacked(baseURI[baseURIIndices[i]], "0"));
                } else {
                    return string(abi.encodePacked(baseURI[baseURIIndices[i]], _tokenId.toString()));
                }
            }
        }

        return "";
    }

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721EnumerableUpgradeable, AccessControlEnumerableUpgradeable, IERC165Upgradeable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || type(IERC2981Upgradeable).interfaceId == interfaceId;
    }

    /// @dev Returns the royalty recipient and amount, given a tokenId and sale price.
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        virtual
        returns (address receiver, uint256 royaltyAmount)
    {
        (address recipient, uint256 bps) = getRoyaltyInfoForToken(tokenId);
        receiver = recipient;
        royaltyAmount = (salePrice * bps) / MAX_BPS;
    }

    /*///////////////////////////////////////////////////////////////
                    Minting + delayed-reveal logic
    //////////////////////////////////////////////////////////////*/

    /**
     *  @dev Lets an account with `MINTER_ROLE` lazy mint 'n' NFTs.
     *       The URIs for each token is the provided `_baseURIForTokens` + `{tokenId}`.
     */
    function lazyMint(
        uint256 _amount,
        string calldata _baseURIForTokens,
        bytes calldata _data
    ) external onlyRole(MINTER_ROLE) {
        uint256 startId = nextTokenIdToMint;
        uint256 baseURIIndex = startId + _amount;

        nextTokenIdToMint = baseURIIndex;
        baseURI[baseURIIndex] = _baseURIForTokens;
        baseURIIndices.push(baseURIIndex);

        if (_data.length > 0) {
            (bytes memory encryptedURI, bytes32 provenanceHash) = abi.decode(_data, (bytes, bytes32));

            if (encryptedURI.length != 0 && provenanceHash != "") {
                encryptedData[baseURIIndex] = _data;
            }
        }

        emit TokensLazyMinted(startId, startId + _amount - 1, _baseURIForTokens, _data);
    }

    /// @dev Lets an account with `MINTER_ROLE` reveal the URI for a batch of 'delayed-reveal' NFTs.
    function reveal(uint256 index, bytes calldata _key)
        external
        onlyRole(MINTER_ROLE)
        returns (string memory revealedURI)
    {
        require(index < baseURIIndices.length, "invalid index.");

        uint256 _index = baseURIIndices[index];
        bytes memory data = encryptedData[_index];

        require(data.length != 0, "nothing to reveal.");
        
        (bytes memory encryptedURI, bytes32 provenanceHash) = abi.decode(data, (bytes, bytes32));

        revealedURI = string(encryptDecrypt(encryptedURI, _key));

        require(keccak256(abi.encodePacked(revealedURI, _key, block.chainid)) == provenanceHash, "Incorrect key");

        baseURI[_index] = revealedURI;
        delete encryptedData[_index];

        emit NFTRevealed(_index, revealedURI);

        return revealedURI;
    }

    /// @dev See: https://ethereum.stackexchange.com/questions/69825/decrypt-message-on-chain
    function encryptDecrypt(bytes memory data, bytes calldata key) public pure returns (bytes memory result) {
        // Store data length on stack for later use
        uint256 length = data.length;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Set result to free memory pointer
            result := mload(0x40)
            // Increase free memory pointer by lenght + 32
            mstore(0x40, add(add(result, length), 32))
            // Set result length
            mstore(result, length)
        }

        // Iterate over the data stepping by 32 bytes
        for (uint256 i = 0; i < length; i += 32) {
            // Generate hash of the key and offset
            bytes32 hash = keccak256(abi.encodePacked(key, i));

            bytes32 chunk;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Read 32-bytes data chunk
                chunk := mload(add(data, add(i, 32)))
            }
            // XOR the chunk with hash
            chunk ^= hash;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Write 32-byte encrypted chunk
                mstore(add(result, add(i, 32)), chunk)
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Claim logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Lets an account claim NFTs.
    function claim(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) external payable nonReentrant {
        require(_msgSender() == tx.origin, "BOT");
        require(_msgSender() != crossmintAddy, "CrossMint");
    
        

        // Get the sales phases.
        uint256 activeConditionId = _salesPhaseId;
        
        verifyClaim(_salesPhaseId, _msgSender(), _quantity, _pricePerToken, _proofs, _quantityLimitPerWallet);

        // If there's a price, collect price.
        collectClaimPrice(_quantity, _pricePerToken);

        // Mint the relevant NFTs to claimer.
        transferClaimedTokens(_receiver, activeConditionId, _quantity);
    }

    /// @dev Lets an account claim NFTs with credit card.
    function claimWithCrossmint(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId
    ) external payable nonReentrant {
        require(_msgSender() == crossmintAddy, "Non-CrossMint-Addy");

        // Get the sales phases.
        uint256 activeConditionId = _salesPhaseId;

        // If there's a price, collect price.
        collectClaimPrice(_quantity, _pricePerToken);

        // Mint the relevant NFTs to claimer.
        transferClaimedTokens(_receiver, activeConditionId, _quantity);

    }

    /// @dev Lets a contract admin (account with `DEFAULT_ADMIN_ROLE`) set sales phases.
    function setSalesPhases(SalesPhase[] calldata _phases, bool _resetClaimEligibility)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 existingStartIndex = salesPhase.currentStartId;
        uint256 existingPhaseCount = salesPhase.count;

        uint256 newStartIndex = existingStartIndex;
        if (_resetClaimEligibility) {
            newStartIndex = existingStartIndex + existingPhaseCount;
        }

        salesPhase.count = _phases.length;
        salesPhase.currentStartId = newStartIndex;

        uint256 lastConditionStartTimestamp;
        for (uint256 i = 0; i < _phases.length; i++) {
            require(i == 0 || lastConditionStartTimestamp < _phases[i].startTimestamp, "ST");

            uint256 supplyClaimedAlready = salesPhase.phases[newStartIndex + i].supplyClaimed;
            require(supplyClaimedAlready <= _phases[i].maxClaimableSupply, "max supply claimed already");

            salesPhase.phases[newStartIndex + i] = _phases[i];
            salesPhase.phases[newStartIndex + i].supplyClaimed = supplyClaimedAlready;

            lastConditionStartTimestamp = _phases[i].startTimestamp;
        }

        /**
         *  Gas refunds (as much as possible)
         *
         *  If `_resetClaimEligibility == true`, we assign completely new UIDs to the claim
         *  conditions in `_phases`. So, we delete sales phases with UID < `newStartIndex`.
         *
         *  If `_resetClaimEligibility == false`, and there are more existing sales phases
         *  than in `_phases`, we delete the existing sales phases that don't get replaced
         *  by the conditions in `_phases`.
         */
        if (_resetClaimEligibility) {
            for (uint256 i = existingStartIndex; i < newStartIndex; i++) {
                delete salesPhase.phases[i];
            }
        } else {
            if (existingPhaseCount > _phases.length) {
                for (uint256 i = _phases.length; i < existingPhaseCount; i++) {
                    delete salesPhase.phases[newStartIndex + i];
                }
            }
        }

        emit SalesPhasesUpdated(_phases);
    }

    /// @dev Collects and distributes the primary sale value of NFTs being claimed.
    function collectClaimPrice(
        uint256 _quantityToClaim,
        uint256 _pricePerToken
    ) internal {
        if (_pricePerToken == 0) {
            return;
        }

        uint256 totalPrice = _quantityToClaim * _pricePerToken;

        require(msg.value == totalPrice, "must send total price.");
    }

    /// @dev Transfers the NFTs being claimed.
    function transferClaimedTokens(
        address _to,
        uint256 _salesphaseId,
        uint256 _quantityBeingClaimed
    ) internal {

        uint256 claimedTokenAmount = salesPhase.phases[_salesphaseId].supplyClaimed;
        // Update the supply minted under mint condition. 
        salesPhase.phases[_salesphaseId].supplyClaimed += _quantityBeingClaimed;
        salesPhase.supplyClaimedByWallet[_salesphaseId][_msgSender()] += _quantityBeingClaimed;
        // current salephase
        SalesPhase memory curSalesPhase = salesPhase.phases[_salesphaseId];
        // if transfer claimed tokens is called when `to != msg.sender`, it'd use msg.sender's limits.
        // behavior would be similar to `msg.sender` mint for itself, then transfer to `_to`.
        salesPhase.limitLastClaimTimestamp[_salesphaseId][_msgSender()] = block.timestamp;
        walletClaimCount[_msgSender()] += _quantityBeingClaimed;
        
        uint256 tokenIdToclaim;
        for (uint256 i = 0; i < _quantityBeingClaimed; i += 1) {
            tokenIdToclaim = curSalesPhase.tokenIds[i + claimedTokenAmount];
            _mint(_to,tokenIdToclaim);
        }
       
        emit TokensClaimed(_salesphaseId, _msgSender(), _to, tokenIdToclaim, _quantityBeingClaimed);
    }

    /// @dev Checks a request to claim NFTs against the active sales phase's criteria.
    function verifyClaim(
        uint256 _salesPhaseId,
        address _claimer,
        uint256 _quantity,
        uint256 _pricePerToken,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) public view returns(bool) {
        SalesPhase memory curSalesPhase = salesPhase.phases[_salesPhaseId];

        require(_quantity < curSalesPhase.quantityLimitPerTransaction, "overQuantityPerTx");

        uint256 claimedTokenAmount = curSalesPhase.supplyClaimed;

        require(_quantity + claimedTokenAmount <= curSalesPhase.tokenIds.length, "over token amount of salePhase");
        
        if (curSalesPhase.merkleRoot != bytes32(0)) {
            (bool isValid, ) = MerkleProof.verify(
                _proofs,
                curSalesPhase.merkleRoot,
                keccak256(abi.encodePacked(_claimer, _quantityLimitPerWallet))
            );

            require(isValid, "non-whitelisted");
        }

        uint256 claimLimit = _quantityLimitPerWallet;
        uint256 claimPrice = curSalesPhase.pricePerToken;

        uint256 supplyClaimedByWallet = salesPhase.supplyClaimedByWallet[_salesPhaseId][_claimer];

        if (_pricePerToken != claimPrice) {
            revert("!PriceOrCurrency");
        }

        if (_quantity == 0 || (_quantity + supplyClaimedByWallet > claimLimit)) {
            revert("!Qty");
        }
        if (curSalesPhase.supplyClaimed + _quantity > curSalesPhase.maxClaimableSupply) {
            revert("!MaxSupply");
        }

        if (curSalesPhase.startTimestamp > block.timestamp) {
            revert("cant claim yet");
        }

        return true;
    }

    /*///////////////////////////////////////////////////////////////
                        Getter functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the royalty recipient and bps for a particular token Id.
    function getRoyaltyInfoForToken(uint256 _tokenId) public view returns (address, uint16) {
        RoyaltyInfo memory royaltyForToken = royaltyInfoForToken[_tokenId];

        return
            royaltyForToken.recipient == address(0)
                ? (royaltyRecipient, uint16(royaltyBps))
                : (royaltyForToken.recipient, uint16(royaltyForToken.bps));
    }

    /// @dev Returns the default royalty recipient and bps.
    function getDefaultRoyaltyInfo() external view returns (address, uint16) {
        return (royaltyRecipient, uint16(royaltyBps));
    }

    /// @dev Returns the timestamp for when a claimer is eligible for claiming NFTs again.
    function getSalesphaseTimestamp(uint256 _salesphaseId, address _claimer)
        public
        view
        returns (uint256 lastClaimTimestamp, uint256 nextValidClaimTimestamp)
    {
        lastClaimTimestamp = salesPhase.limitLastClaimTimestamp[_salesphaseId][_claimer];

        unchecked {
            nextValidClaimTimestamp =
                lastClaimTimestamp +
                salesPhase.phases[_salesphaseId].waitTimeInSecondsBetweenClaims;

            if (nextValidClaimTimestamp < lastClaimTimestamp) {
                nextValidClaimTimestamp = type(uint256).max;
            }
        }
    }

    /// @dev Returns the sales phase at the given uid.
    function getSalesPhaseById(uint256 _salesphaseId) external view returns (SalesPhase memory condition) {
        condition = salesPhase.phases[_salesphaseId];
    }

    /// @dev Returns the amount of stored baseURIs
    function getBaseURICount() external view returns (uint256) {
        return baseURIIndices.length;
    }

    /*///////////////////////////////////////////////////////////////
                        Setter functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Lets a contract admin set a claim count for a wallet.
    function setWalletClaimCount(address _claimer, uint256 _count) external onlyRole(DEFAULT_ADMIN_ROLE) {
        walletClaimCount[_claimer] = _count;
        emit WalletClaimCountUpdated(_claimer, _count);
    }

    /// @dev Lets a contract admin set a maximum number of NFTs that can be claimed by any wallet.
    function setMaxWalletClaimCount(uint256 _count) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxWalletClaimCount = _count;
        emit MaxWalletClaimCountUpdated(_count);
    }

    /// @dev Lets a contract admin set the global maximum supply for collection's NFTs.
    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTotalSupply = _maxTotalSupply;
        emit MaxTotalSupplyUpdated(_maxTotalSupply);
    }

    /// @dev Lets a contract admin set the recipient for all primary sales.
    function setPrimarySaleRecipient(address _saleRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        primarySaleRecipient = _saleRecipient;
        emit PrimarySaleRecipientUpdated(_saleRecipient);
    }

    /// @dev Lets a contract admin update the default royalty recipient and bps.
    function setDefaultRoyaltyInfo(address _royaltyRecipient, uint256 _royaltyBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_royaltyBps <= MAX_BPS, "> MAX_BPS");

        royaltyRecipient = _royaltyRecipient;
        royaltyBps = uint16(_royaltyBps);

        emit DefaultRoyalty(_royaltyRecipient, _royaltyBps);
    }

    /// @dev Lets a contract admin set the royalty recipient and bps for a particular token Id.
    function setRoyaltyInfoForToken(
        uint256 _tokenId,
        address _recipient,
        uint256 _bps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bps <= MAX_BPS, "> MAX_BPS");

        royaltyInfoForToken[_tokenId] = RoyaltyInfo({ recipient: _recipient, bps: _bps });

        emit RoyaltyForToken(_tokenId, _recipient, _bps);
    }

    /// @dev Lets a contract admin set a new owner for the contract. The new owner must be a contract admin.
    function setOwner(address _newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _newOwner), "!ADMIN");
        address _prevOwner = _owner;
        _owner = _newOwner;

        emit OwnerUpdated(_prevOwner, _newOwner);
    }

    /// @dev Lets a contract admin set the URI for contract-level metadata.
    function setContractURI(string calldata _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        contractURI = _uri;
    }

    /// @dev Lets a contract admin set the EOA addy for crossmint.
    function setCrossmintAddy(address _crossmintAddy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(crossmintAddy != _crossmintAddy, "Already exist");
        crossmintAddy = _crossmintAddy;
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /// @dev Burns `tokenId`. See {ERC721-_burn}.
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "caller not owner nor approved");
        _burn(tokenId);
    }

    /// @dev See {ERC721-_beforeTokenTransfer}.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);

        // if transfer is restricted on the contract, we still want to allow burning and minting
        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            require(hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to), "!TRANSFER_ROLE");
        }
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    override
    {}

    /*
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }
    */

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[29] private __gap;
}