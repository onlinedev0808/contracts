import { ethers } from "hardhat";
import { expect } from "chai";

// Contract Types
import { Forwarder } from "../../../typechain/Forwarder";
import { AccessNFT } from "../../../typechain/AccessNFT";
import { Coin } from "../../../typechain/Coin";
import { MarketWithAuction, ListingParametersStruct, ListingStruct } from "../../../typechain/MarketWithAuction";

// Types
import { BigNumberish, BigNumber, Signer } from "ethers";
import { BytesLike } from "@ethersproject/bytes";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

// Test utils
import { getContracts, Contracts } from "../../../utils/tests/getContracts";
import { getURIs, getAmounts, getBoundedEtherAmount, getAmountBounded } from "../../../utils/tests/params";
import { sendGaslessTx } from "../../../utils/tests/gasless";

describe("Close / Cancel auction", function () {
  // Signers
  let protocolProvider: SignerWithAddress;
  let protocolAdmin: SignerWithAddress;
  let creator: SignerWithAddress;
  let buyer: SignerWithAddress;
  let relayer: SignerWithAddress;

  // Contracts
  let marketv2: MarketWithAuction;
  let accessNft: AccessNFT;
  let coin: Coin;
  let forwarder: Forwarder;

  // Reward parameters
  const rewardURIs: string[] = getURIs();
  const accessURIs = getURIs(rewardURIs.length);
  const rewardSupplies: number[] = getAmounts(rewardURIs.length);
  const emptyData: BytesLike = ethers.utils.toUtf8Bytes("");

  // Token IDs
  let rewardId: number = 1;

  // Market params
  enum ListingType { Direct = 0, Auction = 1 }
  const buyoutPricePerToken: BigNumber = ethers.utils.parseEther("2");
  const reservePricePerToken: BigNumberish = ethers.utils.parseEther("1");
  const totalQuantityOwned: BigNumberish = rewardSupplies[0]
  const quantityToList = totalQuantityOwned;
  const secondsUntilStartTime: number = 100;
  const secondsUntilEndTime: number = 200;

  let listingParams: ListingParametersStruct;
  let listingId: BigNumberish;

  before(async () => {
    // Get signers
    const signers: SignerWithAddress[] = await ethers.getSigners();
    [protocolProvider, protocolAdmin, creator, buyer, relayer] = signers;
  });

  beforeEach(async () => {
    // Get contracts
    const contracts: Contracts = await getContracts(protocolProvider, protocolAdmin);
    marketv2 = contracts.marketv2;
    accessNft = contracts.accessNft;
    coin = contracts.coin;
    forwarder = contracts.forwarder;

    // Grant minter role to creator
    const MINTER_ROLE = await accessNft.MINTER_ROLE();
    await accessNft.connect(protocolAdmin).grantRole(MINTER_ROLE, creator.address);

    // Create access tokens
    await sendGaslessTx(creator, forwarder, relayer, {
      from: creator.address,
      to: accessNft.address,
      data: accessNft.interface.encodeFunctionData("createAccessTokens", [
        creator.address,
        rewardURIs,
        accessURIs,
        rewardSupplies,
        emptyData,
      ]),
    });

    // Approve Market to transfer tokens
    await accessNft.connect(creator).setApprovalForAll(marketv2.address, true);

    listingParams = {
      assetContract: accessNft.address,
      tokenId: rewardId,
      
      secondsUntilStartTime: secondsUntilStartTime,
      secondsUntilEndTime: secondsUntilEndTime,

      quantityToList: quantityToList,
      currencyToAccept: coin.address,

      reservePricePerToken: reservePricePerToken,
      buyoutPricePerToken: buyoutPricePerToken,

      listingType: ListingType.Auction
    }

    listingId = await marketv2.totalListings();
    await marketv2.connect(creator).createListing(listingParams);

    // Mint currency to buyer
    await coin.connect(protocolAdmin).mint(buyer.address, buyoutPricePerToken.mul(quantityToList));

    // Approve Market to transfer currency
    await coin.connect(buyer).approve(marketv2.address, buyoutPricePerToken.mul(quantityToList));
  });

  describe("Cancel auction", function() {
    
    describe("Revert cases", function() {
      it("Should revert if caller is not auction creator.", async () => {
        await expect(
          marketv2.connect(buyer).closeAuction(listingId)
        ).to.be.revertedWith("Market: caller is not the listing creator.")
      })
    })

    describe("Events", function() {
      it("Should emit AuctionCanceled with relevant info", async () => {
        
        const eventPromise = new Promise((resolve, reject) => {
          marketv2.on("AuctionCanceled", async (
            _listingId,
            _auctionCreator,
            _listing
          ) => {

            expect(_listingId).to.equal(listingId)
            expect(_auctionCreator).to.equal(creator.address);

            expect(_listing.listingId).to.equal(listingId);
            expect(_listing.tokenOwner).to.equal(creator.address);
            expect(_listing.assetContract).to.equal(accessNft.address);
            expect(_listing.tokenId).to.equal(rewardId);
            
            const timeStamp = (await ethers.provider.getBlock("latest")).timestamp
            expect(_listing.startTime).to.be.gt(timeStamp);

            expect(_listing.quantity).to.equal(0)
            expect(_listing.currency).to.equal(coin.address);
            expect(_listing.reservePricePerToken).to.equal(reservePricePerToken);
            expect(_listing.buyoutPricePerToken).to.equal(buyoutPricePerToken);
            expect(_listing.tokenType).to.equal(0) // 0 == ERC1155
            expect(_listing.listingType).to.equal(ListingType.Auction);

            resolve(null);
          })

          setTimeout(() => {
            reject(new Error("Timeout: AuctionCanceled"));
          }, 10000)
        })

        await marketv2.connect(creator).closeAuction(listingId)
        await eventPromise.catch(e => console.error(e));
      })
    })

    describe("Balances", function() {

      it("Should transfer back tokens to auction creator", async () => {
        const creatorBalBefore: BigNumber = await accessNft.balanceOf(creator.address, rewardId)
        const marketBalBefore: BigNumber = await accessNft.balanceOf(marketv2.address, rewardId)
        
        await marketv2.connect(creator).closeAuction(listingId)

        const creatorBalAfter: BigNumber = await accessNft.balanceOf(creator.address, rewardId)
        const marketBalAfter: BigNumber = await accessNft.balanceOf(marketv2.address, rewardId)

        expect(creatorBalAfter).to.equal(creatorBalBefore.add(quantityToList))
        expect(marketBalAfter).to.equal(marketBalBefore.sub(quantityToList))
      })
    })

    describe("Contract state", function() {
      it("Should reset listing end time and quantity", async () => {
        await marketv2.connect(creator).closeAuction(listingId)

        const listing = await marketv2.listings(listingId);

        expect(listing.quantity).to.equal(0)
        const timeStamp = (await ethers.provider.getBlock("latest")).timestamp;
        expect(listing.endTime).to.equal(timeStamp);
      })
    })
  })

  describe("Regular auction closing", function() {

    beforeEach(async () => {

      // Time travel
      for (let i = 0; i < secondsUntilStartTime; i++) {
        await ethers.provider.send("evm_mine", []);
      }

      const quantityWanted: BigNumberish = 1;
      const offerAmount = reservePricePerToken.mul(quantityToList);

      await marketv2.connect(buyer).offer(listingId, quantityWanted, offerAmount)
    })

    describe("Revert cases", function() {
      
      it("Should revert if caller is not auction creator or bidder.", async () => {
        await expect(
          marketv2.connect(relayer).closeAuction(listingId)
        ).to.be.revertedWith("Market: must be bidder or auction creator.")
      })

      it("Should revert if listing is not an auction.", async () => {
        const newListingId = await marketv2.totalListings();
        const newListingParams = {...listingParams, tokenId: 3, quantityToList: 1, secondsUntilStartTime: 0, listingType: ListingType.Direct};

        await marketv2.connect(creator).createListing(newListingParams);

        await expect(
          marketv2.connect(creator).closeAuction(newListingId)
        ).to.be.revertedWith("Market: listing is not an auction.");
      })

      it("Should revert if the auction duration is not over.", async () => {
        await expect(
          marketv2.connect(creator).closeAuction(listingId)
        ).to.be.revertedWith("Market: can only close auction after it has ended.")
      })
    })

    describe("Events", function() {

      beforeEach(async () => {

        // Time travel to auction start
        for (let i = 0; i < secondsUntilStartTime; i++) {
          await ethers.provider.send("evm_mine", []);
        }
  
        const quantityWanted: BigNumberish = 1;
        const offerAmount = reservePricePerToken.mul(quantityToList);
  
        await marketv2.connect(buyer).offer(listingId, quantityWanted, offerAmount)

        // Time travel to auction end
        const endTime: BigNumber = (await marketv2.listings(listingId)).endTime;
        while(true) {
          await ethers.provider.send("evm_mine", []);

          const timeStamp: BigNumber = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
          if(endTime.lt(timeStamp)) {
            break;
          }
        }
      })

      const getEventPromise = () => {
        return new Promise((resolve, reject) => {
          marketv2.on("AuctionClosed", (
            _listingId,
            _closer,
            _auctionCreator,
            _winningBidder,
            _winningBid,
            _listing
          ) => {

            expect(_listingId).to.equal(listingId)
            expect(_auctionCreator).to.equal(creator.address)
            expect(_winningBidder).to.equal(buyer.address)
            
            const isValidCloser = _closer == buyer.address || _closer == creator.address
            expect(isValidCloser).to.equal(true);

            resolve(null);
          })

          setTimeout(() => {
            reject(new Error("Timeout: AuctionClosed"))
          }, 10000);
        })
      }

      it("Should emit AuctionClosed with relevant closing info: closed by lister", async () => {
        await marketv2.connect(creator).closeAuction(listingId)
        await getEventPromise().catch(e => console.error(e))
      })

      it("Should emit AuctionClosed with relevant closing info: closed by bidder", async () => {
        await marketv2.connect(buyer).closeAuction(listingId)
        await getEventPromise().catch(e => console.error(e))
      })
    })

    describe("Balances", function() {

      let quantityWanted: BigNumberish;
      let offerAmount: BigNumber;

      beforeEach(async () => {

        // Time travel to auction start
        for (let i = 0; i < secondsUntilStartTime; i++) {
          await ethers.provider.send("evm_mine", []);
        }
  
        quantityWanted = 1;
        offerAmount = reservePricePerToken.mul(quantityToList);
  
        await marketv2.connect(buyer).offer(listingId, quantityWanted, offerAmount)

        // Time travel to auction end
        const endTime: BigNumber = (await marketv2.listings(listingId)).endTime;
        while(true) {
          await ethers.provider.send("evm_mine", []);

          const timeStamp: BigNumber = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
          if(endTime.lt(timeStamp)) {
            break;
          }
        }
      })
      
      it("Should payout bid to lister when called by lister", async () => {
        
        const creatorBalBefore: BigNumber = await coin.balanceOf(creator.address)
        const marketBalBefore: BigNumber = await coin.balanceOf(marketv2.address);

        await marketv2.connect(creator).closeAuction(listingId)

        const creatorBalAfter: BigNumber = await coin.balanceOf(creator.address)
        const marketBalAfter: BigNumber = await coin.balanceOf(marketv2.address);

        expect(creatorBalAfter).to.equal(creatorBalBefore.add(offerAmount))
        expect(marketBalAfter).to.equal(marketBalBefore.sub(offerAmount))
      })

      it("Should transfer auctioned tokens to bidder when called by bidder", async () => {
        const marketBalBefore: BigNumber = await accessNft.balanceOf(marketv2.address, rewardId)
        const buyerBalBefore: BigNumber = await accessNft.balanceOf(buyer.address, rewardId);

        await marketv2.connect(buyer).closeAuction(listingId)

        const marketBalAfter: BigNumber = await accessNft.balanceOf(marketv2.address, rewardId)
        const buyerBalAfter: BigNumber = await accessNft.balanceOf(buyer.address, rewardId);

        expect(marketBalAfter).to.equal(marketBalBefore.sub(quantityToList))
        expect(buyerBalAfter).to.equal(buyerBalBefore.add(quantityToList))
      })

      it("Should not affect any currency balances on repeat calls by bidder of lister", async () => {
        await marketv2.connect(creator).closeAuction(listingId)
        await marketv2.connect(buyer).closeAuction(listingId)
        
        const creatorBalBefore: BigNumber = await coin.balanceOf(creator.address)
        const marketBalBefore: BigNumber = await coin.balanceOf(marketv2.address);

        await marketv2.connect(creator).closeAuction(listingId)

        const creatorBalAfter: BigNumber = await coin.balanceOf(creator.address)
        const marketBalAfter: BigNumber = await coin.balanceOf(marketv2.address);

        expect(creatorBalAfter).to.equal(creatorBalBefore)
        expect(marketBalBefore).to.equal(marketBalAfter)
      })

      it("Should not affect any token balances on repeat calls by bidder of lister", async () => {
        await marketv2.connect(creator).closeAuction(listingId)
        await marketv2.connect(buyer).closeAuction(listingId)
        
        const marketBalBefore: BigNumber = await accessNft.balanceOf(marketv2.address, rewardId)
        const buyerBalBefore: BigNumber = await accessNft.balanceOf(buyer.address, rewardId);

        await marketv2.connect(buyer).closeAuction(listingId)

        const marketBalAfter: BigNumber = await accessNft.balanceOf(marketv2.address, rewardId)
        const buyerBalAfter: BigNumber = await accessNft.balanceOf(buyer.address, rewardId);

        expect(marketBalAfter).to.equal(marketBalBefore)
        expect(buyerBalAfter).to.equal(buyerBalBefore)
      })
    })

    describe("Contract state", function() {
      let quantityWanted: BigNumberish;
      let offerAmount: BigNumber;

      beforeEach(async () => {

        // Time travel to auction start
        for (let i = 0; i < secondsUntilStartTime; i++) {
          await ethers.provider.send("evm_mine", []);
        }
  
        quantityWanted = 1;
        offerAmount = reservePricePerToken.mul(quantityToList);
  
        await marketv2.connect(buyer).offer(listingId, quantityWanted, offerAmount)

        // Time travel to auction end
        const endTime: BigNumber = (await marketv2.listings(listingId)).endTime;
        while(true) {
          await ethers.provider.send("evm_mine", []);

          const timeStamp: BigNumber = BigNumber.from((await ethers.provider.getBlock("latest")).timestamp);
          if(endTime.lt(timeStamp)) {
            break;
          }
        }
      })

      it("Should reset listing quantity, end time, and offer's offer amount when called by lister", async () => {
        await marketv2.connect(creator).closeAuction(listingId)

        const listing = await marketv2.listings(listingId)
        expect(listing.quantity).to.equal(0)
        expect(listing.endTime).to.equal(
          (await ethers.provider.getBlock("latest")).timestamp
        )

        const offer = await marketv2.winningBid(listingId)
        expect(offer.offerAmount).to.equal(0);
      })

      it("Should reset the bid's quantity when called by bidder", async () => {
        await marketv2.connect(buyer).closeAuction(listingId)

        const offer = await marketv2.winningBid(listingId)
        expect(offer.quantityWanted).to.equal(0);
      })
    })
  })
});