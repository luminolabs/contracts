// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Enums} from "../libraries/Enums.sol";

interface IRewardManager {
    event RewardDistributed(address indexed cp, uint256 amount, Enums.RewardType rewardType);
    event RewardRateUpdated(Enums.RewardType indexed rewardType, uint256 newRate);
    event RewardClaimed(address indexed cp, uint256 amount);

    function distributeReward(address cp, Enums.RewardType rewardType) external;

    function claimRewards() external;

    function updateRewardRate(Enums.RewardType rewardType, uint256 newRate) external;

    function getPendingRewards(address cp) external view returns (uint256);

    function getRewardRate(Enums.RewardType rewardType) external view returns (uint256);
}