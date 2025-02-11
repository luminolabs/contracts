// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Enums} from "../libraries/Enums.sol";

interface IRewardVault {
    event RewardPoolFunded(Enums.RewardType rewardType, uint256 amount);
    event RewardRateUpdated(Enums.RewardType rewardType, uint256 newRate);
    event RewardDistributed(address indexed recipient, uint256 amount, Enums.RewardType rewardType);
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
    function updateRewardRate(Enums.RewardType rewardType, uint256 newRate) external;

    // View functions
    function getRewardPoolBalance(Enums.RewardType rewardType) external view returns (uint256);

    function getPendingRewards(address recipient) external view returns (uint256);

    function getEpochRewards(uint256 epoch) external view returns (uint256);

    function getRewardRate(Enums.RewardType rewardType) external view returns (uint256);
}