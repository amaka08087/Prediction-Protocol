# Prediction Market Smart Contract

A decentralized prediction market implementation built on Stacks blockchain, allowing users to create markets, stake STX tokens on outcomes, and earn rewards for correct predictions.

## Features

- Create prediction markets with multiple options
- Stake STX tokens on market outcomes
- Automatic market resolution system
- Partial stake withdrawal before market resolution
- Platform fee system (2%)
- Market cancellation functionality
- Claim rewards or refunds system

## Contract Details

### Constants

- Minimum stake amount: 100,000 microSTX
- Platform fee: 2%
- Administrator: Contract deployer

### Main Functions

#### Creating Markets

```clarity
(create-prediction-market 
    (market-question (string-ascii 256))
    (market-description (string-ascii 1024))
    (market-end-block uint)
    (market-options-list (list 20 (string-ascii 64))))
```

Creates a new prediction market with specified parameters. Requires at least two options.

#### Placing Stakes

```clarity
(place-market-stake (market-id uint) (selected-option-index uint) (stake-amount uint))
```

Places a stake on a specific market option. Minimum stake amount applies.

#### Market Resolution

```clarity
(resolve-prediction-market (market-id uint) (winning-option-index uint))
```

Resolves a market by setting the winning option. Only callable by administrator after market end block.

#### Automatic Resolution

```clarity
(auto-resolve-markets (max-markets-to-process uint))
```

Automatically resolves expired markets based on highest stake amounts.

#### Withdrawing Stakes

```clarity
(withdraw-partial-stake (market-id uint) (option-index uint) (withdrawal-amount uint))
```

Allows partial withdrawal of stakes before market resolution.

#### Claiming Rewards

```clarity
(claim-rewards-or-refund (market-id uint))
```

Claims winnings for correct predictions or refunds for cancelled markets.

### Read-Only Functions

- `get-market-details`: Returns market information
- `get-market-options-list`: Returns available options for a market
- `get-participant-stake-details`: Returns stake information for a participant
- `get-contract-stx-balance`: Returns current contract balance

## Error Codes

- `ERROR_UNAUTHORIZED (u100)`: Unauthorized access attempt
- `ERROR_MARKET_ALREADY_RESOLVED (u101)`: Market already resolved
- `ERROR_MARKET_NOT_RESOLVED (u102)`: Market not yet resolved
- `ERROR_INVALID_STAKE_AMOUNT (u103)`: Invalid stake amount
- `ERROR_INSUFFICIENT_BALANCE (u104)`: Insufficient balance
- `ERROR_MARKET_CANCELLED (u105)`: Market is cancelled
- `ERROR_INVALID_OPTION (u106)`: Invalid option selected

## Usage Example

1. Create a prediction market:
```clarity
(contract-call? .prediction-market create-prediction-market 
    "Will BTC price exceed $100k in 2024?"
    "Predict if Bitcoin price will reach $100,000 or higher during 2024"
    u100000
    (list "Yes" "No"))
```

2. Place a stake:
```clarity
(contract-call? .prediction-market place-market-stake 
    u0  ;; market-id
    u0  ;; option index (Yes)
    u200000)  ;; stake amount in microSTX
```

3. Claim rewards after resolution:
```clarity
(contract-call? .prediction-market claim-rewards-or-refund u0)
```

## Security Considerations

- Market resolution requires waiting for the end block
- Minimum stake amount prevents dust attacks
- Administrator controls are limited to market resolution and cancellation
- Platform fees are automatically calculated and deducted
- Stake withdrawals are only allowed before market resolution
- Contract balance is protected through proper permission checks

## Implementation Notes

- Uses Clarity's built-in asset handling for STX tokens
- Implements efficient list manipulation functions
- Includes safeguards against common attack vectors
- Provides comprehensive error handling
- Supports up to 20 options per market
- Uses data maps for efficient storage