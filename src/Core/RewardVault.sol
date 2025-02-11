// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {IRewardVault} from "./interfaces/IRewardVault.sol";
import {Enums} from "./libraries/Enums.sol";

/**
 * @title RewardVault
 * @notice A vault contract that manages and distributes rewards to computing providers in the network
 * @dev This contract handles three types of rewards: heartbeat, leader, and disputer rewards
 */
contract RewardVault is IRewardVault, AccessControlled, ReentrancyGuard {
    // Core contracts
    IERC20 public immutable rewardToken;

    // Reward pools
    uint256 public heartbeatRewardPool;
    uint256 public leaderRewardPool;
    uint256 public disputerRewardPool;

    // Reward rates
    uint256 public heartbeatRewardRate;
    uint256 public leaderRewardRate;
    uint256 public disputerRewardRate;

    // State variables
    /// @dev Tracks rewards distributed in each epoch
    mapping(uint256 => uint256) public epochRewards;
    /// @dev Tracks pending rewards for each computing provider
    mapping(address => uint256) public pendingRewards;
    /// @dev Tracks total rewards earned by each computing provider
    mapping(address => uint256) public totalRewardsEarned;

    // Custom errors
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientPoolBalance(uint256 required, uint256 available);
    error NoPendingRewards();
    error TransferFailed();
    error InvalidRewardRate();

    /**
     * @notice Initializes the reward vault
     * @param _rewardToken Address of the ERC20 token used for rewards
     * @param _accessController Address of the access controller contract
     * @param _heartbeatRate Initial rate for heartbeat rewards
     * @param _leaderRate Initial rate for leader rewards
     * @param _disputerRate Initial rate for disputer rewards
     */
    constructor(
        address _rewardToken,
        address _accessController,
        uint256 _heartbeatRate,
        uint256 _leaderRate,
        uint256 _disputerRate
    ) AccessControlled(_accessController) {
        if (_rewardToken == address(0) || _accessController == address(0)) {
            revert ZeroAddress();
        }
        if (_heartbeatRate == 0 || _leaderRate == 0 || _disputerRate == 0) {
            revert InvalidRewardRate();
        }

        rewardToken = IERC20(_rewardToken);
        heartbeatRewardRate = _heartbeatRate;
        leaderRewardRate = _leaderRate;
        disputerRewardRate = _disputerRate;
    }

    /**
     * @notice Adds funds to the heartbeat reward pool
     * @param amount Amount of tokens to add to the pool
     */
    function fundHeartbeatPool(uint256 amount) external onlyAdmin {
        if (amount == 0) revert ZeroAmount();

        bool success = rewardToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        heartbeatRewardPool += amount;
        emit RewardPoolFunded(Enums.RewardType.HEARTBEAT, amount);
    }

    /**
     * @notice Adds funds to the leader reward pool
     * @param amount Amount of tokens to add to the pool
     */
    function fundLeaderPool(uint256 amount) external onlyAdmin {
        if (amount == 0) revert ZeroAmount();

        bool success = rewardToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        leaderRewardPool += amount;
        emit RewardPoolFunded(Enums.RewardType.LEADER, amount);
    }

    /**
     * @notice Adds funds to the disputer reward pool
     * @param amount Amount of tokens to add to the pool
     */
    function fundDisputerPool(uint256 amount) external onlyAdmin {
        if (amount == 0) revert ZeroAmount();

        bool success = rewardToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        disputerRewardPool += amount;
        emit RewardPoolFunded(Enums.RewardType.DISPUTER, amount);
    }

    /**
     * @notice Distributes a heartbeat reward to a recipient
     * @param recipient Address to receive the reward
     * @param epoch Current epoch number
     */
    function distributeHeartbeatReward(address recipient, uint256 epoch) external onlyContracts {
        if (heartbeatRewardPool < heartbeatRewardRate) {
            revert InsufficientPoolBalance(heartbeatRewardRate, heartbeatRewardPool);
        }

        heartbeatRewardPool -= heartbeatRewardRate;
        pendingRewards[recipient] += heartbeatRewardRate;
        totalRewardsEarned[recipient] += heartbeatRewardRate;
        epochRewards[epoch] += heartbeatRewardRate;

        emit RewardDistributed(recipient, heartbeatRewardRate, Enums.RewardType.HEARTBEAT);
    }

    /**
     * @notice Distributes a leader reward to a recipient
     * @param recipient Address to receive the reward
     * @param epoch Current epoch number
     */
    function distributeLeaderReward(address recipient, uint256 epoch) external onlyContracts {
        if (leaderRewardPool < leaderRewardRate) {
            revert InsufficientPoolBalance(leaderRewardRate, leaderRewardPool);
        }

        leaderRewardPool -= leaderRewardRate;
        pendingRewards[recipient] += leaderRewardRate;
        totalRewardsEarned[recipient] += leaderRewardRate;
        epochRewards[epoch] += leaderRewardRate;

        emit RewardDistributed(recipient, leaderRewardRate, Enums.RewardType.LEADER);
    }

    /**
     * @notice Distributes a disputer reward to a recipient
     * @param recipient Address to receive the reward
     * @param epoch Current epoch number
     */
    function distributeDisputerReward(address recipient, uint256 epoch) external onlyContracts {
        if (disputerRewardPool < disputerRewardRate) {
            revert InsufficientPoolBalance(disputerRewardRate, disputerRewardPool);
        }

        disputerRewardPool -= disputerRewardRate;
        pendingRewards[recipient] += disputerRewardRate;
        totalRewardsEarned[recipient] += disputerRewardRate;
        epochRewards[epoch] += disputerRewardRate;

        emit RewardDistributed(recipient, disputerRewardRate, Enums.RewardType.DISPUTER);
    }

    /**
     * @notice Allows users to claim their pending rewards
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        if (amount == 0) revert NoPendingRewards();

        pendingRewards[msg.sender] = 0;

        bool success = rewardToken.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit RewardsClaimed(msg.sender, amount);
    }

    /**
     * @notice Updates the rate for a specific reward type
     * @param rewardType Type of reward (HEARTBEAT, LEADER, or DISPUTER)
     * @param newRate New reward rate to set
     */
    function updateRewardRate(Enums.RewardType rewardType, uint256 newRate) external onlyAdmin {
        if (newRate == 0) revert InvalidRewardRate();

        if (rewardType == Enums.RewardType.HEARTBEAT) {
            heartbeatRewardRate = newRate;
        } else if (rewardType == Enums.RewardType.LEADER) {
            leaderRewardRate = newRate;
        } else if (rewardType == Enums.RewardType.DISPUTER) {
            disputerRewardRate = newRate;
        }

        emit RewardRateUpdated(rewardType, newRate);
    }

    /**
     * @notice Gets the current balance of a reward pool
     * @param rewardType Type of reward pool to query
     * @return uint256 Current balance of the specified pool
     */
    function getRewardPoolBalance(Enums.RewardType rewardType) external view returns (uint256) {
        if (rewardType == Enums.RewardType.HEARTBEAT) return heartbeatRewardPool;
        if (rewardType == Enums.RewardType.LEADER) return leaderRewardPool;
        if (rewardType == Enums.RewardType.DISPUTER) return disputerRewardPool;
        return 0;
    }

    /**
     * @notice Gets pending rewards for a recipient
     * @param recipient Address to query
     * @return uint256 Amount of unclaimed rewards
     */
    function getPendingRewards(address recipient) external view returns (uint256) {
        return pendingRewards[recipient];
    }

    /**
     * @notice Gets total rewards distributed in an epoch
     * @param epoch Epoch number to query
     * @return uint256 Total rewards distributed in the epoch
     */
    function getEpochRewards(uint256 epoch) external view returns (uint256) {
        return epochRewards[epoch];
    }

    /**
     * @notice Gets the current rate for a reward type
     * @param rewardType Type of reward to query
     * @return uint256 Current reward rate
     */
    function getRewardRate(Enums.RewardType rewardType) external view returns (uint256) {
        if (rewardType == Enums.RewardType.HEARTBEAT) return heartbeatRewardRate;
        if (rewardType == Enums.RewardType.LEADER) return leaderRewardRate;
        if (rewardType == Enums.RewardType.DISPUTER) return disputerRewardRate;
        return 0;
    }
}