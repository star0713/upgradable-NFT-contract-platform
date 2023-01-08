// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "erc721a-upgradeable/contracts/IERC721AUpgradeable.sol";
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

interface INFTCollection is IERC721AUpgradeable, INFTSalesPhase {
    /// @dev Emitted when tokens are claimed.
    event TokensMinted(
        uint256 indexed SalesPhaseIndex,
        address indexed minter,
        address indexed receiver,
        uint256 startTokenId,
        uint256 quantityMinted
    );

    /// @dev Emitted when new mint conditions are set.
    event SalesPhasesUpdated(SalesPhase[] SalesPhases);

    /// @dev Emitted when the global max supply of tokens is updated.
    event MaxTotalSupplyUpdated(uint256 maxTotalSupply);

    /// @dev Emitted when the wallet mint count for an address is updated.
    event WalletMintCountUpdated(address indexed wallet, uint256 count);

    /// @dev Emitted when the global max wallet mint count is updated.
    event MaxWalletMintCountUpdated(uint256 count);

    /**
     *  @notice Lets an account mint a given quantity of NFTs.
     *
     *  @param _receiver                       The receiver of the NFTs to mint.
     *  @param _quantity                       The quantity of NFTs to mint.
     *  @param _pricePerToken                  The price per token to pay for the mint.
     *  @param _salesPhaseId                   The current(selected) sales phase Id.
     *  @param _proofs                         The proof of the minter's inclusion in the merkle root allowlist
     *                                        of the mint conditions that apply.
     *  @param _quantityLimitPerWallet        (Optional) The maximum number of NFTs an address included in an
     *                                        allowlist can mint.
     */
    function mintTo(
        address _receiver,
        uint256 _quantity,
        uint256 _pricePerToken,
        uint256 _salesPhaseId,
        bytes32[] calldata _proofs,
        uint256 _quantityLimitPerWallet
    ) external payable;

    /**
     *  @notice Lets a contract admin (account with `DEFAULT_ADMIN_ROLE`) set mint conditions.
     *
     *  @param phases                mint conditions in ascending order by `startTimestamp`.
     *  @param resetMintEligibility    Whether to honor the restrictions applied to wallets who have claimed tokens in the current conditions,
     *                                  in the new mint conditions being set.
     *
     */
    function setSalesPhases(SalesPhase[] calldata phases, bool resetMintEligibility) external;
}
