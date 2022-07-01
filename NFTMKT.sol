// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./NFTCollection.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFTMarketplace {
    using Counters for Counters.Counter;

    Counters.Counter public _offerCount;

    address owner;

    mapping(uint256 => _Offer) public offers;
    mapping(address => uint256) public userFunds;
    // keeps track of deleted offers
    mapping(uint256 => bool) public deleted;
    // keeps track of tokenIds already in an Offer
    mapping(uint256 => bool) public taken;
    NFTCollection nftCollection;

    struct _Offer {
        uint256 id;
        address user;
        uint256 price;
        bool fulfilled;
        bool paused;
    }

    event Offer(
        uint256 offerId,
        uint256 id,
        address user,
        uint256 price,
        bool fulfilled,
        bool paused
    );

    event OfferFilled(uint256 offerId, uint256 id, address newOwner);
    event OfferPaused(uint256 offerId, uint256 id, address owner);
    event OfferResume(uint256 offerId, uint256 id, address owner);
    event OfferRemoved(uint256 offerId, uint256 id);
    event ClaimFunds(address user, uint256 amount);

    constructor(address _nftCollection) {
        nftCollection = NFTCollection(_nftCollection);
        owner = msg.sender;
    }

    modifier isValidOffer(uint256 _offerId) {
        require(!deleted[_offerId], "Offer must exist");
        _;
    }

    modifier validateOffer(uint256 _offerId) {
        _Offer memory _offer = offers[_offerId];
        require(!_offer.fulfilled, "Fulfilled offer");
        require(!_offer.paused, "Paused offer");
        _;
    }

    modifier isOfferOwner(uint256 _offerId) {
        require(
            offers[_offerId].user == msg.sender,
            "The offer can only be cancelled by the owner"
        );
        _;
    }

    // allows contract owner to change NFTCollection address
    function changeNftAddress(address _nftAddress) {
      require(msg.sender == owner, "Unauthorized user");
      require(_nftAddress != address(0), "Invalid address");
      nftCollection = NFTCollection(_nftAddress);
    }


    // creates a sale offer for NFT in NFtCollection
    function createOffer(uint256 _id, uint256 _price) public {
        require(_price > 0, "Invalid price");
        require(
            nftCollection.getApproved(_id) == msg.sender ||
                nftCollection.ownerOf(_id) == msg.sender,
            "Must be owner or an approved operator"
        );
        require(!taken[_id], "Token is already in an offer");
        taken[_id] = true;
        uint256 offerId = _offerCount.current();
        _offerCount.increment();
        offers[offerId] = _Offer(_id, msg.sender, _price, false, false);
        nftCollection.transferFrom(msg.sender, address(this), _id);
        emit Offer(offerId, _id, msg.sender, _price, false, false);
    }

    // function to buy fulfill offer and buy NFT
    function fillOffer(uint256 _offerId)
        public
        payable
        isValidOffer(_offerId)
        validateOffer(_offerId)
    {
        _Offer storage _offer = offers[_offerId];
        require(
            _offer.user != msg.sender,
            "The owner of the offer cannot fill it"
        );
        require(
            msg.value == _offer.price,
            "The ETH amount should match with the NFT Price"
        );
        
        _offer.fulfilled = true;
        taken[_offerId] = false;
        userFunds[_offer.user] += msg.value;
        deleted[_offerId] = true;
        nftCollection.transferFrom(address(this), msg.sender, _offer.id);
        delete offers[_offerId];
        emit OfferFilled(_offerId, _offer.id, msg.sender);
    }

    // Pauses an active offer
    function pauseOffer(uint256 _offerId)
        public
        isValidOffer(_offerId)
        validateOffer(_offerId)
        isOfferOwner(_offerId)
    {
        offers[_offerId].paused = true;
        emit OfferPaused(_offerId, offers[_offerId].id, msg.sender);
    }

    // Resumes a paused offer
    function resumeOffer(uint256 _offerId)
        public
        isValidOffer(_offerId)
        isOfferOwner(_offerId)
    {
        _Offer storage _offer = offers[_offerId];
        require(!_offer.fulfilled, "Fulfilled offer");
        require(_offer.paused, "Paused offer");
        _offer.paused = false;
        emit OfferResume(_offerId, _offer.id, _offer.user);
    }

    // Deletes an offer and return NFT to its respective owner
    function removeOffer(uint256 _offerId)
        public
        isOfferOwner(_offerId)
        isValidOffer(_offerId)
        validateOffer(_offerId)
    {
        taken[_offerId] = false;
        deleted[_offerId] = true;
        nftCollection.transferFrom(
            address(this),
            msg.sender,
            offers[_offerId].id
        );
        uint256 id = offers[_offerId].id;
        delete offers[_offerId];
        emit OfferRemoved(_offerId, id);
    }

    function claimFunds() public {
        require(
            userFunds[msg.sender] > 0,
            "This user has no funds to be claimed"
        );
        uint256 amount = userFunds[msg.sender];
        userFunds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "failed to claim funds");
        emit ClaimFunds(msg.sender, userFunds[msg.sender]);
    }

    // Fallback: reverts if Ether is sent to this smart-contract by mistake
    fallback() external {
        revert();
    }
}
