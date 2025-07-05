# Cars360 Smart Contracts Documentation

## Overview

Cars360 uses four main smart contracts deployed on the Stacks blockchain to manage the decentralized data marketplace:

1. **Dataset Registry** - Manages dataset registration, metadata, and ownership
2. **Marketplace** - Handles STX payments and transactions
3. **Access Control** - Manages user permissions and verification
4. **Staking Pool** - Enables token staking for rewards and premium benefits

## Contract Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Dataset        │    │   Marketplace   │    │ Access Control  │
│  Registry       │◄──►│                 │◄──►│                 │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Dataset Registry Contract

### Purpose
Manages the registration, metadata, and ownership of datasets in the marketplace.

### Key Functions

#### `register-dataset`
```clarity
(define-public (register-dataset 
  (uri (string-utf8 256))
  (price uint)
  (metadata (string-utf8 512)))
```
Registers a new dataset with IPFS URI, price in microSTX, and JSON metadata.

**Parameters:**
- `uri`: IPFS URI of the dataset file
- `price`: Price in microSTX (1 STX = 1,000,000 microSTX)
- `metadata`: JSON string containing dataset information

**Returns:** Dataset ID (uint)

#### `get-dataset`
```clarity
(define-read-only (get-dataset (dataset-id uint)))
```
Retrieves dataset information by ID.

**Returns:** Dataset tuple with owner, URI, price, metadata, etc.

#### `has-access`
```clarity
(define-read-only (has-access (dataset-id uint) (buyer principal)))
```
Checks if a user has access to a specific dataset.

**Returns:** Boolean indicating access status

#### `grant-access`
```clarity
(define-public (grant-access (dataset-id uint) (buyer principal)))
```
Grants access to a dataset (called by marketplace contract after payment).

### Data Structures

#### Dataset Map
```clarity
{
  owner: principal,
  uri: (string-utf8 256),
  price: uint,
  metadata: (string-utf8 512),
  created-at: uint,
  updated-at: uint,
  total-sales: uint,
  rating: uint,
  rating-count: uint,
  active: bool
}
```

## Marketplace Contract

### Purpose
Handles STX payments, dataset purchases, and earnings distribution.

### Key Functions

#### `purchase-dataset`
```clarity
(define-public (purchase-dataset (dataset-id uint)))
```
Purchases access to a dataset using STX tokens.

**Process:**
1. Validates dataset exists and is active
2. Checks user hasn't already purchased
3. Transfers STX from buyer to seller
4. Transfers platform fee to platform wallet
5. Grants access via dataset registry
6. Records transaction

#### `withdraw-earnings`
```clarity
(define-public (withdraw-earnings))
```
Allows sellers to withdraw their accumulated earnings.

#### `get-marketplace-stats`
```clarity
(define-read-only (get-marketplace-stats))
```
Returns marketplace statistics including total volume and transactions.

### Fee Structure

- **Platform Fee:** 5% of transaction value (configurable)
- **Seller Revenue:** 95% of transaction value
- **Payment Method:** STX tokens only

## Access Control Contract

### Purpose
Manages user roles, permissions, and verification status.

### User Roles

1. **Admin (1)** - Full system access
2. **Verified Seller (2)** - Can upload datasets
3. **Premium Buyer (3)** - Enhanced marketplace features
4. **Basic User (4)** - Standard marketplace access

### Key Functions

#### `register-user`
```clarity
(define-public (register-user))
```
Registers a new user with basic role.

#### `request-verification`
```clarity
(define-public (request-verification (documents-uri (string-utf8 256))))
```
Submits verification request with supporting documents.

#### `verify-user`
```clarity
(define-public (verify-user (user principal) (approved bool)))
```
Admin function to approve/reject verification requests.

## Deployment

### Testnet Deployment

```bash
# Deploy to Stacks testnet
clarinet deploy --testnet

# Verify deployment
clarinet console
```

### Contract Addresses

- **Testnet:** `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM`
- **Mainnet:** TBD

## Integration Examples

### Frontend Integration

```typescript
import { makeContractCall, uintCV, stringUtf8CV } from '@stacks/transactions'

// Register a dataset
const registerDataset = async (uri: string, price: number, metadata: string) => {
  const txOptions = {
    contractAddress: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM',
    contractName: 'dataset-registry',
    functionName: 'register-dataset',
    functionArgs: [
      stringUtf8CV(uri),
      uintCV(price),
      stringUtf8CV(metadata)
    ],
    // ... other options
  }
  
  return await makeContractCall(txOptions)
}
```

### Backend Integration

```python
# Check dataset access via API
import requests

response = requests.get(
    f"{API_URL}/api/v1/datasets/{dataset_id}/access",
    headers={"Authorization": f"Bearer {token}"}
)
```

## Security Considerations

1. **Access Control:** Only verified users can upload datasets
2. **Payment Security:** STX transfers are atomic and reversible only by consensus
3. **Data Integrity:** IPFS content addressing ensures data immutability
4. **Rate Limiting:** API endpoints have rate limiting to prevent abuse

## Testing

### Unit Tests

```bash
# Run contract tests
clarinet test

# Run specific test
clarinet test tests/dataset-registry_test.ts
```

### Integration Tests

```bash
# Test full purchase flow
npm run test:integration
```

## Monitoring

### Events

The contracts emit events for:
- Dataset registration
- Dataset purchases
- User verification
- Access grants

### Metrics

Track these key metrics:
- Total datasets registered
- Total transaction volume
- Active users
- Platform fees collected

## Upgrades

Contracts are immutable once deployed. For upgrades:

1. Deploy new contract versions
2. Migrate data if necessary
3. Update frontend to use new contracts
4. Deprecate old contracts gracefully

## Support

For technical support or questions:
- GitHub Issues: [Cars360 Repository](https://github.com/muhsinmuhammad/Cars360)
- Email: support@cars360.ng
- Discord: [Cars360 Community](https://discord.gg/cars360)
