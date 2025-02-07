// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardVault {
    enum RewardType { HEARTBEAT, LEADER, DISPUTER }

    event RewardPoolFunded(RewardType rewardType, uint256 amount);
    event RewardRateUpdated(RewardType rewardType, uint256 newRate);
    event RewardDistributed(address indexed recipient, uint256 amount, RewardType rewardType);
    event RewardsClaimed(address indexed recipient, uint256 amount);

    // Funding functions
    function fundHeartbeatPool(uint256 amount) external;
    function fundLeaderPool(uint256 amount) external;
    function fundDisputerPool(uint256 amount) external;

    // Distribution functions
    function distributeHeartbeatReward(address recipient, uint256 epoch) external;
    function distributeLeaderReward(address recipient, uint256 epoch) external;
    function distributeDisputerReward(address recipient, uint256 epoch) external;

    // Claim function
    function claimRewards() external;

    // Admin functions
    function updateRewardRate(RewardType rewardType, uint256 newRate) external;

    // View functions
    function getRewardPoolBalance(RewardType rewardType) external view returns (uint256);
    function getPendingRewards(address recipient) external view returns (uint256);
    function getEpochRewards(uint256 epoch) external view returns (uint256);
    function getRewardRate(RewardType rewardType) external view returns (uint256);
}