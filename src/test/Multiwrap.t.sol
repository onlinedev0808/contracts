// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { Multiwrap } from "contracts/multiwrap/Multiwrap.sol";
import { ITokenBundle } from "contracts/feature/interface/ITokenBundle.sol";

// Test imports
import { MockERC20 } from "./mocks/MockERC20.sol";
import { Wallet } from "./utils/Wallet.sol";
import "./utils/BaseTest.sol";

contract MultiwrapReentrant is MockERC20, ITokenBundle {
    Multiwrap internal multiwrap;
    uint256 internal tokenIdOfWrapped = 0;

    constructor(address _multiwrap) {
        multiwrap = Multiwrap(_multiwrap);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        multiwrap.unwrap(0, address(this));
        return super.transferFrom(from, to, amount);
    }
}

contract MultiwrapTest is BaseTest {
    /// @dev Emitted when tokens are wrapped.
    event TokensWrapped(
        address indexed wrapper,
        address indexed recipientOfWrappedToken,
        uint256 indexed tokenIdOfWrappedToken,
        ITokenBundle.Token[] wrappedContents
    );

    /// @dev Emitted when tokens are unwrapped.
    event TokensUnwrapped(
        address indexed unwrapper,
        address indexed recipientOfWrappedContents,
        uint256 indexed tokenIdOfWrappedToken
    );

    /*///////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    Multiwrap internal multiwrap;

    Wallet internal tokenOwner;
    string internal uriForWrappedToken;
    ITokenBundle.Token[] internal wrappedContent;

    function setUp() public override {
        super.setUp();

        // Get target contract
        multiwrap = Multiwrap(getContract("Multiwrap"));

        // Set test vars
        tokenOwner = getWallet();
        uriForWrappedToken = "ipfs://baseURI/";

        wrappedContent.push(
            ITokenBundle.Token({
                assetContract: address(erc20),
                tokenType: ITokenBundle.TokenType.ERC20,
                tokenId: 0,
                totalAmount: 10 ether
            })
        );
        wrappedContent.push(
            ITokenBundle.Token({
                assetContract: address(erc721),
                tokenType: ITokenBundle.TokenType.ERC721,
                tokenId: 0,
                totalAmount: 1
            })
        );
        wrappedContent.push(
            ITokenBundle.Token({
                assetContract: address(erc1155),
                tokenType: ITokenBundle.TokenType.ERC1155,
                tokenId: 0,
                totalAmount: 100
            })
        );

        // Mint tokens-to-wrap to `tokenOwner`
        erc20.mint(address(tokenOwner), 10 ether);
        erc721.mint(address(tokenOwner), 1);
        erc1155.mint(address(tokenOwner), 0, 100);

        // Token owner approves `Multiwrap` to transfer tokens.
        tokenOwner.setAllowanceERC20(address(erc20), address(multiwrap), type(uint).max);
        tokenOwner.setApprovalForAllERC721(address(erc721), address(multiwrap), true);
        tokenOwner.setApprovalForAllERC1155(address(erc1155), address(multiwrap), true);

        // Grant MINTER_ROLE / requisite wrapping permissions to `tokenOwer`
        vm.prank(deployer);
        multiwrap.grantRole(keccak256("MINTER_ROLE"), address(tokenOwner));
    }

    /**
     *      Unit tests for relevant functions:
     *      - `wrap`
     *      - `unwrap`
     */

    /*///////////////////////////////////////////////////////////////
                        Unit tests: `wrap`
    //////////////////////////////////////////////////////////////*/

    /**
     *  note: Testing state changes; token owner calls `wrap` to wrap owned tokens.
     */
    function test_state_wrap() public {
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        assertEq(expectedIdForWrappedToken + 1, multiwrap.nextTokenIdToMint());

        ITokenBundle.Token[] memory contentsOfWrappedToken = multiwrap.getWrappedContents(expectedIdForWrappedToken);
        assertEq(contentsOfWrappedToken.length, wrappedContent.length);
        for (uint256 i = 0; i < contentsOfWrappedToken.length; i += 1) {
            assertEq(contentsOfWrappedToken[i].assetContract, wrappedContent[i].assetContract);
            assertEq(uint256(contentsOfWrappedToken[i].tokenType), uint256(wrappedContent[i].tokenType));
            assertEq(contentsOfWrappedToken[i].tokenId, wrappedContent[i].tokenId);
            assertEq(contentsOfWrappedToken[i].totalAmount, wrappedContent[i].totalAmount);
        }

        assertEq(uriForWrappedToken, multiwrap.tokenURI(expectedIdForWrappedToken));
    }

    /**
     *  note: Testing event emission; token owner calls `wrap` to wrap owned tokens.
     */
    function test_event_wrap_TokensWrapped() public {
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));

        vm.expectEmit(true, true, true, true);
        emit TokensWrapped(address(tokenOwner), recipient, expectedIdForWrappedToken, wrappedContent);

        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);
    }

    /**
     *  note: Testing token balances; token owner calls `wrap` to wrap owned tokens.
     */
    function test_balances_wrap() public {
        // ERC20 balance
        assertEq(erc20.balanceOf(address(tokenOwner)), 10 ether);
        assertEq(erc20.balanceOf(address(multiwrap)), 0);

        // ERC721 balance
        assertEq(erc721.ownerOf(0), address(tokenOwner));

        // ERC1155 balance
        assertEq(erc1155.balanceOf(address(tokenOwner), 0), 100);
        assertEq(erc1155.balanceOf(address(multiwrap), 0), 0);

        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ERC20 balance
        assertEq(erc20.balanceOf(address(tokenOwner)), 0);
        assertEq(erc20.balanceOf(address(multiwrap)), 10 ether);

        // ERC721 balance
        assertEq(erc721.ownerOf(0), address(multiwrap));

        // ERC1155 balance
        assertEq(erc1155.balanceOf(address(tokenOwner), 0), 0);
        assertEq(erc1155.balanceOf(address(multiwrap), 0), 100);

        // Multiwrap wrapped token balance
        assertEq(multiwrap.ownerOf(expectedIdForWrappedToken), recipient);
    }

    /**
     *  note: Testing revert condition; token owner calls `wrap` to wrap owned tokens.
     */
    function test_revert_wrap_reentrancy() public {
        MultiwrapReentrant reentrant = new MultiwrapReentrant(address(multiwrap));
        ITokenBundle.Token[] memory reentrantContentToWrap = new ITokenBundle.Token[](1);

        reentrant.mint(address(tokenOwner), 10 ether);
        reentrantContentToWrap[0] = ITokenBundle.Token({
            assetContract: address(reentrant),
            tokenType: ITokenBundle.TokenType.ERC20,
            tokenId: 0,
            totalAmount: 10 ether
        });

        tokenOwner.setAllowanceERC20(address(reentrant), address(multiwrap), 10 ether);

        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        multiwrap.wrap(reentrantContentToWrap, uriForWrappedToken, recipient);
    }

    /**
     *  note: Testing revert condition; token owner calls `wrap` to wrap owned tokens, without MINTER_ROLE.
     */
    function test_revert_wrap_access_MINTER_ROLE() public {
        vm.prank(address(tokenOwner));
        multiwrap.renounceRole(keccak256("MINTER_ROLE"), address(tokenOwner));

        address recipient = address(0x123);

        string memory errorMsg = string(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(address(tokenOwner)), 20),
                " is missing role ",
                Strings.toHexString(uint256(keccak256("MINTER_ROLE")), 32)
            )
        );

        vm.prank(address(tokenOwner));
        vm.expectRevert(bytes(errorMsg));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);
    }

    /**
     *  note: Testing revert condition; token owner calls `wrap` to wrap un-owned ERC20 tokens.
     */
    function test_revert_wrap_notOwner_ERC20() public {
        tokenOwner.transferERC20(address(erc20), address(0x12), 10 ether);

        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);
    }

    /**
     *  note: Testing revert condition; token owner calls `wrap` to wrap un-owned ERC721 tokens.
     */
    function test_revert_wrap_notOwner_ERC721() public {
        tokenOwner.transferERC721(address(erc721), address(0x12), 0);

        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);
    }

    /**
     *  note: Testing revert condition; token owner calls `wrap` to wrap un-owned ERC1155 tokens.
     */
    function test_revert_wrap_notOwner_ERC1155() public {
        tokenOwner.transferERC1155(address(erc1155), address(0x12), 0, 100, "");

        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        vm.expectRevert("ERC1155: insufficient balance for transfer");
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);
    }

    function test_revert_wrap_noTokensToWrap() public {
        ITokenBundle.Token[] memory emptyContent;

        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        vm.expectRevert("TokenBundle: no tokens to bind.");
        multiwrap.wrap(emptyContent, uriForWrappedToken, recipient);
    }

    /*///////////////////////////////////////////////////////////////
                        Unit tests: `unwrap`
    //////////////////////////////////////////////////////////////*/

    /**
     *  note: Testing state changes; wrapped token owner calls `unwrap` to unwrap underlying tokens.
     */
    function test_state_unwrap() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        vm.prank(recipient);
        multiwrap.unwrap(expectedIdForWrappedToken, recipient);

        vm.expectRevert("ERC721: owner query for nonexistent token");
        multiwrap.ownerOf(expectedIdForWrappedToken);

        assertEq("", multiwrap.tokenURI(expectedIdForWrappedToken));

        ITokenBundle.Token[] memory contentsOfWrappedToken = multiwrap.getWrappedContents(expectedIdForWrappedToken);
        assertEq(contentsOfWrappedToken.length, 0);
    }

    /**
     *  note: Testing state changes; wrapped token owner calls `unwrap` to unwrap underlying tokens.
     */
    function test_state_unwrap_approvedCaller() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        address approvedCaller = address(0x12);

        vm.prank(recipient);
        multiwrap.setApprovalForAll(approvedCaller, true);

        vm.prank(approvedCaller);
        multiwrap.unwrap(expectedIdForWrappedToken, recipient);

        vm.expectRevert("ERC721: owner query for nonexistent token");
        multiwrap.ownerOf(expectedIdForWrappedToken);

        assertEq("", multiwrap.tokenURI(expectedIdForWrappedToken));

        ITokenBundle.Token[] memory contentsOfWrappedToken = multiwrap.getWrappedContents(expectedIdForWrappedToken);
        assertEq(contentsOfWrappedToken.length, 0);
    }

    function test_event_unwrap_TokensUnwrapped() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        vm.prank(recipient);

        vm.expectEmit(true, true, true, true);
        emit TokensUnwrapped(recipient, recipient, expectedIdForWrappedToken);

        multiwrap.unwrap(expectedIdForWrappedToken, recipient);
    }

    function test_balances_unwrap() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        // ERC20 balance
        assertEq(erc20.balanceOf(address(recipient)), 0);
        assertEq(erc20.balanceOf(address(multiwrap)), 10 ether);

        // ERC721 balance
        assertEq(erc721.ownerOf(0), address(multiwrap));

        // ERC1155 balance
        assertEq(erc1155.balanceOf(address(recipient), 0), 0);
        assertEq(erc1155.balanceOf(address(multiwrap), 0), 100);

        vm.prank(recipient);
        multiwrap.unwrap(expectedIdForWrappedToken, recipient);

        // ERC20 balance
        assertEq(erc20.balanceOf(address(recipient)), 10 ether);
        assertEq(erc20.balanceOf(address(multiwrap)), 0);

        // ERC721 balance
        assertEq(erc721.ownerOf(0), address(recipient));

        // ERC1155 balance
        assertEq(erc1155.balanceOf(address(recipient), 0), 100);
        assertEq(erc1155.balanceOf(address(multiwrap), 0), 0);
    }

    function test_revert_unwrap_invalidTokenId() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        vm.prank(recipient);
        vm.expectRevert("invalid tokenId");
        multiwrap.unwrap(expectedIdForWrappedToken + 1, recipient);
    }

    function test_revert_unwrap_unapprovedCaller() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        vm.prank(address(0x12));
        vm.expectRevert("unapproved called");
        multiwrap.unwrap(expectedIdForWrappedToken, recipient);
    }

    function test_revert_unwrap_notOwner() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        vm.prank(recipient);
        multiwrap.transferFrom(recipient, address(0x12), 0);

        vm.prank(recipient);
        vm.expectRevert("unapproved called");
        multiwrap.unwrap(expectedIdForWrappedToken, recipient);
    }

    function test_revert_unwrap_access_UNWRAP_ROLE() public {
        // ===== setup: wrap tokens =====
        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        multiwrap.wrap(wrappedContent, uriForWrappedToken, recipient);

        // ===== target test content =====

        vm.prank(deployer);
        multiwrap.revokeRole(keccak256("UNWRAP_ROLE"), address(0));

        string memory errorMsg = string(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(recipient), 20),
                " is missing role ",
                Strings.toHexString(uint256(keccak256("UNWRAP_ROLE")), 32)
            )
        );

        vm.prank(recipient);
        vm.expectRevert(bytes(errorMsg));
        multiwrap.unwrap(expectedIdForWrappedToken, recipient);
    }

    /**
     *      Fuzz testing:
     *      - Wrapping and unwrapping arbitrary kinds of tokens
     */

    uint256 internal constant MAX_TOKENS = 1000;

    function getTokensToWrap(uint256 x) internal returns (ITokenBundle.Token[] memory tokensToWrap) {
        uint256 len = x % MAX_TOKENS;
        tokensToWrap = new ITokenBundle.Token[](len);

        for(uint256 i = 0; i < len; i += 1) {
            
            uint256 random = uint(keccak256(abi.encodePacked(len + i))) % MAX_TOKENS;
            uint256 selector = random % 3;

            if(selector == 0) {

                tokensToWrap[i] = ITokenBundle.Token({
                    assetContract: address(erc20),
                    tokenType: ITokenBundle.TokenType.ERC20,
                    tokenId: 0,
                    totalAmount: random
                });

                erc20.mint(address(tokenOwner), tokensToWrap[i].totalAmount);

            } else if (selector == 1) {

                uint256 tokenId = erc721.nextTokenIdToMint();

                tokensToWrap[i] = ITokenBundle.Token({
                    assetContract: address(erc721),
                    tokenType: ITokenBundle.TokenType.ERC721,
                    tokenId: tokenId,
                    totalAmount: 1
                });

                erc721.mint(address(tokenOwner), 1);

            } else if (selector == 2) {

                tokensToWrap[i] = ITokenBundle.Token({
                    assetContract: address(erc1155),
                    tokenType: ITokenBundle.TokenType.ERC1155,
                    tokenId: random,
                    totalAmount: random
                });

                erc1155.mint(address(tokenOwner), tokensToWrap[i].tokenId, tokensToWrap[i].totalAmount);
            }
        }
    }

    function test_fuzz_wrap(uint256 x) public {
        ITokenBundle.Token[] memory tokensToWrap = getTokensToWrap(x);

        uint256 expectedIdForWrappedToken = multiwrap.nextTokenIdToMint();
        address recipient = address(0x123);

        vm.prank(address(tokenOwner));
        if(x == 0) {
            vm.expectRevert("TokenBundle: no tokens to bind.");
            multiwrap.wrap(tokensToWrap, uriForWrappedToken, recipient);
        } else {
            
            multiwrap.wrap(tokensToWrap, uriForWrappedToken, recipient);

            assertEq(expectedIdForWrappedToken + 1, multiwrap.nextTokenIdToMint());

            ITokenBundle.Token[] memory contentsOfWrappedToken = multiwrap.getWrappedContents(expectedIdForWrappedToken);
            assertEq(contentsOfWrappedToken.length, tokensToWrap.length);
            for (uint256 i = 0; i < contentsOfWrappedToken.length; i += 1) {
                assertEq(contentsOfWrappedToken[i].assetContract, tokensToWrap[i].assetContract);
                assertEq(uint256(contentsOfWrappedToken[i].tokenType), uint256(tokensToWrap[i].tokenType));
                assertEq(contentsOfWrappedToken[i].tokenId, tokensToWrap[i].tokenId);
                assertEq(contentsOfWrappedToken[i].totalAmount, tokensToWrap[i].totalAmount);
            }

            assertEq(uriForWrappedToken, multiwrap.tokenURI(expectedIdForWrappedToken));
        }
    }
}
