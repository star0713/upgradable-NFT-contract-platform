// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "./INFTSalesPhase.sol";

/**
 *  Sparkblox's 'Drop' contracts are distribution mechanisms for tokens. The
 *  `DropERC721` contract is a distribution mechanism for ERC721 tokens.
 *
 *  A minter wallet (i.e. holder of `MINTER_ROLE`) can (lazy)mint 'n' tokens
 *  at once by providing a single base URI for all tokens being lazy minted.
 *  The URI for each of the 'n' tokens lazy minted is the provided base URI +
 *  `{tokenId}` of the respective token. (e.g. "ipsf://Qmece.../1").
 *
 *  A minter can choose to lazy mint 'delayed-reveal' tokens.
 *
 *  A contract admin (i.e. holder of `DEFAULT_ADMIN_ROLE`) can create claim conditions
 *  with non-overlapping time windows, and accounts can claim the tokens according to
 *  restrictions defined in the claim condition that is active at the time of the transaction.
 */

interface INFTDrop is IERC721Upgradeable, INFTSalesPhase {
    /// @dev Emitted when tokens are claimed.
    event TokensClaimed(
        uint256 indexed SalesPhaseIndex,
        address indexed claimer,
        address indexed receiver,
        uint256 startTokenId,
        uint256 quantityClaimed
    );

    /// @dev Emitted when tokens are lazy minted.
    event TokensLazyMinted(uint256 startTokenId, uint256 endTokenId, string baseURI, bytes encryptedBaseURI);

    /// @dev Emitted when the URI for a batch of 'delayed-reveal' NFTs is revealed.
    event NFTRevealed(uint256 endTokenId, string revealedURI);

    /// @dev Emitted when new claim conditions are set.
    event SalesPhasesUpdated(SalesPhase[] SalesPhases);

    /// @dev Emitted when the global max supply of tokens is updated.
    event MaxTotalSupplyUpdated(uint256 maxTotalSupply);

    /// @dev Emitted when the wallet claim count for an address is updated.
    event WalletClaimCountUpdated(address indexed wallet, uint256 count);

    /// @dev Emitted when the global max wallet claim count is updated.
    event MaxWalletClaimCountUpdated(uint256 count);

    /**
     *  @notice Lets an account with `MINTER_ROLE` lazy mint 'n' NFTs.
     *          The URIs for each token is the provided `_baseURIForTokens` + `{tokenId}`.
     *
     *  @param amount           The amount of NFTs to lazy mint.
     *  @param baseURIForTokens The URI for the NFTs to lazy mint. If lazy minting
     *                           'delayed-reveal' NFTs, the is a URI for NFTs in the
     *                           un-revealed state.
     *  @param encryptedBaseURI If lazy minting 'delayed-reveal' NFTs, this is the
     *                           result of encrypting the URI of the NFTs in the revealed
     *                           state.
     */
    function lazyMint(
        uint256 amount,
        string calldata baseURIForTokens,
        bytes calldata encryptedBaseURI
    ) external;

    /**
     *  @notice Lets an account claim a given quantity of NFTs.
     *
     *  @param _receiver                       The receiver of the NFTs to claim.
     *  @param _quantity                       The quantity of NFTs to claim.
     *  @param _pricePerToken                  The price per token to pay for the claim.
     *  @param _salesPhaseId                   The current(selected) sales phase Id.
     *  @param _proofs                         The proof of the claimer's inclusion in the merkle root allowlist
     *                                        of the claim conditions that apply.
     *  @param _quantityLimitPerWallet        (Optional) The maximum number of NFTs an address included in an
     *                                        allowlist can claim.
     */
    function claim(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) external payable;

    /**
     *  @notice Lets a contract admin (account with `DEFAULT_ADMIN_ROLE`) set claim conditions.
     *
     *  @param phases                Claim conditions in ascending order by `startTimestamp`.
     *  @param resetClaimEligibility    Whether to honor the restrictions applied to wallets who have claimed tokens in the current conditions,
     *                                  in the new claim conditions being set.
     *
     */
    function setSalesPhases(SalesPhase[] calldata phases, bool resetClaimEligibility) external;
}
