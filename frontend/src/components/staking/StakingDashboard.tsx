'use client';

import React, { useState, useEffect } from 'react';
import { useStacks } from '@/hooks/useStacks';
import { 
  uintCV, 
  contractPrincipalCV,
  callReadOnlyFunction,
  makeContractCall,
  broadcastTransaction
} from '@stacks/transactions';
import { StacksNetwork } from '@stacks/network';

interface StakingPool {
  id: number;
  name: string;
  lockDuration: number;
  apyRate: number;
  penaltyRate: number;
  active: boolean;
  totalStaked: number;
  totalStakers: number;
}

interface UserStake {
  stakeId: number;
  poolId: number;
  amount: number;
  startBlock: number;
  endBlock: number;
  rewardsClaimed: number;
  active: boolean;
}

interface StakerStats {
  totalStaked: number;
  totalRewards: number;
  activeStakes: number;
  governanceWeight: number;
}

const StakingDashboard: React.FC = () => {
  const { userSession, network } = useStacks();
  const [stakingPools, setStakingPools] = useState<StakingPool[]>([]);
  const [userStakes, setUserStakes] = useState<UserStake[]>([]);
  const [stakerStats, setStakerStats] = useState<StakerStats | null>(null);
  const [selectedPool, setSelectedPool] = useState<number>(1);
  const [stakeAmount, setStakeAmount] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [discount, setDiscount] = useState<number>(0);

  const contractAddress = 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM';
  const contractName = 'staking-pool';

  useEffect(() => {
    if (userSession?.isUserSignedIn()) {
      loadStakingData();
    }
  }, [userSession]);

  const loadStakingData = async () => {
    try {
      setLoading(true);
      const userAddress = userSession?.loadUserData()?.profile?.stxAddress?.mainnet;
      
      if (!userAddress) return;

      // Load staking pools
      const pools = await Promise.all([1, 2, 3, 4].map(async (poolId) => {
        const poolData = await callReadOnlyFunction({
          contractAddress,
          contractName,
          functionName: 'get-staking-pool',
          functionArgs: [uintCV(poolId)],
          network: network as StacksNetwork,
          senderAddress: userAddress,
        });
        
        if (poolData.type === 'optional' && poolData.value) {
          const pool = poolData.value as any;
          return {
            id: poolId,
            name: pool.data.name.data,
            lockDuration: parseInt(pool.data['lock-duration'].value),
            apyRate: parseInt(pool.data['apy-rate'].value),
            penaltyRate: parseInt(pool.data['penalty-rate'].value),
            active: pool.data.active.value,
            totalStaked: parseInt(pool.data['total-staked'].value),
            totalStakers: parseInt(pool.data['total-stakers'].value),
          };
        }
        return null;
      }));

      setStakingPools(pools.filter(Boolean) as StakingPool[]);

      // Load user staker stats
      const statsData = await callReadOnlyFunction({
        contractAddress,
        contractName,
        functionName: 'get-staker-stats',
        functionArgs: [contractPrincipalCV(userAddress, '')],
        network: network as StacksNetwork,
        senderAddress: userAddress,
      });

      if (statsData.type === 'tuple') {
        const stats = statsData.data as any;
        setStakerStats({
          totalStaked: parseInt(stats['total-staked'].value),
          totalRewards: parseInt(stats['total-rewards'].value),
          activeStakes: parseInt(stats['active-stakes'].value),
          governanceWeight: parseInt(stats['governance-weight'].value),
        });
      }

      // Load user discount
      const discountData = await callReadOnlyFunction({
        contractAddress,
        contractName,
        functionName: 'get-staking-discount',
        functionArgs: [contractPrincipalCV(userAddress, '')],
        network: network as StacksNetwork,
        senderAddress: userAddress,
      });

      if (discountData.type === 'uint') {
        setDiscount(parseInt(discountData.value));
      }

      // Load user stake IDs
      const stakeIdsData = await callReadOnlyFunction({
        contractAddress,
        contractName,
        functionName: 'get-user-stake-ids',
        functionArgs: [contractPrincipalCV(userAddress, '')],
        network: network as StacksNetwork,
        senderAddress: userAddress,
      });

      if (stakeIdsData.type === 'tuple') {
        const stakeIds = (stakeIdsData.data as any)['stake-ids'].list;
        
        // Load individual stakes
        const stakes = await Promise.all(stakeIds.map(async (stakeIdCV: any) => {
          const stakeId = parseInt(stakeIdCV.value);
          const stakeData = await callReadOnlyFunction({
            contractAddress,
            contractName,
            functionName: 'get-user-stake',
            functionArgs: [uintCV(stakeId)],
            network: network as StacksNetwork,
            senderAddress: userAddress,
          });

          if (stakeData.type === 'optional' && stakeData.value) {
            const stake = stakeData.value as any;
            return {
              stakeId,
              poolId: parseInt(stake.data['pool-id'].value),
              amount: parseInt(stake.data.amount.value),
              startBlock: parseInt(stake.data['start-block'].value),
              endBlock: parseInt(stake.data['end-block'].value),
              rewardsClaimed: parseInt(stake.data['rewards-claimed'].value),
              active: stake.data.active.value,
            };
          }
          return null;
        }));

        setUserStakes(stakes.filter(Boolean) as UserStake[]);
      }

    } catch (error) {
      console.error('Error loading staking data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleStake = async () => {
    if (!stakeAmount || !userSession?.isUserSignedIn()) return;

    try {
      setLoading(true);
      const amountMicroSTX = parseInt(stakeAmount) * 1000000; // Convert to microSTX

      const txOptions = {
        contractAddress,
        contractName,
        functionName: 'stake-tokens',
        functionArgs: [uintCV(amountMicroSTX), uintCV(selectedPool)],
        network: network as StacksNetwork,
        senderKey: userSession.loadUserData().appPrivateKey,
      };

      const transaction = await makeContractCall(txOptions);
      const broadcastResponse = await broadcastTransaction(transaction, network as StacksNetwork);
      
      console.log('Staking transaction broadcast:', broadcastResponse);
      
      // Refresh data after successful transaction
      setTimeout(loadStakingData, 5000);
      setStakeAmount('');
      
    } catch (error) {
      console.error('Error staking tokens:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleUnstake = async (stakeId: number) => {
    if (!userSession?.isUserSignedIn()) return;

    try {
      setLoading(true);

      const txOptions = {
        contractAddress,
        contractName,
        functionName: 'unstake-tokens',
        functionArgs: [uintCV(stakeId)],
        network: network as StacksNetwork,
        senderKey: userSession.loadUserData().appPrivateKey,
      };

      const transaction = await makeContractCall(txOptions);
      const broadcastResponse = await broadcastTransaction(transaction, network as StacksNetwork);
      
      console.log('Unstaking transaction broadcast:', broadcastResponse);
      
      // Refresh data after successful transaction
      setTimeout(loadStakingData, 5000);
      
    } catch (error) {
      console.error('Error unstaking tokens:', error);
    } finally {
      setLoading(false);
    }
  };

  const formatSTX = (microSTX: number) => {
    return (microSTX / 1000000).toLocaleString();
  };

  const formatAPY = (basisPoints: number) => {
    return (basisPoints / 100).toFixed(1);
  };

  if (!userSession?.isUserSignedIn()) {
    return (
      <div className="text-center py-8">
        <p className="text-gray-600">Please connect your wallet to access staking features.</p>
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-8">
      {/* Header */}
      <div className="text-center">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">STX Staking Dashboard</h1>
        <p className="text-gray-600">Stake your STX tokens to earn rewards and unlock premium benefits</p>
      </div>

      {/* User Stats */}
      {stakerStats && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-sm font-medium text-gray-500">Total Staked</h3>
            <p className="text-2xl font-bold text-blue-600">{formatSTX(stakerStats.totalStaked)} STX</p>
          </div>
          <div className="bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-sm font-medium text-gray-500">Total Rewards</h3>
            <p className="text-2xl font-bold text-green-600">{formatSTX(stakerStats.totalRewards)} STX</p>
          </div>
          <div className="bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-sm font-medium text-gray-500">Active Stakes</h3>
            <p className="text-2xl font-bold text-purple-600">{stakerStats.activeStakes}</p>
          </div>
          <div className="bg-white p-6 rounded-lg shadow-md">
            <h3 className="text-sm font-medium text-gray-500">Fee Discount</h3>
            <p className="text-2xl font-bold text-orange-600">{discount}%</p>
          </div>
        </div>
      )}

      {/* Staking Pools */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold mb-4">Staking Pools</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          {stakingPools.map((pool) => (
            <div 
              key={pool.id}
              className={`p-4 border rounded-lg cursor-pointer transition-colors ${
                selectedPool === pool.id 
                  ? 'border-blue-500 bg-blue-50' 
                  : 'border-gray-200 hover:border-gray-300'
              }`}
              onClick={() => setSelectedPool(pool.id)}
            >
              <h3 className="font-semibold">{pool.name}</h3>
              <p className="text-sm text-gray-600">{pool.lockDuration / 144} days</p>
              <p className="text-lg font-bold text-green-600">{formatAPY(pool.apyRate)}% APY</p>
              <p className="text-xs text-gray-500">{formatSTX(pool.totalStaked)} STX staked</p>
            </div>
          ))}
        </div>

        {/* Stake Form */}
        <div className="flex gap-4 items-end">
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Amount to Stake (STX)
            </label>
            <input
              type="number"
              value={stakeAmount}
              onChange={(e) => setStakeAmount(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Enter amount"
              min="1"
            />
          </div>
          <button
            onClick={handleStake}
            disabled={loading || !stakeAmount}
            className="px-6 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading ? 'Staking...' : 'Stake'}
          </button>
        </div>
      </div>

      {/* User Stakes */}
      {userStakes.length > 0 && (
        <div className="bg-white rounded-lg shadow-md p-6">
          <h2 className="text-xl font-bold mb-4">Your Stakes</h2>
          <div className="overflow-x-auto">
            <table className="w-full table-auto">
              <thead>
                <tr className="border-b">
                  <th className="text-left py-2">Pool</th>
                  <th className="text-left py-2">Amount</th>
                  <th className="text-left py-2">Status</th>
                  <th className="text-left py-2">Actions</th>
                </tr>
              </thead>
              <tbody>
                {userStakes.map((stake) => {
                  const pool = stakingPools.find(p => p.id === stake.poolId);
                  return (
                    <tr key={stake.stakeId} className="border-b">
                      <td className="py-2">{pool?.name || `Pool ${stake.poolId}`}</td>
                      <td className="py-2">{formatSTX(stake.amount)} STX</td>
                      <td className="py-2">
                        <span className={`px-2 py-1 rounded-full text-xs ${
                          stake.active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'
                        }`}>
                          {stake.active ? 'Active' : 'Inactive'}
                        </span>
                      </td>
                      <td className="py-2">
                        {stake.active && (
                          <button
                            onClick={() => handleUnstake(stake.stakeId)}
                            disabled={loading}
                            className="px-3 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700 disabled:opacity-50"
                          >
                            Unstake
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};

export default StakingDashboard;
