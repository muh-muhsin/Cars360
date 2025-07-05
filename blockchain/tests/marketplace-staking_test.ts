import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Staking provides marketplace fee discount",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const seller = accounts.get('wallet_1')!;
        const buyer = accounts.get('wallet_2')!;
        
        // Register a dataset first
        let block = chain.mineBlock([
            Tx.contractCall('dataset-registry', 'register-dataset', [
                types.utf8("ipfs://QmTest123"),
                types.uint(1000000), // 1 STX
                types.utf8('{"title":"Test Dataset","description":"Test data"}')
            ], seller.address)
        ]);
        
        // Buyer stakes tokens to get discount
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX - should provide 20% discount
                types.uint(1) // 30-day pool
            ], buyer.address)
        ]);
        
        // Calculate fees with staking discount
        let feesWithDiscount = chain.callReadOnlyFn(
            'marketplace',
            'calculate-fees-with-staking-discount',
            [types.uint(1000000), types.principal(buyer.address)],
            buyer.address
        );
        
        const feeResult = feesWithDiscount.result.expectTuple();
        assertEquals(feeResult['discount-applied'], types.uint(20)); // 20% discount
        
        // Calculate fees without discount for comparison
        let feesWithoutDiscount = chain.callReadOnlyFn(
            'marketplace',
            'calculate-fees',
            [types.uint(1000000)],
            buyer.address
        );
        
        const normalFeeResult = feesWithoutDiscount.result.expectTuple();
        
        // Discounted fee should be less than normal fee
        const discountedFee = feeResult['platform-fee'];
        const normalFee = normalFeeResult['platform-fee'];
        
        // Verify savings
        assertEquals(feeResult['savings'], types.uint(10000)); // 20% of 5% of 1 STX
    },
});

Clarinet.test({
    name: "Purchase with staking discount applies correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const seller = accounts.get('wallet_1')!;
        const buyer = accounts.get('wallet_2')!;
        
        // Register a dataset
        let block = chain.mineBlock([
            Tx.contractCall('dataset-registry', 'register-dataset', [
                types.utf8("ipfs://QmTest123"),
                types.uint(1000000), // 1 STX
                types.utf8('{"title":"Test Dataset","description":"Test data"}')
            ], seller.address)
        ]);
        
        // Buyer stakes tokens
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(5000000000), // 5000 STX - should provide 30% discount
                types.uint(2) // 90-day pool
            ], buyer.address)
        ]);
        
        // Get seller balance before purchase
        const sellerBalanceBefore = chain.callReadOnlyFn(
            'stx-account',
            'get-stx-balance',
            [types.principal(seller.address)],
            seller.address
        );
        
        // Purchase dataset (should apply staking discount)
        block = chain.mineBlock([
            Tx.contractCall('marketplace', 'purchase-dataset', [
                types.uint(1)
            ], buyer.address)
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1)); // Transaction ID
        
        // Verify purchase receipt
        let receipt = chain.callReadOnlyFn(
            'marketplace',
            'get-purchase-receipt',
            [types.principal(buyer.address), types.uint(1)],
            buyer.address
        );
        
        const receiptData = receipt.result.expectSome().expectTuple();
        assertEquals(receiptData['amount-paid'], types.uint(1000000));
        
        // Verify transaction history includes discount
        let transaction = chain.callReadOnlyFn(
            'marketplace',
            'get-transaction',
            [types.uint(1)],
            buyer.address
        );
        
        const txData = transaction.result.expectSome().expectTuple();
        assertEquals(txData['buyer'], buyer.address);
        assertEquals(txData['seller'], seller.address);
        assertEquals(txData['amount'], types.uint(1000000));
        
        // Platform fee should be reduced due to staking discount
        // Normal 5% fee = 50,000, with 30% discount = 35,000
        assertEquals(txData['platform-fee'], types.uint(35000));
    },
});

Clarinet.test({
    name: "Non-stakers pay full fees",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const seller = accounts.get('wallet_1')!;
        const buyer = accounts.get('wallet_3')!; // Different buyer without staking
        
        // Register a dataset
        let block = chain.mineBlock([
            Tx.contractCall('dataset-registry', 'register-dataset', [
                types.utf8("ipfs://QmTest456"),
                types.uint(2000000), // 2 STX
                types.utf8('{"title":"Another Dataset","description":"More test data"}')
            ], seller.address)
        ]);
        
        // Calculate fees for non-staker
        let fees = chain.callReadOnlyFn(
            'marketplace',
            'calculate-fees-with-staking-discount',
            [types.uint(2000000), types.principal(buyer.address)],
            buyer.address
        );
        
        const feeResult = fees.result.expectTuple();
        assertEquals(feeResult['discount-applied'], types.uint(0)); // No discount
        assertEquals(feeResult['savings'], types.uint(0)); // No savings
        assertEquals(feeResult['platform-fee'], types.uint(100000)); // Full 5% fee
        
        // Purchase dataset
        block = chain.mineBlock([
            Tx.contractCall('marketplace', 'purchase-dataset', [
                types.uint(2)
            ], buyer.address)
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(2));
        
        // Verify full fee was charged
        let transaction = chain.callReadOnlyFn(
            'marketplace',
            'get-transaction',
            [types.uint(2)],
            buyer.address
        );
        
        const txData = transaction.result.expectSome().expectTuple();
        assertEquals(txData['platform-fee'], types.uint(100000)); // Full 5% fee
    },
});

Clarinet.test({
    name: "Different staking tiers provide different discounts",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const buyer1 = accounts.get('wallet_1')!; // Will stake 100 STX
        const buyer2 = accounts.get('wallet_2')!; // Will stake 1000 STX
        const buyer3 = accounts.get('wallet_3')!; // Will stake 5000 STX
        
        // Stake different amounts
        let block = chain.mineBlock([
            // 100 STX - 10% discount
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(100000000),
                types.uint(1)
            ], buyer1.address),
            
            // 1000 STX - 20% discount
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000),
                types.uint(1)
            ], buyer2.address),
            
            // 5000 STX - 30% discount
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(5000000000),
                types.uint(1)
            ], buyer3.address)
        ]);
        
        // Check discounts for each tier
        let discount1 = chain.callReadOnlyFn(
            'staking-pool',
            'get-staking-discount',
            [types.principal(buyer1.address)],
            buyer1.address
        );
        assertEquals(discount1.result, types.uint(10)); // 10% discount
        
        let discount2 = chain.callReadOnlyFn(
            'staking-pool',
            'get-staking-discount',
            [types.principal(buyer2.address)],
            buyer2.address
        );
        assertEquals(discount2.result, types.uint(20)); // 20% discount
        
        let discount3 = chain.callReadOnlyFn(
            'staking-pool',
            'get-staking-discount',
            [types.principal(buyer3.address)],
            buyer3.address
        );
        assertEquals(discount3.result, types.uint(30)); // 30% discount
        
        // Verify fee calculations reflect these discounts
        const testPrice = types.uint(1000000); // 1 STX
        
        let fees1 = chain.callReadOnlyFn(
            'marketplace',
            'calculate-fees-with-staking-discount',
            [testPrice, types.principal(buyer1.address)],
            buyer1.address
        );
        assertEquals(fees1.result.expectTuple()['platform-fee'], types.uint(45000)); // 4.5% fee
        
        let fees2 = chain.callReadOnlyFn(
            'marketplace',
            'calculate-fees-with-staking-discount',
            [testPrice, types.principal(buyer2.address)],
            buyer2.address
        );
        assertEquals(fees2.result.expectTuple()['platform-fee'], types.uint(40000)); // 4% fee
        
        let fees3 = chain.callReadOnlyFn(
            'marketplace',
            'calculate-fees-with-staking-discount',
            [testPrice, types.principal(buyer3.address)],
            buyer3.address
        );
        assertEquals(fees3.result.expectTuple()['platform-fee'], types.uint(35000)); // 3.5% fee
    },
});

Clarinet.test({
    name: "Premium stakers can upload datasets",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        // Check upload permission before staking
        let canUploadBefore = chain.callReadOnlyFn(
            'access-control',
            'can-upload-dataset',
            [types.principal(user1.address)],
            user1.address
        );
        assertEquals(canUploadBefore.result, types.bool(false)); // Cannot upload initially
        
        // Register user first
        let block = chain.mineBlock([
            Tx.contractCall('access-control', 'register-user', [], user1.address)
        ]);
        
        // Stake enough to become premium (1000+ STX)
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX
                types.uint(1)
            ], user1.address)
        ]);
        
        // Check upload permission after staking
        let canUploadAfter = chain.callReadOnlyFn(
            'access-control',
            'can-upload-dataset',
            [types.principal(user1.address)],
            user1.address
        );
        assertEquals(canUploadAfter.result, types.bool(true)); // Can upload as premium staker
        
        // Check premium benefits
        let hasPremiumBenefits = chain.callReadOnlyFn(
            'access-control',
            'has-premium-benefits',
            [types.principal(user1.address)],
            user1.address
        );
        assertEquals(hasPremiumBenefits.result, types.bool(true));
    },
});
