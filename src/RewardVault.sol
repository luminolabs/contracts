// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title RewardVault
 * @notice A vault contract that manages and distributes rewards to computing providers in the network
 * @dev This contract handles three types of rewards: heartbeat, leader, and disputer rewards
 */
contract RewardVault is IRewardVault, ReentrancyGuard {
    // Core state
    /**
     * @notice The ERC20 token used for rewards
     * @dev This is immutable and set during contract construction
     */
    IERC20 public immutable rewardToken;

    /**
     * @notice The access controller that manages role-based permissions
     * @dev This is immutable and set during contract construction
     */
    IAccessController public immutable accessController;

    // Reward pools
    /**
     * @notice Pool of tokens available for heartbeat rewards
     * @dev Decremented when rewards are distributed, incremented when funded
     */
    uint256 public heartbeatRewardPool;

    /**
     * @notice Pool of tokens available for leader rewards
     * @dev Decremented when rewards are distributed, incremented when funded
     */
    uint256 public leaderRewardPool;

    /**
     * @notice Pool of tokens available for disputer rewards
     * @dev Decremented when rewards are distributed, incremented when funded
     */
    uint256 public disputerRewardPool;

    // Reward rates
    /**
     * @notice Amount of tokens given per heartbeat reward
     * @dev Can be updated by admin, must be non-zero
     */
    uint256 public heartbeatRewardRate;

    /**
     * @notice Amount of tokens given per leader reward
     * @dev Can be updated by admin, must be non-zero
     */
    uint256 public leaderRewardRate;

    /**
     * @notice Amount of tokens given per disputer reward
     * @dev Can be updated by admin, must be non-zero
     */
    uint256 public disputerRewardRate;

    // Tracking
    /**
     * @notice Tracks total rewards distributed in each epoch
     * @dev Mapping from epoch number to total rewards
     */
    mapping(uint256 => uint256) public epochRewards;

    /**
     * @notice Tracks unclaimed rewards for each address
     * @dev Mapping from address to pending reward amount
     */
    mapping(address => uint256) public pendingRewards;

    /**
     * @notice Tracks total rewards earned by each address
     * @dev Mapping from address to total earned rewards
     */
    mapping(address => uint256) public totalRewardsEarned;

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
    );

/**
 * @notice Adds funds to the heartbeat reward pool
     * @dev Only callable by admin
     * @param amount Amount of tokens to add to the pool
     */
function fundHeartbeatPool(uint256 amount) external;

/**
 * @notice Adds funds to the leader reward pool
     * @dev Only callable by admin
     * @param amount Amount of tokens to add to the pool
     */
function fundLeaderPool(uint256 amount) external;

/**
 * @notice Adds funds to the disputer reward pool
     * @dev Only callable by admin
     * @param amount Amount of tokens to add to the pool
     */
function fundDisputerPool(uint256 amount) external;

/**
 * @notice Distributes a heartbeat reward to a recipient
     * @dev Only callable by contracts with CONTRACTS_ROLE
     * @param recipient Address to receive the reward
     * @param epoch Current epoch number
     */
function distributeHeartbeatReward(address recipient, uint256 epoch) external;

/**
 * @notice Distributes a leader reward to a recipient
     * @dev Only callable by contracts with CONTRACTS_ROLE
     * @param recipient Address to receive the reward
     * @param epoch Current epoch number
     */
function distributeLeaderReward(address recipient, uint256 epoch) external;

/**
 * @notice Distributes a disputer reward to a recipient
     * @dev Only callable by contracts with CONTRACTS_ROLE
     * @param recipient Address to receive the reward
     * @param epoch Current epoch number
     */
function distributeDisputerReward(address recipient, uint256 epoch) external;

/**
 * @notice Allows users to claim their pending rewards
     * @dev Uses ReentrancyGuard, requires non-zero pending rewards
     */
function claimRewards() external;

/**
 * @notice Updates the rate for a specific reward type
     * @dev Only callable by admin, new rate must be non-zero
     * @param rewardType Type of reward (HEARTBEAT, LEADER, or DISPUTER)
     * @param newRate New reward rate to set
     */
function updateRewardRate(RewardType rewardType, uint256 newRate) external;

// View Functions

/**
 * @notice Gets the current balance of a reward pool
     * @param rewardType Type of reward pool to query
     * @return uint256 Current balance of the specified pool
     */
function getRewardPoolBalance(RewardType rewardType) external view returns (uint256);

/**
 * @notice Gets pending rewards for a recipient
     * @param recipient Address to query
     * @return uint256 Amount of unclaimed rewards
     */
function getPendingRewards(address recipient) external view returns (uint256);

/**
 * @notice Gets total rewards distributed in an epoch
     * @param epoch Epoch number to query
     * @return uint256 Total rewards distributed in the epoch
     */
function getEpochRewards(uint256 epoch) external view returns (uint256);

/**
 * @notice Gets the current rate for a reward type
     * @param rewardType Type of reward to query
     * @return uint256 Current reward rate
     */
function getRewardRate(RewardType rewardType) external view returns (uint256);
}