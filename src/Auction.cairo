#[contract]
mod NFTAuction {
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;
    use starknet::u256;
    use starknet::Zeroable;
    use starknet::OptionTrait;
    use starknet::Array;
    use starknet::LegacyMap;

    type Address = ContractAddress;

    const AUCTION_DURATION: u64 = 604800; // 7 days in seconds

    // Storage structure for the auction contract
    struct Storage {
        auctions: LegacyMap<u256, Auction>,
    }

    // Auction structure
    struct Auction {
        seller: Address,
        nft_contract: Address,
        token_id: u256,
        starting_price: u256,
        current_bidder: Option<Address>,
        current_bid: u256,
        start_time: u64,
        end_time: u64,
        finalized: bool,
    }

    // Events
    #[event]
    fn AuctionCreated(u256);

    #[event]
    fn BidPlaced(u256, Address, u256);

    #[event]
    fn AuctionFinalized(u256, Address, Address, u256);

    // Constructor
    #[constructor]
    fn initialize() {}

    // External functions

    // Create a new auction
    #[external]
    fn createAuction(
        nft_contract: Address,
        token_id: u256,
        starting_price: u256,
    ) -> u256 {
        let caller = get_caller_address();
        assert_valid_nft(nft_contract, token_id);
        assert(starting_price > 0, 'starting price must be greater than 0');

        let auction_id = get_new_auction_id();
        let end_time = get_block_timestamp() + AUCTION_DURATION;

        let auction = Auction {
            seller: caller,
            nft_contract,
            token_id,
            starting_price,
            current_bidder: None,
            current_bid: starting_price,
            start_time: get_block_timestamp(),
            end_time,
            finalized: false,
        };

        Storage::auctions.write(auction_id, auction);
        AuctionCreated(auction_id);

        auction_id
    }

    // Place a bid on an auction
    #[external]
    fn placeBid(auction_id: u256) {
        let caller = get_caller_address();
        let mut auction = get_auction(auction_id);
        assert_auction_not_finalized(&auction);
        assert_bid_valid(&auction);

        let bid_amount = u256 { low: msg.value, high: 0 };
        assert(bid_amount > auction.current_bid, 'bid amount too low');

        // Refund the previous bidder
        if let Some(previous_bidder) = auction.current_bidder {
            previous_bidder.transfer(auction.current_bid.low);
        }

        // Update auction state
        auction.current_bidder = Some(caller);
        auction.current_bid = bid_amount;
        Storage::auctions.write(auction_id, auction);

        BidPlaced(auction_id, caller, bid_amount);
    }

    // Finalize an auction
    #[external]
    fn finalizeAuction(auction_id: u256) {
        let caller = get_caller_address();
        let mut auction = get_auction(auction_id);
        assert_auction_not_finalized(&auction);
        assert(auction.end_time <= get_block_timestamp(), 'auction not ended');
        assert(caller == auction.seller, 'only seller can finalize');

        // Transfer the NFT to the highest bidder
        if let Some(winner) = auction.current_bidder {
            // Assuming the NFT contract has a transferToken function
            NFT::transferToken(auction.seller, winner, auction.token_id);
            auction.finalized = true;
            Storage::auctions.write(auction_id, auction);

            AuctionFinalized(auction_id, auction.seller, winner, auction.current_bid);
        }
    }

    // View functions

    // Get auction details
    #[view]
    fn getAuctionDetails(auction_id: u256) -> Auction {
        get_auction(auction_id)
    }

    // Internal functions

    // Ensure that the NFT contract and token ID are valid
    fn assert_valid_nft(nft_contract: Address, token_id: u256) {
        assert(NFT::getOwner(token_id) == nft_contract, 'invalid NFT');
    }

    // Ensure that the auction has not been finalized
    fn assert_auction_not_finalized(auction: &Auction) {
        assert(!auction.finalized, 'auction already finalized');
    }

    // Ensure that the bid is valid
    fn assert_bid_valid(auction: &Auction) {
        assert(get_block_timestamp() >= auction.start_time, 'auction not started');
        assert(get_block_timestamp() <= auction.end_time, 'auction ended');
    }

    // Get a new unique auction ID
    fn get_new_auction_id() -> u256 {
        Storage::auctions.len().try_into().unwrap()
    }

    // Get auction details by ID
    fn get_auction(auction_id: u256) -> Auction {
        Storage::auctions.read(auction_id).unwrap_or_else(|| {
            panic!("Auction with ID {} does not exist", auction_id.low);
        })
    }
}
