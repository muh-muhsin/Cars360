# Cars360 Token Staking System

## Overview

The Cars360 Token Staking System is a comprehensive DeFi feature that allows users to stake STX tokens to earn rewards and gain premium platform benefits. This system creates economic incentives for long-term platform engagement and provides a foundation for future governance features.

## Features

### 🔒 **Multiple Staking Pools**
- **30-Day Pool**: 5% APY, 10% early withdrawal penalty
- **90-Day Pool**: 8% APY, 15% early withdrawal penalty  
- **180-Day Pool**: 12% APY, 20% early withdrawal penalty
- **365-Day Pool**: 18% APY, 25% early withdrawal penalty

### 💰 **Reward System**
- **APY-based rewards** calculated per block
- **Compound staking** to reinvest rewards automatically
- **Reward pool** funded by platform fees and early withdrawal penalties
- **Real-time reward calculation** based on staking duration

### 🎯 **Premium Benefits**
- **Fee discounts** on marketplace transactions based on staking tier:
  - 100+ STX: 10% discount
  - 1,000+ STX: 20% discount  
  - 5,000+ STX: 30% discount
  - 10,000+ STX: 50% discount
- **Premium upload permissions** for dataset providers
- **Governance weight** for future voting features

### ⚡ **Flexible Operations**
- **Early withdrawal** with penalty (funds go to reward pool)
- **Reward claiming** without unstaking
- **Stake compounding** to maximize returns
- **Multiple active stakes** per user

## Smart Contract Architecture

### Core Contract: `staking-pool.clar`

#### Key Data Structures

```clarity
;; Staking pools with different parameters
(define-map staking-pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    lock-duration: uint,
    apy-rate: uint,
    penalty-rate: uint,
    active: bool,
    total-staked: uint,
    total-stakers: uint
  }
)

;; Individual user stakes
(define-map user-stakes
  { stake-id: uint }
  {
    staker: principal,
    pool-id: uint,
    amount: uint,
    start-block: uint,
    end-block: uint,
    rewards-claimed: uint,
    active: bool
  }
)

;; User statistics and governance weight
(define-map staker-stats
  { staker: principal }
  {
    total-staked: uint,
    total-rewards: uint,
    active-stakes: uint,
    governance-weight: uint
  }
)
```

#### Core Functions

**Staking Operations:**
- `stake-tokens(amount, pool-id)` - Stake STX in a specific pool
- `unstake-tokens(stake-id)` - Withdraw stake (with penalties if early)
- `claim-rewards(stake-id)` - Claim accumulated rewards
- `compound-stake(stake-id)` - Reinvest rewards into stake

**Read-Only Functions:**
- `calculate-rewards(stake-id)` - Calculate current rewards
- `calculate-early-withdrawal-penalty(stake-id)` - Calculate penalty amount
- `get-staking-discount(staker)` - Get marketplace fee discount percentage
- `is-premium-staker(staker)` - Check premium status

**Admin Functions:**
- `add-rewards-to-pool(amount)` - Add STX to reward pool
- `update-pool-status(pool-id, active)` - Enable/disable pools
- `emergency-withdraw(amount)` - Emergency fund recovery

## Integration with Existing Contracts

### Marketplace Integration

The marketplace contract has been enhanced to provide fee discounts for stakers:

```clarity
(define-read-only (calculate-fees-with-staking-discount (price uint) (buyer principal))
  (let
    (
      (base-platform-fee-percentage (contract-call? .dataset-registry get-platform-fee-percentage))
      (staking-discount (contract-call? .staking-pool get-staking-discount buyer))
      (discounted-fee-percentage (- base-platform-fee-percentage (/ (* base-platform-fee-percentage staking-discount) u100)))
      (platform-fee (/ (* price discounted-fee-percentage) u100))
      (seller-amount (- price platform-fee))
    )
    {
      platform-fee: platform-fee,
      seller-amount: seller-amount,
      total-price: price,
      discount-applied: staking-discount,
      savings: (- (/ (* price base-platform-fee-percentage) u100) platform-fee)
    }
  )
)
```

### Access Control Integration

Premium stakers gain additional permissions:

```clarity
(define-read-only (can-upload-dataset (user principal))
  (match (get-user-profile user)
    profile (and (not (get banned profile)) 
                 (or (>= (get role profile) ROLE_VERIFIED_SELLER)
                     (get-user-permission user "upload-dataset")
                     (contract-call? .staking-pool is-premium-staker user)))
    false
  )
)
```

## Usage Examples

### Staking Tokens

```clarity
;; Stake 1000 STX in 90-day pool
(contract-call? .staking-pool stake-tokens u1000000000 u2)
```

### Claiming Rewards

```clarity
;; Claim rewards for stake ID 1
(contract-call? .staking-pool claim-rewards u1)
```

### Compounding Stake

```clarity
;; Reinvest rewards into stake
(contract-call? .staking-pool compound-stake u1)
```

### Early Withdrawal

```clarity
;; Unstake early (with penalty)
(contract-call? .staking-pool unstake-tokens u1)
```

## Economic Model

### Reward Distribution
- **Platform fees**: 20% of marketplace fees go to reward pool
- **Early withdrawal penalties**: 100% go to reward pool
- **Admin contributions**: Additional STX can be added by admin

### Staking Tiers and Benefits

| Staked Amount | Fee Discount | Premium Status | Upload Rights |
|---------------|--------------|----------------|---------------|
| 0-99 STX      | 0%          | No             | No            |
| 100-999 STX   | 10%         | No             | No            |
| 1,000-4,999 STX | 20%       | Yes            | Yes           |
| 5,000-9,999 STX | 30%       | Yes            | Yes           |
| 10,000+ STX   | 50%         | Yes            | Yes           |

### APY Calculation

Rewards are calculated using the formula:
```
rewards = (staked_amount * apy_rate * blocks_staked) / (10000 * annual_blocks)
```

Where:
- `apy_rate` is in basis points (e.g., 500 = 5%)
- `annual_blocks` = 365 * 144 (assuming 10-minute blocks)
- `blocks_staked` = current_block - start_block

## Security Considerations

### Access Control
- Only contract owner can add rewards and manage pools
- Users can only operate on their own stakes
- Emergency withdrawal function for admin recovery

### Economic Security
- Early withdrawal penalties discourage gaming
- Reward pool balance checked before distributions
- Overflow protection in calculations

### Time-based Security
- Lock periods enforced at block level
- No manipulation of time-based calculations
- Consistent block-based reward accrual

## Testing

Comprehensive test suite covers:
- **Basic staking operations** (stake, unstake, claim)
- **Reward calculations** and compounding
- **Early withdrawal penalties**
- **Fee discount integration**
- **Premium permission integration**
- **Admin functions** and access control
- **Edge cases** and error conditions

## Future Enhancements

### Governance Integration
The staking system provides `governance-weight` that can be used for:
- **Voting on platform parameters** (fees, pool rates)
- **Dataset quality standards** and verification
- **Platform feature proposals**
- **Treasury management decisions**

### Advanced Features
- **Liquid staking tokens** (stSTX) for tradeable stakes
- **Delegation mechanisms** for governance participation
- **Cross-chain staking** integration
- **NFT rewards** for long-term stakers

## Deployment

The staking system requires:
1. **Deploy staking-pool.clar** contract
2. **Update marketplace.clar** with staking integration
3. **Update access-control.clar** with premium permissions
4. **Initialize reward pool** with initial STX
5. **Configure pool parameters** as needed

## Monitoring

Key metrics to track:
- **Total value locked** (TVL) across all pools
- **Reward distribution rate** and pool sustainability
- **User engagement** and staking behavior
- **Fee discount utilization** and revenue impact
- **Premium feature adoption** rates
