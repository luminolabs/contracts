// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

/**
 * @title IVoteManager
 * @dev Interface for the VoteManager contract in the Lumino Staking System.
 * This interface defines the expected functions for managing the voting process,
 * including commit and reveal phases, within the system.
 */
interface IVoteManager {

    /**
     * @dev Initializes the VoteManager contract.
     * @param stakeManagerAddress Address of the StakeManager contract
     * @param jobsManagerAddress Address of the JobsManager contract
     * @param blockManagerAddress Address of the BlockManager contract
     */
    function initialize(
        address stakeManagerAddress,
        address jobsManagerAddress,
        address blockManagerAddress
    ) external;

    /**
     * @dev Allows a staker to commit their vote for an epoch.
     * @param epoch The epoch number for which the commitment is being made
     * @param commitment The hashed commitment of the staker's vote
     */
    function commit(uint32 epoch, bytes32 commitment) external;

    /**
     * @dev Allows a staker to reveal their vote and job results for an epoch.
     * @param epoch The epoch number for which the reveal is being made
     * @param results Array of JobVerifier structs containing job results
     * @param signature The staker's signature for verification
     */
    function reveal(
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes memory signature
    ) external;

    /**
     * @dev Retrieves the commitment details for a specific staker.
     * @param stakerId The ID of the staker
     * @return The Commitment struct containing the staker's commitment details
     */
    function getCommitment(uint32 stakerId) external view returns (Structs.Commitment memory);

    /**
     * @dev Retrieves the last epoch in which a staker revealed their vote.
     * @param stakerId The ID of the staker
     * @return The epoch number of the staker's last reveal
     */
    function getEpochLastRevealed(uint32 stakerId) external view returns (uint32);

    /**
     * @dev Retrieves the current salt used in the voting process.
     * @return The current salt value
     */
    function getSalt() external view returns (bytes32);

    /**
     * @dev Retrieves the assigned jobs for a staker in a specific epoch.
     * @param epoch The epoch number
     * @param stakerId The ID of the staker
     * @return An array of AssignedJob structs
     */
    function getAssignedJobs(uint32 epoch, uint32 stakerId) external view returns (Structs.AssignedJob[] memory);

    // NOTE: The following functions are commented out but could be useful additions:

    /**
     * @dev Checks if a staker has committed for a specific epoch.
     * @param epoch The epoch number
     * @param stakerId The ID of the staker
     * @return A boolean indicating whether the staker has committed
     */
    // function hasCommitted(uint32 epoch, uint32 stakerId) external view returns (bool);

    /**
     * @dev Checks if a staker has revealed their vote for a specific epoch.
     * @param epoch The epoch number
     * @param stakerId The ID of the staker
     * @return A boolean indicating whether the staker has revealed
     */
    // function hasRevealed(uint32 epoch, uint32 stakerId) external view returns (bool);
}