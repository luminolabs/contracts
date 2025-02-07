// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/INodeStakingManager.sol";
import "./interfaces/IStakingCore.sol";
import "./interfaces/INodeRegistryCore.sol";

/**
 * @title NodeStakingManager
 * @dev Contract for managing staking requirements for compute nodes in the network.
 * This contract validates stake amounts based on node compute ratings and manages
 * per-Computing Provider (CP) stake requirements.
 */
contract NodeStakingManager is INodeStakingManager {
    /// @notice Interface for interacting with the main staking contract
    IStakingCore public immutable stakingContract;

    /// @notice Interface for interacting with the node registry
    INodeRegistryCore public immutable nodeRegistry;

    /**
     * @notice Amount of stake required per unit of compute rating
     * @dev Set to 1 token (1e18) per compute rating unit
     */
    uint256 public constant STAKE_PER_RATING = 1e18;

    /**
     * @notice Mapping of CP addresses to their total stake requirements
     * @dev This tracks the cumulative stake needed across all nodes for each CP
     */
    mapping(address => uint256) private cpStakeRequirements;

    /**
     * @notice Constructor to initialize the NodeStakingManager contract
     * @param _stakingContract Address of the StakingCore contract
     * @param _nodeRegistry Address of the NodeRegistryCore contract
     */
    constructor(address _stakingContract, address _nodeRegistry) {
        stakingContract = IStakingCore(_stakingContract);
        nodeRegistry = INodeRegistryCore(_nodeRegistry);
    }

    /**
     * @notice Ensures only the NodeRegistry contract can call certain functions
     */
    modifier onlyNodeRegistry() {
        require(msg.sender == address(nodeRegistry), "NodeStakingManager: Only NodeRegistry");
        _;
    }

    /**
     * @notice Calculates required stake amount based on compute rating
     * @dev Uses STAKE_PER_RATING constant to determine required stake
     * @param computeRating The compute rating of the node
     * @return uint256 Required stake amount in tokens
     */
    function calculateRequiredStake(uint256 computeRating) public pure returns (uint256) {
        return computeRating * STAKE_PER_RATING;
    }

    /**
     * @notice Validates if a CP has sufficient stake for a given compute rating
     * @dev Checks both existing requirements and new rating requirements
     * @param cp Address of the Computing Provider
     * @param computeRating Compute rating to validate stake against
     * @return bool True if CP has sufficient stake, false otherwise
     */
    function validateStake(address cp, uint256 computeRating) external view returns (bool) {
        uint256 currentRequirement = cpStakeRequirements[cp];
        uint256 newRequirement = calculateRequiredStake(computeRating);
        uint256 totalRequired = currentRequirement + newRequirement;

        bool isValid = stakingContract.getStakedBalance(cp) >= totalRequired;
        emit StakeValidated(cp, computeRating, isValid);

        return isValid;
    }

    /**
     * @notice Updates stake requirement for a CP
     * @dev Can only be called by NodeRegistry contract
     * @param cp Address of the Computing Provider
     * @param newRequirement New total stake requirement
     */
    function updateStakeRequirement(address cp, uint256 newRequirement) external onlyNodeRegistry {
        cpStakeRequirements[cp] = newRequirement;
        emit StakeRequirementUpdated(cp, newRequirement);
    }

    /**
     * @notice Gets total required stake for a CP
     * @param cp Address of the Computing Provider
     * @return uint256 Total required stake amount
     */
    function getTotalRequiredStake(address cp) external view returns (uint256) {
        return cpStakeRequirements[cp];
    }

    /**
     * @notice Calculates stake requirement for a specific compute rating
     * @dev Wrapper around calculateRequiredStake for external visibility
     * @param computeRating Compute rating to calculate stake for
     * @return uint256 Required stake amount for the rating
     */
    function getStakeRequirementForRating(uint256 computeRating) external pure returns (uint256) {
        return calculateRequiredStake(computeRating);
    }
}