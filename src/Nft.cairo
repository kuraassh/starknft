#[contract]
mod NFT {

    // Importing necessary modules and traits
    use array::ArrayTrait;
    use option::OptionTrait;
    use traits::Into;
    use traits::TryInto;
    use starknet::contract_address;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use zeroable::Zeroable;

    type Address = ContractAddress;

    // ERC 165 interface codes
    const INTERFACE_ERC165: u32 = 0x01ffc9a7_u32;
    const INTERFACE_ERC721: u32 = 0x80ac58cd_u32;
    const INTERFACE_ERC721_METADATA: u32 = 0x5b5e139f_u32;
    const INTERFACE_ERC721_RECEIVER: u32 = 0x150b7a02_u32;

    // ERC721 Token Receiver trait
    #[abi]
    trait IERC721TokenReceiver {
        fn on_erc721_received(operator: Address, from: Address, token_id: u256, data: Array<u8>) -> u32;
    }

    // ERC165 trait
    #[abi]
    trait IERC165 {
        fn supports_interface(interface_id: u32) -> bool;
    }

    // Events
    #[event]
    fn TokenTransferred(from: Address, to: Address, token_id: u256) {}

    #[event]
    fn ApprovalChanged(owner: Address, approved: Address, token_id: u256) {}

    #[event]
    fn ApprovalForAllChanged(owner: Address, operator: Address, approved: bool) {}

    // Storage structure
    struct Storage {
        admin: Address,
        token_id_count: u256,
        balances: LegacyMap<Address, u256>,
        owners: LegacyMap<u256, Address>,
        token_approvals: LegacyMap<u256, Address>,
        operator_approvals: LegacyMap<(Address, Address), bool>,
    }

    // Constructor
    #[constructor]
    fn initialize() {
        admin::write(get_caller_address())
    }

    // External functions

    // Mint a new token
    fn mint(to: Address) {
        assert_admin();
        assert(to.is_non_zero(), 'minting to zero');

        let one = u256 { low: 1, high: 0 };
        let token_id = token_id_count::read() + one;

        token_id_count::write(token_id);
        balances::write(to, balances::read(to) + one);
        owners::write(token_id, to);

        TokenTransferred(Zeroable::zero(), to, token_id);
    }

    // ERC721 Metadata functions

    // Get the name of the token
    #[view]
    fn getTokenName() -> felt252 {
        'Starknet'
    }

    // Get the symbol of the token
    #[view]
    fn getTokenSymbol() -> felt252 {
        'Starknet'
    }

    // Get the URI of the token
    #[view]
    fn getTokenURI(token_id: u256) -> Array<felt252> {
        assert_valid_token(token_id);
        let mut uri = ArrayTrait::new();
        uri.append('https://www.starknet.io/assets/');
        uri.append('cairo_logo_banner.png');
        uri
    }   

    // ERC721 functions

    // Get the balance of a token owner
    #[view]
    fn getBalance(owner: Address) -> u256 {
        assert_valid_address(owner);
        balances::read(owner)
    }

    // Get the owner of a token
    #[view]
    fn getOwner(token_id: u256) -> Address {
        let owner = owners::read(token_id);
        assert_valid_address(owner);
        owner
    }

    // Get the approved address for a token
    #[view]
    fn getApproved(token_id: u256) -> Address {
        assert_valid_token(token_id);
        token_approvals::read(token_id)
    }

    // Check if an operator is approved for all tokens of an owner
    #[view]
    fn isApprovedForAll(owner: Address, operator: Address) -> bool {
        operator_approvals::read((owner, operator))
    }

    // Transfer a token safely
    #[external]
    fn safeTransferFrom(from: Address, to: Address, token_id: u256, data: Array<u8>) {
        let can_receive_token = IERC165Dispatcher { contract_address: to }.supports_interface(INTERFACE_ERC721_RECEIVER);
        assert(can_receive_token, 'not supported by receiver');

        transfer(from, to, token_id);

        let confirmation = IERC721TokenReceiverDispatcher { contract_address: to }.on_erc721_received(from, to, token_id, data);
        assert(confirmation == INTERFACE_ERC721_RECEIVER, 'incompatible receiver');
    }

    // Transfer a token
    #[external]
    fn transferToken(from: Address, to: Address, token_id: u256) {
        transfer(from, to, token_id);
    }

    // Approve an address for a token
    #[external]
    fn approveAddress(approved: Address, token_id: u256) {
        let owner = owners::read(token_id);
        assert(owner != approved, 'approval to owner');

        let caller = get_caller_address();
        assert(
            caller == owner | operator_approvals::read((owner, caller)), 
            'not approved'
        );

        token_approvals::write(token_id, approved);
        ApprovalChanged(owner, approved, token_id);
    }

    // Set approval for all tokens for an operator
    #[external]
    fn setApprovalForAll(operator: Address, approval: bool) {
        let owner = get_caller_address();
        assert(owner != operator, 'approval to self');
        operator_approvals::write((owner, operator), approval);
        ApprovalForAllChanged(owner, operator, approval);
    }

    // ERC165 functions

    // Check if the contract supports the given interface
    #[view]
    fn supportsInterface(interface_id: u32) -> bool {
        interface_id == INTERFACE_ERC165 |
        interface_id == INTERFACE_ERC721 |
        interface_id == INTERFACE_ERC721_METADATA
    }

    // Internal functions

    // Ensure that the caller is the admin
    fn assert_admin() {
        assert(get_caller_address() == admin::read(), 'caller not admin')
    }

    // Ensure that the operator is approved or the owner of the token
    fn assert_approved_or_owner(operator: Address, token_id: u256) {
        let owner = owners::read(token_id);
        let approved = getApproved(token_id);
        assert(
            operator == owner | operator == approved | isApprovedForAll(owner, operator),
            'operation not allowed'
        );
    }

    // Ensure that the address is valid (non-zero)
    fn assert_valid_address(address: Address) {
        assert(address.is_non_zero(), 'invalid address');
    }

    // Ensure that the token ID is valid
    fn assert_valid_token(token_id: u256) {
        assert(owners::read(token_id).is_non_zero(), 'invalid token ID')
    }

    // Transfer a token from one address to another
    fn transfer(from: Address, to: Address, token_id: u256) {
        assert_approved_or_owner(get_caller_address(), token_id);
        assert(owners::read(token_id) == from, 'source not owner');
        assert(to.is_non_zero(), 'transferring to zero');
        assert_valid_token(token_id);

        // Reset approvals
        token_approvals::write(token_id, Zeroable::zero());

        // Update balances
        let one = u256 { low: 1, high: 0 };
        let owner_balance = balances::read(from);
        balances::write(from, owner_balance - one);
        let receiver_balance = balances::read(to);
        balances::write(to, receiver_balance + one);

        // Update ownership
        owners::write(token_id, to);
        TokenTransferred(from, to, token_id);
    }
    // Burn a token
    #[external]
    fn burnToken(token_id: u256) {
        let owner = owners::read(token_id);
        assert_approved_or_owner(get_caller_address(), token_id);
        assert(owner == get_caller_address(), 'caller not owner');

        // Reset approvals
        token_approvals::write(token_id, Zeroable::zero());

        // Update balances
        let one = u256 { low: 1, high: 0 };
        let owner_balance = balances::read(owner);
        balances::write(owner, owner_balance - one);

        // Update ownership
        owners::write(token_id, Zeroable::zero());
        TokenTransferred(owner, Zeroable::zero(), token_id);
    }

    // Batch transfer tokens
    #[external]
    fn batchTransfer(tokens: Array<(Address, u256)>) {
        let caller = get_caller_address();
        for (to, token_id) in tokens.iter() {
            assert(to.is_non_zero(), 'transferring to zero');
            assert_valid_token(*token_id);
            assert_approved_or_owner(caller, *token_id);

            transfer(caller, *to, *token_id);
        }
    }

    // Update token URI
    #[external]
    fn updateTokenURI(token_id: u256, new_uri: Array<felt252>) {
        assert_admin();
        assert_valid_token(token_id);

        // Update URI
        setTokenURI(token_id, new_uri);
    }
}
