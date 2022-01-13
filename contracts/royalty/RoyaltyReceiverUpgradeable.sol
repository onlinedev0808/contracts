// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

// Royalty standard
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

// Utils
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RoyaltyReceiverUpgradeable is IERC2981, Initializable {
    /// @dev The recipient of who gets the royalty.
    address public royaltyReceipient;

    /// @dev The percentage of royalty how much royalty in basis points.
    uint96 public royaltyBps;

    /// @dev Emitted when the royalty recipient or fee bps is updated
    event RoyaltyUpdated(address newRoyaltyRecipient, uint96 newRoyaltyBps);

    /// @dev Initializes the contract, like a constructor.
    function __RoyaltyReceiver_init(address _receiver, uint96 _royaltyBps) internal onlyInitializing {
        __RoyaltyReceiver_init_unchained(_receiver, _royaltyBps);
    }

    function __RoyaltyReceiver_init_unchained(address _receiver, uint96 _royaltyBps) internal onlyInitializing {
        royaltyReceipient = _receiver;
        royaltyBps = _royaltyBps;
    }

    /**
     * @dev For setting NFT royalty recipient.
     *
     * @param _royaltyRecipient The address of which the royalty goes to.
     */
    function _setRoyaltyRecipient(address _royaltyRecipient) internal {
        royaltyReceipient = _royaltyRecipient;
        emit RoyaltyUpdated(royaltyReceipient, royaltyBps);
    }

    /**
     * @dev For setting royalty basis points.
     *
     * @param _royaltyBps the basis points of royalty. 10_000 = 100%.
     */
    function _setRoyaltyBps(uint256 _royaltyBps) internal {
        require(_royaltyBps <= 10_000, "exceed royalty bps");
        royaltyBps = uint96(_royaltyBps);
        emit RoyaltyUpdated(royaltyReceipient, royaltyBps);
    }

    /// @dev See EIP-2981
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        virtual
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = royaltyReceipient;
        royaltyAmount = (salePrice * royaltyBps) / 10_000;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC2981).interfaceId;
    }
}