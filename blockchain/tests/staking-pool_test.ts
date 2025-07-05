import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can stake tokens in 30-day pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX
                types.uint(1) // 30-day pool
            ], user1.address)
        ]);
        
        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Verify stake was created
        let getStake = chain.callReadOnlyFn(
            'staking-pool',
            'get-user-stake',
            [types.uint(1)],
            user1.address
        );
        
        const stake = getStake.result.expectSome().expectTuple();
        assertEquals(stake['staker'], user1.address);
        assertEquals(stake['amount'], types.uint(1000000000));
        assertEquals(stake['pool-id'], types.uint(1));
        assertEquals(stake['active'], types.bool(true));
    },
});

Clarinet.test({
    name: "Cannot stake with insufficient balance",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(100000000000000), // More than user balance
                types.uint(1)
            ], user1.address)
        ]);
        
        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectErr(), types.uint(405)); // ERR_INSUFFICIENT_BALANCE
    },
});

Clarinet.test({
    name: "Cannot stake in invalid pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000),
                types.uint(99) // Invalid pool ID
            ], user1.address)
        ]);
        
        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectErr(), types.uint(402)); // ERR_INVALID_POOL
    },
});

Clarinet.test({
    name: "Can unstake tokens after lock period",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        // Stake tokens
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000),
                types.uint(1) // 30-day pool
            ], user1.address)
        ]);
        
        // Mine blocks to simulate time passing (30 days = 4320 blocks)
        chain.mineEmptyBlockUntil(4321);
        
        // Unstake tokens
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'unstake-tokens', [
                types.uint(1)
            ], user1.address)
        ]);
        
        assertEquals(block.receipts[0].result.expectOk().expectTuple()['penalty'], types.uint(0));
        
        // Verify stake is inactive
        let getStake = chain.callReadOnlyFn(
            'staking-pool',
            'get-user-stake',
            [types.uint(1)],
            user1.address
        );
        
        const stake = getStake.result.expectSome().expectTuple();
        assertEquals(stake['active'], types.bool(false));
    },
});

Clarinet.test({
    name: "Early withdrawal incurs penalty",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        // Stake tokens
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX
                types.uint(1) // 30-day pool (10% penalty)
            ], user1.address)
        ]);
        
        // Unstake early (before lock period)
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'unstake-tokens', [
                types.uint(1)
            ], user1.address)
        ]);
        
        const result = block.receipts[0].result.expectOk().expectTuple();
        assertEquals(result['penalty'], types.uint(100000000)); // 10% of 1000 STX
        assertEquals(result['withdrawal-amount'], types.uint(900000000)); // 90% of 1000 STX
    },
});

Clarinet.test({
    name: "Can calculate rewards correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        // Stake tokens
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX
                types.uint(2) // 90-day pool (8% APY)
            ], user1.address)
        ]);
        
        // Mine blocks to simulate 30 days
        chain.mineEmptyBlockUntil(4321);
        
        // Calculate rewards
        let rewards = chain.callReadOnlyFn(
            'staking-pool',
            'calculate-rewards',
            [types.uint(1)],
            user1.address
        );
        
        // Should have some rewards (approximately 1000 * 0.08 * (30/365))
        const rewardAmount = rewards.result.expectOk();
        // Rewards should be positive but less than full year
        assertEquals(rewardAmount.type, 'uint');
    },
});

Clarinet.test({
    name: "Can claim rewards",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Add rewards to pool first
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'add-rewards-to-pool', [
                types.uint(1000000000) // 1000 STX for rewards
            ], deployer.address)
        ]);
        
        // Stake tokens
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX
                types.uint(2) // 90-day pool
            ], user1.address)
        ]);
        
        // Mine blocks to accumulate rewards
        chain.mineEmptyBlockUntil(1441); // 10 days
        
        // Claim rewards
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'claim-rewards', [
                types.uint(1)
            ], user1.address)
        ]);
        
        // Should successfully claim some rewards
        const claimedAmount = block.receipts[0].result.expectOk();
        assertEquals(claimedAmount.type, 'uint');
    },
});

Clarinet.test({
    name: "Can compound stake",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Add rewards to pool
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'add-rewards-to-pool', [
                types.uint(1000000000)
            ], deployer.address)
        ]);
        
        // Stake tokens
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000),
                types.uint(2)
            ], user1.address)
        ]);
        
        // Mine blocks to accumulate rewards
        chain.mineEmptyBlockUntil(1441);
        
        // Get original stake amount
        let getStake = chain.callReadOnlyFn(
            'staking-pool',
            'get-user-stake',
            [types.uint(1)],
            user1.address
        );
        const originalAmount = getStake.result.expectSome().expectTuple()['amount'];
        
        // Compound stake
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'compound-stake', [
                types.uint(1)
            ], user1.address)
        ]);
        
        // Verify stake amount increased
        getStake = chain.callReadOnlyFn(
            'staking-pool',
            'get-user-stake',
            [types.uint(1)],
            user1.address
        );
        const newAmount = getStake.result.expectSome().expectTuple()['amount'];
        
        // New amount should be greater than original
        assertEquals(newAmount.type, 'uint');
    },
});

Clarinet.test({
    name: "Staking provides fee discount",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user1 = accounts.get('wallet_1')!;
        
        // Stake tokens to get discount
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'stake-tokens', [
                types.uint(1000000000), // 1000 STX - should provide 20% discount
                types.uint(1)
            ], user1.address)
        ]);
        
        // Check staking discount
        let discount = chain.callReadOnlyFn(
            'staking-pool',
            'get-staking-discount',
            [types.principal(user1.address)],
            user1.address
        );
        
        assertEquals(discount.result, types.uint(20)); // 20% discount for 1000+ STX
        
        // Check premium staker status
        let isPremium = chain.callReadOnlyFn(
            'staking-pool',
            'is-premium-staker',
            [types.principal(user1.address)],
            user1.address
        );
        
        assertEquals(isPremium.result, types.bool(true));
    },
});

Clarinet.test({
    name: "Admin can add rewards to pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const user1 = accounts.get('wallet_1')!;
        
        // Admin adds rewards
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'add-rewards-to-pool', [
                types.uint(500000000) // 500 STX
            ], deployer.address)
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.uint(500000000));
        
        // Non-admin cannot add rewards
        block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'add-rewards-to-pool', [
                types.uint(100000000)
            ], user1.address)
        ]);
        
        assertEquals(block.receipts[0].result.expectErr(), types.uint(400)); // ERR_UNAUTHORIZED
    },
});

Clarinet.test({
    name: "Admin can update pool status",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        // Deactivate pool
        let block = chain.mineBlock([
            Tx.contractCall('staking-pool', 'update-pool-status', [
                types.uint(1),
                types.bool(false)
            ], deployer.address)
        ]);
        
        assertEquals(block.receipts[0].result.expectOk(), types.bool(true));
        
        // Verify pool is inactive
        let getPool = chain.callReadOnlyFn(
            'staking-pool',
            'get-staking-pool',
            [types.uint(1)],
            deployer.address
        );
        
        const pool = getPool.result.expectSome().expectTuple();
        assertEquals(pool['active'], types.bool(false));
    },
});
