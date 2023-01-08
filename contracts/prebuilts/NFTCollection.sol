// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//  ==========  External imports    ==========

import "erc721a-upgradeable/contracts/ERC721AUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

//  ==========  Internal imports    ==========

import "../interfaces/ISparkbloxContract.sol";
import "../interfaces/INFTCollection.sol";
import "../interfaces/IRoyalty.sol";
import "../interfaces/IOwnable.sol";

//  ==========  Features    ==========

import "../lib/MerkleProof.sol";


contract NFTCollection is
    Initializable,
    ISparkbloxContract,
    INFTCollection,
    IRoyalty,
    IOwnable,
    Multicall,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    ERC721AUpgradeable
{
    using BitMapsUpgradeable for BitMapsUpgradeable.BitMap;
    using StringsUpgradeable for uint256;

    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant MODULE_TYPE = bytes32("NFTCollection");
    uint256 private constant VERSION = 1;

    /// @dev Only TRANSFER_ROLE holders can have tokens transferred from or to them, during restricted transfers.
    bytes32 private constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    /// @dev Only MINTER_ROLE holders can sign off on `MintRequest`s.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Max bps in the sparkblox system.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev Owner of the contract (purpose: OpenSea compatibility)
    address private _owner;

    /// @dev The token ID of the next token to mint.
    uint256 public nextTokenIdToMint;

    /// @dev The address that receives all primary sales value.
    address public primarySaleRecipient;

    /// @dev The max number of NFTs a wallet can mint.
    uint256 public maxWalletMintCount;

    /// @dev Global max total supply of NFTs.
    uint256 public maxTotalSupply;

    /// @dev The (default) address that receives all royalty value.
    address private royaltyRecipient;

    /// @dev The (default) % of a sale to take as royalty (in basis points).
    uint16 private royaltyBps;

    /// @dev Contract level metadata.
    string public contractURI;

    /// @dev The set of all sales phases, at any given moment.
    SalesPhaseList public salesPhase;

    /// @dev The EOA address for cross mint
    address public crossmintAddy;

    /*///////////////////////////////////////////////////////////////
                                Mappings
    //////////////////////////////////////////////////////////////*/

    /**
     *  @dev baseURI of token URI
     **/
    string internal baseURI;

    /// @dev Mapping from address => total number of NFTs a wallet has minted.
    mapping(address => uint256) public walletMintCount;

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
        uint256 _maxTotalSupply,
        address _crossmintAddy,
        string memory _baseURI
        

    ) external initializerERC721A initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ERC721A_init(_name, _symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Initialize this contract's state.
        royaltyRecipient = _royaltyRecipient;
        royaltyBps = uint16(_royaltyBps);
        primarySaleRecipient = _saleRecipient;
        contractURI = _contractURI;
        _owner = tx.origin;
        baseURI = _baseURI;
        maxTotalSupply = _maxTotalSupply;

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

    /**im(
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return hasRole(DEFAULT_ADMIN_ROLE, _owner) ? _owner : address(0);
    }

    /*///////////////////////////////////////////////////////////////
                        ERC 165 / 721 / 2981 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) 
        public 
        view 
        virtual
        override(ERC721AUpgradeable, IERC721AUpgradeable ) 
        returns (string memory) 
    {
        return string(
            abi.encodePacked(
                baseURI, 
                _tokenId.toString()
            )
        );
    }

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721AUpgradeable, IERC721AUpgradeable, AccessControlEnumerableUpgradeable, IERC165)
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
                            Mint logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Lets an account mint NFTs.
    function mintTo(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) external payable virtual nonReentrant {
        require(_msgSender() == tx.origin, "BOT");
        require(_msgSender() != crossmintAddy, "CrossMint");

        uint256 tokenIdToMint = nextTokenIdToMint;

        verifyMint(_salesPhaseId, _msgSender(), _quantity, _pricePerToken, _proofs, _quantityLimitPerWallet);

        // If there's a price, collect price.
        collectMintPrice(_quantity, _pricePerToken);

        // Mint the relevant NFTs to minter.
        _mintTo(_receiver, _salesPhaseId, _quantity);

        emit TokensMinted(_salesPhaseId, _msgSender(), _receiver, tokenIdToMint, _quantity);
    }

    /// @dev Lets an account mint NFTs with credit card.
    function mintWithCrossmint(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId
       ) external payable virtual nonReentrant {
        require(_msgSender() == crossmintAddy, "Non-CrossMint-Addy");

        uint256 tokenIdToMint = nextTokenIdToMint;

        // Get the sales phases.
        uint256 activeConditionId = _salesPhaseId;

        // If there's a price, collect price.
        collectMintPrice(_quantity, _pricePerToken);

        // Mint the relevant NFTs to minter.
        _mintTo(_receiver, activeConditionId, _quantity);

        emit TokensMinted(activeConditionId, _msgSender(), _receiver, tokenIdToMint, _quantity);
    }

    /// @dev Lets a contract admin (account with `DEFAULT_ADMIN_ROLE`) set sales phases.
    function setSalesPhases(SalesPhase[] calldata _phases, bool _resetMintEligibility)
        external virtual
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
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
        }

        /**
         *  Gas refunds (as much as possible)
         *
         *  If `_resetMintEligibility == true`, we assign completely new UIDs to the mint
         *  conditions in `_phases`. So, we delete sales phases with UID < `newStartIndex`.
         *
         *  If `_resetMintEligibility == false`, and there are more existing sales phases
         *  than in `_phases`, we delete the existing sales phases that don't get replaced
         *  by the conditions in `_phases`.
         */
        if (_resetMintEligibility) {
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

    /// @dev Collects and distributes the primary sale value of NFTs being Minted.
    function collectMintPrice(
        uint256 _quantityToMint,
        uint256 _pricePerToken
    ) internal {
        if (_pricePerToken == 0) {
            return;
        }

        uint256 totalPrice = _quantityToMint * _pricePerToken;

        require(msg.value == totalPrice, "must send total price.");
    }

    /// @dev Transfers the NFTs being minted.
    function _mintTo(
        address _to,
        uint256 _salesphaseId,
        uint256 _quantityBeingMinted
    ) internal {
        // Update the supply minted under mint condition.
        salesPhase.phases[_salesphaseId].supplyClaimed += _quantityBeingMinted;
        salesPhase.supplyClaimedByWallet[_salesphaseId][_msgSender()] += _quantityBeingMinted;

        // if transfer minted tokens is called when `to != msg.sender`, it'd use msg.sender's limits.
        // behavior would be similar to `msg.sender` mint for itself, then transfer to `_to`.
        salesPhase.limitLastClaimTimestamp[_salesphaseId][_msgSender()] = block.timestamp;
        walletMintCount[_msgSender()] += _quantityBeingMinted;

        uint256 tokenIdToMint = nextTokenIdToMint;
        nextTokenIdToMint = tokenIdToMint + _quantityBeingMinted;
        require(nextTokenIdToMint <= maxTotalSupply, "exceeded maxt total supply");
        
        _safeMint(_to, _quantityBeingMinted);

        
    }

    /// @dev Checks a request to mint NFTs against the active sales phase's criteria.
    function verifyMint(
        uint256 _salesphaseId,
        address _minter,
        uint256 _quantity,
        uint256 _pricePerToken,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) public view returns(bool) {
        SalesPhase memory curSalesPhase = salesPhase.phases[_salesphaseId];

        require(_quantity < curSalesPhase.quantityLimitPerTransaction, "overQuantityPerTx");

        if (curSalesPhase.merkleRoot != bytes32(0)) {
            (bool isValid, ) = MerkleProof.verify(
                _proofs,
                curSalesPhase.merkleRoot,
                keccak256(abi.encodePacked(_minter, _quantityLimitPerWallet))
            );

            require(isValid, "non-whitelisted");
        }

        uint256 mintLimit = _quantityLimitPerWallet;
        uint256 mintPrice = curSalesPhase.pricePerToken;

        uint256 supplyMintedByWallet = salesPhase.supplyClaimedByWallet[_salesphaseId][_minter];

        if (_pricePerToken != mintPrice) {
            revert("!PriceOrCurrency");
        }

        if (_quantity == 0 || (_quantity + supplyMintedByWallet > mintLimit)) {
            revert("!Qty");
        }
        if (curSalesPhase.supplyClaimed + _quantity > curSalesPhase.maxClaimableSupply) {
            revert("!MaxSupply");
        }

        if (curSalesPhase.startTimestamp > block.timestamp) {
            revert("cant mint yet");
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

    /// @dev Returns the timestamp for when a minter is eligible for minting NFTs again.
    function getSalesphaseTimestamp(uint256 _salesphaseId, address _minter)
        public
        view
        returns (uint256 lastMintTimestamp, uint256 nextValidMintTimestamp)
    {
        lastMintTimestamp = salesPhase.limitLastClaimTimestamp[_salesphaseId][_minter];

        unchecked {
            nextValidMintTimestamp =
                lastMintTimestamp +
                salesPhase.phases[_salesphaseId].waitTimeInSecondsBetweenClaims;

            if (nextValidMintTimestamp < lastMintTimestamp) {
                nextValidMintTimestamp = type(uint256).max;
            }
        }
    }

    /// @dev Returns the sales phase at the given uid.
    function getSalesPhaseById(uint256 _salesphaseId) external view returns (SalesPhase memory condition) {
        condition = salesPhase.phases[_salesphaseId];
    }

    /*///////////////////////////////////////////////////////////////
                        Setter functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Lets a contract admin set a mint count for a wallet.
    function setWalletMintCount(address _minter, uint256 _count) external onlyRole(DEFAULT_ADMIN_ROLE) {
        walletMintCount[_minter] = _count;
        emit WalletMintCountUpdated(_minter, _count);
    }

    /// @dev Lets a contract admin set a maximum number of NFTs that can be minted by any wallet.
    function setMaxWalletCount(uint256 _count) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxWalletMintCount = _count;
        emit MaxWalletMintCountUpdated(_count);
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
        
        _burn(tokenId, true);
    }

    /// @dev See {ERC721-_beforeTokenTransfer}.
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override(ERC721AUpgradeable) {
        super._beforeTokenTransfers(from, to, firstTokenId, batchSize);

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

}