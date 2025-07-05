# Cars360 Staking System Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Cars360 Token Staking System to the Stacks blockchain. The deployment includes the core staking contract, integration updates, and optional governance preview.

## Prerequisites

### Development Environment
- **Clarinet CLI** installed and configured
- **Stacks CLI** for mainnet/testnet deployment
- **Node.js 18+** for frontend integration
- **Git** for version control

### Network Requirements
- **Testnet STX** for testing deployment
- **Mainnet STX** for production deployment
- **Wallet setup** with sufficient funds for deployment fees

### Contract Dependencies
Ensure these contracts are already deployed:
- `dataset-registry.clar`
- `marketplace.clar` 
- `access-control.clar`

## Deployment Steps

### Phase 1: Local Testing

#### 1. Setup Development Environment
```bash
# Clone the repository
git clone https://github.com/muhsinmuhammad/Cars360.git
cd Cars360

# Switch to staking feature branch
git checkout feature/token-staking-system

# Navigate to blockchain directory
cd blockchain
```

#### 2. Validate Contract Syntax
```bash
# Check all contracts for syntax errors
clarinet check

# Run comprehensive test suite
clarinet test --coverage
```

#### 3. Local Integration Testing
```bash
# Start local devnet
clarinet integrate

# Test contract interactions in console
clarinet console
```

### Phase 2: Testnet Deployment

#### 1. Configure Testnet Environment
```bash
# Update Clarinet.toml for testnet
[testnet]
stacks_node_rpc_address = "https://api.testnet.hiro.so"
bitcoin_node_rpc_address = "https://blockstream.info/testnet/api"
```

#### 2. Deploy Contracts to Testnet
```bash
# Deploy staking pool contract
clarinet deployments apply --testnet

# Verify deployment
stx balance <your-address> --testnet
```

#### 3. Initialize Staking System
```clarity
;; Add initial rewards to pool (10,000 STX)
(contract-call? .staking-pool add-rewards-to-pool u10000000000)

;; Verify pool initialization
(contract-call? .staking-pool get-staking-pool u1)
```

### Phase 3: Integration Updates

#### 1. Update Existing Contracts
Deploy updated versions of:
- `marketplace.clar` (with staking discount integration)
- `access-control.clar` (with premium staker permissions)

#### 2. Verify Cross-Contract Integration
```clarity
;; Test staking discount calculation
(contract-call? .marketplace calculate-fees-with-staking-discount u1000000 'ST1EXAMPLE...)

;; Test premium staker permissions
(contract-call? .access-control can-upload-dataset 'ST1EXAMPLE...)
```

### Phase 4: Frontend Integration

#### 1. Update Frontend Dependencies
```bash
cd ../frontend

# Install Stacks.js dependencies
npm install @stacks/transactions @stacks/network @stacks/connect

# Add staking components
npm run build
```

#### 2. Configure Contract Addresses
```typescript
// Update contract addresses in environment
NEXT_PUBLIC_STAKING_CONTRACT_ADDRESS=ST1...
NEXT_PUBLIC_MARKETPLACE_CONTRACT_ADDRESS=ST1...
NEXT_PUBLIC_ACCESS_CONTROL_CONTRACT_ADDRESS=ST1...
```

### Phase 5: Production Deployment

#### 1. Mainnet Preparation
```bash
# Generate production wallet
stx make_keychain

# Fund deployment wallet with sufficient STX
# Minimum: 1000 STX for deployment + initial rewards
```

#### 2. Deploy to Mainnet
```bash
# Deploy contracts
clarinet deployments apply --mainnet

# Initialize with production parameters
# Add substantial reward pool (50,000+ STX recommended)
```

#### 3. Post-Deployment Configuration
```clarity
;; Set production parameters
(contract-call? .staking-pool add-rewards-to-pool u50000000000)

;; Configure pool rates if needed
(contract-call? .staking-pool update-pool-status u1 true)
```

## Configuration Parameters

### Staking Pool Settings
```clarity
;; Default APY rates (in basis points)
30-day pool:  500  (5% APY)
90-day pool:  800  (8% APY)
180-day pool: 1200 (12% APY)
365-day pool: 1800 (18% APY)

;; Early withdrawal penalties
30-day pool:  1000 (10%)
90-day pool:  1500 (15%)
180-day pool: 2000 (20%)
365-day pool: 2500 (25%)
```

### Fee Discount Tiers
```clarity
;; Staking amount -> Discount percentage
100+ STX:    10% discount
1,000+ STX:  20% discount
5,000+ STX:  30% discount
10,000+ STX: 50% discount
```

## Security Checklist

### Pre-Deployment
- [ ] All contracts pass syntax validation
- [ ] Comprehensive test suite passes (100% coverage)
- [ ] Security audit completed (recommended for mainnet)
- [ ] Access control permissions verified
- [ ] Emergency functions tested

### Post-Deployment
- [ ] Contract addresses verified and documented
- [ ] Initial reward pool funded adequately
- [ ] Cross-contract integrations working correctly
- [ ] Frontend integration tested end-to-end
- [ ] Monitoring and alerting configured

## Monitoring and Maintenance

### Key Metrics to Track
```typescript
// Staking metrics
- Total Value Locked (TVL)
- Active stakers count
- Reward distribution rate
- Pool utilization rates

// Integration metrics  
- Fee discount usage
- Premium feature adoption
- Cross-contract call success rates
```

### Regular Maintenance Tasks
```clarity
;; Weekly: Update governance weight
(contract-call? .governance-preview update-governance-weight)

;; Monthly: Add rewards to pool (as needed)
(contract-call? .staking-pool add-rewards-to-pool <amount>)

;; Quarterly: Review and adjust pool parameters
```

## Troubleshooting

### Common Issues

#### Contract Deployment Fails
```bash
# Check account balance
stx balance <address> --testnet

# Verify contract syntax
clarinet check

# Check for naming conflicts
clarinet deployments generate --testnet
```

#### Cross-Contract Calls Fail
```clarity
;; Verify contract addresses
(contract-call? .staking-pool get-total-staked)

;; Check contract deployment status
(get-contract-info? .staking-pool)
```

#### Frontend Integration Issues
```typescript
// Verify network configuration
const network = new StacksTestnet(); // or StacksMainnet()

// Check contract address format
const contractAddress = 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM';
```

## Rollback Procedures

### Emergency Rollback
```clarity
;; Disable new staking (admin only)
(contract-call? .staking-pool update-pool-status u1 false)
(contract-call? .staking-pool update-pool-status u2 false)
(contract-call? .staking-pool update-pool-status u3 false)
(contract-call? .staking-pool update-pool-status u4 false)

;; Emergency fund recovery (if needed)
(contract-call? .staking-pool emergency-withdraw <amount>)
```

### Gradual Migration
```clarity
;; Reduce APY rates to discourage new staking
;; Allow existing stakes to complete naturally
;; Deploy updated contracts with fixes
```

## Success Criteria

### Technical Metrics
- [ ] All contracts deployed successfully
- [ ] Cross-contract integration working
- [ ] Frontend integration complete
- [ ] Zero critical security issues

### Business Metrics
- [ ] Initial staking adoption (target: 10+ users in first week)
- [ ] TVL growth (target: 10,000+ STX in first month)
- [ ] Fee discount utilization (target: 20% of transactions)
- [ ] Premium feature adoption (target: 5+ premium stakers)

## Support and Resources

### Documentation
- [Stacking System Overview](./staking-system.md)
- [Smart Contracts Documentation](./smart-contracts.md)
- [API Reference](./api-reference.md)

### Community
- **GitHub Issues**: Report bugs and feature requests
- **Discord**: Real-time community support
- **Documentation**: Comprehensive guides and examples

### Emergency Contacts
- **Lead Developer**: muhammad.m1601550@st.futminna.edu.ng
- **GitHub**: @muhsinmuhammad
- **Twitter**: @DataPeritus

---

**Note**: This deployment guide assumes familiarity with Stacks blockchain development. For production deployments, consider engaging a security audit firm and implementing gradual rollout procedures.
