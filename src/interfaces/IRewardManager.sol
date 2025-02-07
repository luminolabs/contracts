// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardManager {
    event RewardDistributed(address indexed cp, uint256 amount, RewardType rewardType);
    event RewardRateUpdated(RewardType indexed rewardType, uint256 newRate);
    event RewardClaimed(address indexed cp, uint256 amount);

    enum RewardType { HEARTBEAT, LEADER, DISPUTER }

    function distributeReward(address cp, RewardType rewardType) external;
    function claimRewards() external;
    function updateRewardRate(RewardType rewardType, uint256 newRate) external;
    function getPendingRewards(address cp) external view returns (uint256);
    function getRewardRate(RewardType rewardType) external view returns (uint256);
}