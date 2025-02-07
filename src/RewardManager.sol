// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IRewardManager.sol";
import "./interfaces/IEpochManagerCore.sol";
import "./interfaces/IRewardVault.sol";
import "./interfaces/IAccessController.sol";

/**
 * @title RewardManager
 * @notice Manages the distribution of rewards to computing providers in the network
 * @dev Coordinates with RewardVault for token distribution and handles different reward types
 *
 * This contract manages three types of rewards:
 * - Heartbeat rewards: For maintaining node uptime and network participation
 * - Leader rewards: For nodes selected as epoch leaders
 * - Disputer rewards: For successfully identifying and reporting violations
 */
contract RewardManager is IRewardManager {
    // Core contracts
    IEpochManagerCore public immutable epochManager;
    IRewardVault public immutable rewardVault;
    IAccessController public immutable accessController;

    // Custom errors
    error Unauthorized(address caller);
    error InvalidRewardType(RewardType rewardType);
    error InvalidRewardRate(uint256 rate);
    error RewardDistributionFailed(address cp, RewardType rewardType);
    error NoPendingRewards(address cp);

    // Events
    event RewardRateChanged(RewardType indexed rewardType, uint256 oldRate, uint256 newRate);
    event RewardDistributionAttempted(address indexed cp, RewardType rewardType, bool success);

    /**
     * @notice Ensures caller has OPERATOR_ROLE
     */
    modifier onlyOperator() {
        if (!accessController.isAuthorized(msg.sender, keccak256("OPERATOR_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @notice Ensures caller has ADMIN_ROLE
     */
    modifier onlyAdmin() {
        if (!accessController.isAuthorized(msg.sender, keccak256("ADMIN_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @notice Ensures caller has CONTRACTS_ROLE
     */
    modifier onlyContracts() {
        if (!accessController.isAuthorized(msg.sender, keccak256("CONTRACTS_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @notice Ensures caller has either OPERATOR_ROLE or CONTRACTS_ROLE
     */
    modifier onlyOperatorOrContracts() {
        if (!accessController.isAuthorized(msg.sender, keccak256("OPERATOR_ROLE")) &&
        !accessController.isAuthorized(msg.sender, keccak256("CONTRACTS_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @notice Initializes the RewardManager contract
     * @param _epochManager Address of the EpochManagerCore contract
     * @param _rewardVault Address of the RewardVault contract
     * @param _accessController Address of the AccessController contract
     * @dev Sets up immutable contract references for reward management
     */
    constructor(
        address _epochManager,
        address _rewardVault,
        address _accessController
    ) {
        epochManager = IEpochManagerCore(_epochManager);
        rewardVault = IRewardVault(_rewardVault);
        accessController = IAccessController(_accessController);
    }

    /**
     * @notice Distributes rewards to a computing provider
     * @param cp Address of the computing provider
     * @param rewardType Type of reward to distribute (HEARTBEAT, LEADER, or DISPUTER)
     * @dev Attempts to distribute rewards through the RewardVault
     * @dev Emits RewardDistributionAttempted and RewardDistributed events
     * @dev Reverts if distribution fails or reward type is invalid
     */
    function distributeReward(
        address cp,
        RewardType rewardType
    ) external onlyOperatorOrContracts {
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        bool success = true;

        if (rewardType == RewardType.HEARTBEAT) {
            try rewardVault.distributeHeartbeatReward(cp, currentEpoch) {
                // Distribution successful
            } catch {
                success = false;
            }
        } else if (rewardType == RewardType.LEADER) {
            try rewardVault.distributeLeaderReward(cp, currentEpoch) {
                // Distribution successful
            } catch {
                success = false;
            }
        } else if (rewardType == RewardType.DISPUTER) {
            try rewardVault.distributeDisputerReward(cp, currentEpoch) {
                // Distribution successful
            } catch {
                success = false;
            }
        } else {
            revert InvalidRewardType(rewardType);
        }

        emit RewardDistributionAttempted(cp, rewardType, success);

        if (!success) {
            revert RewardDistributionFailed(cp, rewardType);
        }

        emit RewardDistributed(cp, rewardVault.getRewardRate(rewardType), rewardType);
    }

    /**
     * @notice Allows computing providers to claim their accumulated rewards
     * @dev Claims rewards through the RewardVault
     * @dev Emits RewardClaimed event
     * @dev Reverts if caller has no pending rewards
     */
    function claimRewards() external {
        if (rewardVault.getPendingRewards(msg.sender) == 0) {
            revert NoPendingRewards(msg.sender);
        }
        rewardVault.claimRewards();
        emit RewardClaimed(msg.sender, rewardVault.getPendingRewards(msg.sender));
    }

    /**
     * @notice Updates the reward rate for a specific reward type
     * @param rewardType Type of reward to update
     * @param newRate New reward rate value
     * @dev Only callable by admin
     * @dev Emits RewardRateChanged and RewardRateUpdated events
     * @dev Reverts if new rate is zero
     */
    function updateRewardRate(
        RewardType rewardType,
        uint256 newRate
    ) external onlyAdmin {
        if (newRate == 0) {
            revert InvalidRewardRate(newRate);
        }

        uint256 oldRate = rewardVault.getRewardRate(rewardType);
        rewardVault.updateRewardRate(rewardType, newRate);

        emit RewardRateChanged(rewardType, oldRate, newRate);
        emit RewardRateUpdated(rewardType, newRate);
    }

    /**
     * @notice Gets pending rewards for a computing provider
     * @param cp Address of computing provider
     * @return uint256 Amount of pending rewards
     */
    function getPendingRewards(address cp) external view returns (uint256) {
        return rewardVault.getPendingRewards(cp);
    }

    /**
     * @notice Gets current reward rate for a specific reward type
     * @param rewardType Type of reward
     * @return uint256 Current reward rate
     */
    function getRewardRate(RewardType rewardType) external view returns (uint256) {
        return rewardVault.getRewardRate(rewardType);
    }

    /**
     * @notice Gets total rewards distributed in current epoch
     * @return uint256 Total rewards for current epoch
     */
    function getCurrentEpochRewards() external view returns (uint256) {
        return rewardVault.getEpochRewards(epochManager.getCurrentEpoch());
    }
}