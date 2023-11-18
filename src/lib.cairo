fn main() -> felt252 {
    fib(16)
}

fn fib(mut n: felt252) -> felt252 {
    let mut a: felt252 = 0;
    let mut b: felt252 = 1;
    loop {
        if n == 0 {
            break a;
        }
        n = n - 1;
        let temp = b;
        b = a + b;
        a = temp;
    }
}

#[test]
fn test() {
    // Deploy the contract
    let contract = StarkNFT.deploy();

    // Get the admin address
    let admin_address = contract.admin::read();

    // Ensure the admin address is set correctly
    assert(admin_address == get_caller_address(), 'Admin address not set correctly');

    // Mint a new token to an address
    let to_address = ContractAddress { value: 0x1234 }; // Replace with a valid address
    contract.mint(to_address);

    // Check the balance of the recipient address
    let balance = contract.balance_of(to_address);
    assert(balance == 1, 'Balance of recipient not updated correctly after minting');

    // Get the owner of the minted token
    let owner = contract.owner_of(1);
    assert(owner == to_address, 'Owner of the minted token is incorrect');

    // Get the approved address for the minted token
    let approved_address = contract.get_approved(1);
    assert(approved_address == Zeroable::zero(), 'Approved address for the minted token should be zero initially');

    // Approve an address for the minted token
    let approved_address_2 = ContractAddress { value: 0x5678 }; // Replace with a valid address
    contract.approve(approved_address_2, 1);

    // Check if the approval was successful
    let new_approved_address = contract.get_approved(1);
    assert(new_approved_address == approved_address_2, 'Approval for the minted token not set correctly');

    // Set approval for all tokens for an operator
    let operator_address = ContractAddress { value: 0x9abc }; // Replace with a valid address
    contract.set_approval_for_all(operator_address, true);

    // Check if the approval for all was successful
    let is_approved_for_all = contract.is_approved_for_all(to_address, operator_address);
    assert(is_approved_for_all, 'Approval for all not set correctly');

    // Perform a safe transfer of the token
    let data = Array::new(); // Replace with appropriate data
    contract.safe_transfer_from(to_address, operator_address, 1, data);

    // Check if the token ownership and balances are updated after the transfer
    let new_owner = contract.owner_of(1);
    let new_balance = contract.balance_of(operator_address);
    assert(new_owner == operator_address, 'Token ownership not updated correctly after transfer');
    assert(new_balance == 1, 'Balance of the new owner not updated correctly after transfer');
}
