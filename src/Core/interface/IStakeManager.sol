// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../lib/Structs.sol";
import "../storage/Constants.sol";

/**
 * @title IStakeManager
 * @dev Interface for the StakeManager contract in the Lumino Staking System.
 * This interface defines the expected functions for managing staking operations within the system.
 */
interface IStakeManager {

    /**
     * @dev Retrieves the staker ID associated with a given address.
     * @param _address The address of the staker
     * @return The unique identifier (staker ID) associated with the given address
     */
    function getStakerId(address _address) external view returns (uint32);

    /**
     * @dev Retrieves the full staker information for a given staker ID.
     * @param _id The unique identifier of the staker
     * @return staker A Staker struct containing all the staker's information
     */
    function getStaker(uint32 _id) external view returns (Structs.Staker memory staker);

    /**
     * @dev Retrieves the total number of stakers in the Lumino network.
     * @return The current count of stakers in the system
     */
    function getNumStakers() external view returns (uint32);

    /**
     * @dev Retrieves the current stake amount for a given staker.
     * @param stakerId The unique identifier of the staker
     * @return The current stake amount of the specified staker
     */
    function getStake(uint32 stakerId) external view returns (uint256);

    // NOTE: The following functions are not explicitly defined in the provided interface,
    // but they would typically be part of a StakeManager. Consider adding them if needed:

    /**
     * @dev Allows a user to stake tokens in the system.
     * @param _amount The amount of tokens to stake
     * @param _machineSpecInJSON JSON string containing the staker's machine specifications
     */
    // function stake(uint256 _amount, string memory _machineSpecInJSON) external;

    /**
     * @dev Initiates the unstaking process for a staker.
     * @param _amount The amount of tokens to unstake
     */
    // function unstake(uint256 _amount) external;

    /**
     * @dev Allows a staker to withdraw their unstaked tokens after the lock period.
     */
    // function withdraw() external;

    /**
     * @dev Applies penalties to a staker (e.g., for malicious behavior).
     * @param _stakerId The ID of the staker to penalize
     * @param _amount The amount of penalty to apply
     */
    // function applyPenalty(uint32 _stakerId, uint256 _amount) external;

    /**
     * @dev Distributes rewards to a staker.
     * @param _stakerId The ID of the staker to reward
     * @param _amount The amount of reward to distribute
     */
    // function distributeReward(uint32 _stakerId, uint256 _amount) external;
}