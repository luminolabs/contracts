// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";
import "../storage/Constants.sol";

/**
 * @title IJobsManager
 * @dev Interface for the JobsManager contract in the Lumino Staking System.
 * This interface defines the expected functions and events for managing jobs within the system.
 */
interface IJobsManager {

    /**
     * @dev Emitted when a new job is created in the system.
     * @param jobId The unique identifier of the created job
     * @param creator The address of the account that created the job
     * @param epoch The epoch in which the job was created
     */
    event JobCreated(uint256 indexed jobId, address indexed creator, uint32 epoch);

    /**
     * @dev Emitted when the status of a job is updated.
     * @param jobId The unique identifier of the job
     * @param newStatus The new status of the job
     */
    event JobStatusUpdated(uint256 indexed jobId, Constants.Status newStatus);

    /**
     * @dev Initializes the JobsManager contract.
     * @param _jobsPerStaker The number of jobs to be assigned per staker
     */
    function initialize(uint8 _jobsPerStaker) external;

    /**
     * @dev Creates a new job in the system.
     * @param _jobDetailsInJSON A JSON string containing the job details
     */
    function createJob(string memory _jobDetailsInJSON) external;

    /**
     * @dev Updates the status of an existing job.
     * @param _jobId The unique identifier of the job to update
     * @param _newStatus The new status to set for the job
     */
    function updateJobStatus(uint256 _jobId, Constants.Status _newStatus) external;

    /**
     * @dev Retrieves the list of active job IDs.
     * @return An array of active job IDs
     */
    function getActiveJobs() external view returns (uint256[] memory);

    /**
     * @dev Retrieves the details of a specific job.
     * @param _jobId The unique identifier of the job
     * @return A Job struct containing the job details
     */
    function getJobDetails(uint256 _jobId) external view returns (Structs.Job memory);

    /**
     * @dev Retrieves the current status of a specific job.
     * @param _jobId The unique identifier of the job
     * @return The current status of the job
     */
    function getJobStatus(uint256 _jobId) external view returns (Constants.Status);

    /**
     * @dev Assigns jobs to a staker based on a seed value.
     * @param _seed A random seed used for job assignment
     * @param _stakerId The ID of the staker to assign jobs to
     * @return An array of job IDs assigned to the staker
     */
    function getJobsForStaker(bytes32 _seed, uint32 _stakerId) external view returns (uint256[] memory);

    /**
     * @dev Retrieves the number of jobs assigned per staker.
     * @return The number of jobs per staker
     */
    function jobsPerStaker() external view returns (uint8);

    /**
     * @dev Retrieves the current job ID counter.
     * @return The current value of the job ID counter
     */
    function jobIdCounter() external view returns (uint256);
}