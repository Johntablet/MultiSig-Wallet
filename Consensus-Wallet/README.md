# Multi-signature Wallet Smart Contract

A robust implementation of a multi-signature wallet in Clarity for the Stacks blockchain.

## Overview

This smart contract provides a secure multi-signature wallet implementation that requires a configurable threshold of owner approvals before executing transactions. It's designed for organizations, DAOs, or groups that need shared control over funds with strong security guarantees.

## Features

- **Multi-Owner Management**: Add and remove wallet owners through multi-sig approval
- **Configurable Threshold**: Set and update the number of required confirmations
- **Transaction Management**: Create, confirm, revoke, and execute transactions
- **STX Token Support**: Securely store and transfer STX tokens
- **Safety Mechanisms**: Transaction expiration, rejection capability, and emergency functions

## Contract Structure

The contract implements the following data structures:
- Transaction records with complete metadata
- Confirmation tracking for each owner/transaction pair
- Owner registry with active status
- Configuration values for threshold and counters

## Error Codes

| Code | Description |
|------|-------------|
| 100  | Unauthorized - Caller is not an owner |
| 101  | Invalid Parameter - Input validation failed |
| 102  | Transaction Not Found |
| 103  | Transaction Already Executed |
| 104  | Transaction Already Rejected |
| 105  | Transaction Expired |
| 106  | Insufficient Funds |
| 107  | Threshold Too High - Must be <= owner count |
| 108  | Owner Already Exists |
| 109  | Owner Not Found |
| 110  | Already Confirmed by Owner |
| 111  | Not Confirmed by Owner |

## Usage

### Initialization

Initialize the contract with a list of initial owners and the confirmation threshold:

```clarity
(contract-call? .multisig-wallet initialize (list 'owner1 'owner2 'owner3) u2)
```

This example creates a wallet with 3 owners requiring 2 confirmations for execution.

### Creating a Transaction

Only owners can create transactions:

```clarity
(contract-call? .multisig-wallet submit-transaction 
  'recipient-address    ;; to: recipient of the funds
  u1000000             ;; amount: 1 STX (in microSTX)
  none                 ;; data: optional buffer for additional data
  u100000              ;; expiration: block height when tx expires
)
```

The transaction creator automatically confirms it. If threshold is 1, the transaction executes immediately.

### Confirming a Transaction

Other owners can confirm pending transactions:

```clarity
(contract-call? .multisig-wallet confirm-transaction u1)
```

When the number of confirmations reaches the threshold, the transaction executes automatically.

### Revoking a Confirmation

Owners can revoke their confirmations while a transaction is pending:

```clarity
(contract-call? .multisig-wallet revoke-confirmation u1)
```

### Rejecting a Transaction

Transactions can be rejected in two ways:
1. The creator can reject their own transactions
2. If enough owners confirm (meeting threshold), any owner can reject

```clarity
(contract-call? .multisig-wallet reject-transaction u1)
```

### Adding a New Owner

Adding an owner requires multi-signature approval:

```clarity
(contract-call? .multisig-wallet add-owner 'new-owner-address)
```

After receiving enough confirmations, execute the addition:

```clarity
(contract-call? .multisig-wallet execute-add-owner u3)
```

### Removing an Owner

Removing an owner also requires multi-signature approval:

```clarity
(contract-call? .multisig-wallet remove-owner 'existing-owner-address)
```

After receiving enough confirmations, execute the removal:

```clarity
(contract-call? .multisig-wallet execute-remove-owner u4)
```

Note: Cannot remove the last owner, and threshold must be <= (owner count - 1)

### Changing the Threshold

Changing the confirmation threshold requires multi-sig approval:

```clarity
(contract-call? .multisig-wallet change-threshold u2)
```

After receiving enough confirmations, execute the change:

```clarity
(contract-call? .multisig-wallet execute-change-threshold u5)
```

### Depositing Funds

Anyone can deposit STX to the wallet:

```clarity
(contract-call? .multisig-wallet deposit u1000000)
```

### Clearing Expired Transactions

For housekeeping, expired transactions can be cleared:

```clarity
(contract-call? .multisig-wallet clear-expired-transaction u1)
```

## Query Functions

The contract provides several read-only functions:

- `get-threshold`: Returns the current confirmation threshold
- `is-owner`: Checks if an address is an active owner
- `get-owner-count`: Returns the number of active owners
- `get-transaction`: Returns details of a specific transaction
- `transaction-exists`: Checks if a transaction ID exists
- `is-confirmed`: Checks if an owner confirmed a transaction
- `get-confirmation-count`: Returns confirmation count for a transaction
- `get-balance`: Returns the contract's STX balance

## Security Considerations

- All critical operations require threshold confirmations
- Transactions have expiration dates to prevent stale executions
- Only active owners can participate in wallet governance
- Contract verifies all inputs to prevent invalid state changes
- Clear error codes for transparent failure reporting

## Best Practices

1. Start with a moderate threshold (e.g., majority of owners)
2. Consider the risks when removing owners or changing threshold
3. Set reasonable expiration dates for transactions
4. Monitor pending transactions regularly
5. Distribute ownership across trusted, independent parties

## Technical Limitations

- Maximum 20 initial owners during initialization
- Optional transaction data limited to 256 bytes
- Transaction IDs are sequential starting from 0