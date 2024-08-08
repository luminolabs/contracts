// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./ACL.sol";
import "./StateManager.sol";
import "../lib/Structs.sol";
import "../Core/storage/JobStorage.sol";

/**
 * @title JobsManager
 * @dev Manages the creation, assignment, and lifecycle of jobs in the Lumino Staking System.
 * This contract handles job-related operations and maintains job states.
 */
contract JobsManager is Initializable, StateManager, ACL, JobStorage {
    /**
     * @notice Emitted when a new job is created
     * @param jobId The ID of the newly created job
     * @param creator The address of the account that created the job
     * @param epoch The epoch in which the job was created
     */
    event JobCreated(
        uint256 indexed jobId,
        address indexed creator,
        uint32 epoch
    );

    /**
     * @notice Emitted when a job's status is updated
     * @param jobId The ID of the job whose status was updated
     * @param newStatus The new status of the job
     */
    event JobStatusUpdated(uint256 indexed jobId, Status newStatus);

    /**
     * @dev Initializes the JobsManager contract.
     * @param _jobsPerStaker The number of jobs to be assigned per staker
     */
    function initialize(
        uint8 _jobsPerStaker
    ) external initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        // Initialize the job ID counter
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        jobIdCounter = 1;

        // Set the number of jobs to be assigned per staker
        jobsPerStaker = _jobsPerStaker;
    }

    /**
     * @dev Creates a new job in the system.
     * @param _jobDetailsInJSON A JSON string containing the job details
     */
    function createJob(string memory _jobDetailsInJSON) external payable returns (uint256) {
        // Get the current epoch
        uint32 currentEpoch = getEpoch();

        // Generate a new unique job ID
        uint256 newJobId = jobIdCounter++;

        // Create and store the new job
        jobs[newJobId] = Structs.Job({
            jobId: newJobId,
            creator: msg.sender,
            assignee: address(0), // No assignee yet
            creationEpoch: currentEpoch,
            executionEpoch: 0, // Will be set when job starts execution
            proofGenerationEpoch: 0, // Will be set when staker starts proof generation
            completionEpoch: 0, // Will be set when job is completed
            jobDetailsInJSON: _jobDetailsInJSON
        });

        // Set the initial status of the job
        jobStatus[newJobId] = Status.Created;

        // Add the new job to the list of active jobs
        activeJobIds.push(newJobId);

        // Emit an event to log the job creation
        emit JobCreated(newJobId, msg.sender, currentEpoch);

        return newJobId;
    }

    /**
     * @dev Updates the status of a job.
     * @param _jobId The ID of the job to update
     * @param _newStatus The new status to set for the job
     */
    function updateJobStatus(uint256 _jobId, Status _newStatus) external {
        // Ensure the job exists
        require(jobs[_jobId].jobId != 0, "Job does not exist");
        // Ensure only Assignee can update the status
        require(jobs[_jobId].assignee == msg.sender, "Only assignee can update the jobStatus");

        // Ensure the new status is a valid progression from the current status
        require(_newStatus > jobStatus[_jobId], "Invalid status transition");

        // Update the job status
        jobStatus[_jobId] = _newStatus;

        // Perform additional actions based on the new status
        if (_newStatus == Status.Execution) {
            // Record the execution start epoch
            jobs[_jobId].executionEpoch = getEpoch();
        } else if (_newStatus == Status.Completed) {
            // Record the execution start epoch
            jobs[_jobId].proofGenerationEpoch = getEpoch();
        } else if (_newStatus == Status.Completed) {
            // Record the completion epoch
            jobs[_jobId].completionEpoch = getEpoch();
            // Remove the job from the active jobs list
            removeActiveJob(_jobId);
        }

        // Emit an event to log the status update
        emit JobStatusUpdated(_jobId, _newStatus);
    }
    
    // TODO: Manual AssignJob function

    /**
     * @dev Retrieves the list of active job IDs.
     * @return An array of active job IDs
     */
    function getActiveJobs() external view returns (uint256[] memory) {
        return activeJobIds;
    }

    /**
     * @dev Retrieves the details of a specific job.
     * @param _jobId The ID of the job to retrieve
     * @return The Job struct containing the job details
     */
    function getJobDetails(
        uint256 _jobId
    ) external view returns (Structs.Job memory) {
        require(jobs[_jobId].jobId != 0, "Job does not exist");
        return jobs[_jobId];
    }

    /**
     * @dev Retrieves the current status of a specific job.
     * @param _jobId The ID of the job to check
     * @return The current status of the job
     */
    function getJobStatus(uint256 _jobId) external view returns (Status) {
        return jobStatus[_jobId];
    }

    // TODO: visibility to be moved to internal, the seed should fetch from the 
    // the voteManager/blockManager contracts at the end of each epoch
    // the seed will be set by the blockProposer of the epoch
    /**
     * @dev Assigns jobs to a staker based on a seed value.
     * @param _seed A random seed used for job assignment
     * @param _stakerId The ID of the staker to assign jobs to
     * @return An array of job IDs assigned to the staker
     */
    function getJobsForStaker(
        bytes32 _seed,
        uint32 _stakerId
    ) external returns (uint256[] memory) {
        // Ensure there are enough active jobs to assign
        require(activeJobIds.length >= jobsPerStaker, "Not enough active jobs");

        // Create an array to store the assigned job IDs
        uint256[] memory assignedJobs = new uint256[](jobsPerStaker);

        for (uint256 i = 0; i < activeJobIds.length; i++) {
            if (jobStatus[activeJobIds[i]] == Constants.Status.Assigned) {
                delete activeJobIds[i];
            }
        }

        // Assign jobs to the staker
        for (uint8 i = 0; i < jobsPerStaker; i++) {
            // Use the seed, staker ID, and index to generate a pseudo-random index
            uint256 index = uint256(
                keccak256(abi.encodePacked(_seed, _stakerId, i))
            ) % activeJobIds.length;
            // Assign the job at the calculated index
            assignedJobs[i] = activeJobIds[index];
        }

        return assignedJobs;
    }

    /**
     * @dev Removes a job from the list of active jobs.
     * @param _jobId The ID of the job to remove
     */
    function removeActiveJob(uint256 _jobId) internal {
        for (uint256 i = 0; i < activeJobIds.length; i++) {
            if (activeJobIds[i] == _jobId) {
                // Replace the job to remove with the last job in the array
                activeJobIds[i] = activeJobIds[activeJobIds.length - 1];
                // Remove the last element (now a duplicate)
                activeJobIds.pop();
                break;
            }
        }
    }
}
