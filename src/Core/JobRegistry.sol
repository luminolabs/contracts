// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IJobPaymentEscrow} from "./interfaces/IJobPaymentEscrow.sol";
import {IJobPaymentManager} from "./interfaces/IJobPaymentManager.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {INodeRegistryCore} from "./interfaces/INodeRegistryCore.sol";

/**
 * @title JobRegistry
 * @dev Contract for managing the lifecycle of computing jobs in the Lumino network.
 * Handles job submission, status tracking, and node assignment while enforcing
 * payment escrow requirements and access controls.
 */
contract JobRegistry is IJobRegistry, AccessControlled {
    // Core contracts
    IJobPaymentManager public immutable paymentManager;
    INodeRegistryCore public immutable nodeRegistry;
    IJobPaymentEscrow public immutable paymentEscrow;

    // State variables
    /// @dev Counter for job IDs
    uint256 private jobCounter;
    /// @dev Job struct to store job details by ID
    mapping(uint256 => Job) private jobs;
    /// @dev Mapping of job IDs by status
    mapping(JobStatus => uint256[]) private jobsByStatus;
    /// @dev Mapping of job IDs by submitter
    mapping(address => uint256[]) private submitterJobs;

    // Custom errors
    error JobNotFound(uint256 jobId);
    error InvalidJobStatus(uint256 jobId, JobStatus currentStatus, JobStatus newStatus);
    error NodeNotActive(uint256 nodeId);
    error InsufficientEscrowBalance(address submitter);
    error InvalidStatusTransition(JobStatus from, JobStatus to);

    // Events are defined in the interface
    //

    /**
     * @dev Ensures job exists
     */
    modifier jobExists(uint256 jobId) {
        if (jobs[jobId].submitter == address(0)) {
            revert JobNotFound(jobId);
        }
        _;
    }

    constructor(
        address _paymentManager,
        address _nodeRegistry,
        address _paymentEscrow,
        address _accessController
    ) AccessControlled(_accessController) {
        paymentManager = IJobPaymentManager(_paymentManager);
        nodeRegistry = INodeRegistryCore(_nodeRegistry);
        paymentEscrow = IJobPaymentEscrow(_paymentEscrow);
    }

    /**
     * @notice Submit a new job to the registry
     * @dev Creates a new job entry after validating submitter has sufficient escrow balance
     * @param jobArgs Job arguments/parameters in string format
     * @param requiredPool Required compute pool identifier
     * @return jobId Unique identifier for the submitted job
     */
    function submitJob(
        string calldata jobArgs,
        uint256 requiredPool
    ) external returns (uint256) {
        // Validate submitter has minimum balance in escrow
        if (!paymentEscrow.hasMinimumBalance(msg.sender)) {
            revert InsufficientEscrowBalance(msg.sender);
        }

        // Create new job
        jobCounter++;
        uint256 jobId = jobCounter;

        jobs[jobId] = Job({
            jobId: jobId,
            submitter: msg.sender,
            assignedNode: 0,
            status: JobStatus.NEW,
            requiredPool: requiredPool,
            jobArgs: jobArgs,
            createdAt: block.timestamp
        });

        // Add to tracking mappings
        jobsByStatus[JobStatus.NEW].push(jobId);
        submitterJobs[msg.sender].push(jobId);

        emit JobSubmitted(jobId, msg.sender, requiredPool);
        return jobId;
    }

    /**
     * @notice Update the status of an existing job
     * @dev Can only be called by operators or authorized contracts
     * @param jobId Job identifier
     * @param newStatus New status to set for the job
     */
    function updateJobStatus(
        uint256 jobId,
        JobStatus newStatus
    ) external onlyOperatorOrContracts jobExists(jobId) {
        Job storage job = jobs[jobId];
        JobStatus currentStatus = job.status;

        // Validate status transition
        if (!isValidStatusTransition(currentStatus, newStatus)) {
            revert InvalidStatusTransition(currentStatus, newStatus);
        }

        // Remove from old status tracking
        removeFromStatusArray(jobId, currentStatus);

        // Update job status
        job.status = newStatus;

        // Add to new status tracking
        jobsByStatus[newStatus].push(jobId);

        emit JobStatusUpdated(jobId, newStatus);
    }

    /**
     * @notice Assign a node to handle a job
     * @dev Can only be called by authorized contracts
     * @param jobId Job identifier
     * @param nodeId Node identifier
     */
    function assignNode(
        uint256 jobId,
        uint256 nodeId
    ) external onlyContracts jobExists(jobId) {
        Job storage job = jobs[jobId];

        // Validate node is active
        if (!nodeRegistry.isNodeActive(nodeId)) {
            revert NodeNotActive(nodeId);
        }

        // Validate job is in NEW status
        if (job.status != JobStatus.NEW) {
            revert InvalidJobStatus(jobId, job.status, JobStatus.NEW);
        }

        // Update job
        job.assignedNode = nodeId;
        job.status = JobStatus.ASSIGNED;

        // Update status tracking
        removeFromStatusArray(jobId, JobStatus.NEW);
        jobsByStatus[JobStatus.ASSIGNED].push(jobId);

        emit JobAssigned(jobId, nodeId);
    }

    /**
     * @notice Retrieve details for a specific job
     * @param jobId Job identifier
     * @return Job struct containing all job details
     */
    function getJob(uint256 jobId) external view jobExists(jobId) returns (Job memory) {
        return jobs[jobId];
    }

    /**
     * @notice Get all jobs with a specific status
     * @param status Job status to query
     * @return uint256[] Array of job IDs with the specified status
     */
    function getJobsByStatus(JobStatus status) external view returns (uint256[] memory) {
        return jobsByStatus[status];
    }

    /**
     * @notice Get all jobs submitted by a specific address
     * @param submitter Address of the job submitter
     * @return uint256[] Array of job IDs submitted by the address
     */
    function getJobsBySubmitter(address submitter) external view returns (uint256[] memory) {
        return submitterJobs[submitter];
    }

    /**
     * @dev Remove a job ID from its status array
     * @param jobId Job to remove
     * @param status Status array to remove from
     */
    function removeFromStatusArray(uint256 jobId, JobStatus status) private {
        uint256[] storage statusArray = jobsByStatus[status];
        for (uint256 i = 0; i < statusArray.length; i++) {
            if (statusArray[i] == jobId) {
                statusArray[i] = statusArray[statusArray.length - 1];
                statusArray.pop();
                break;
            }
        }
    }

    /**
     * @dev Validate if a status transition is allowed
     * @param from Current status
     * @param to New status
     * @return bool True if transition is valid
     */
    function isValidStatusTransition(JobStatus from, JobStatus to) private pure returns (bool) {
        if (from == JobStatus.NEW) {
            return to == JobStatus.ASSIGNED;
        }
        if (from == JobStatus.ASSIGNED) {
            return to == JobStatus.CONFIRMED;
        }
        if (from == JobStatus.CONFIRMED) {
            return to == JobStatus.COMPLETE;
        }
        return false;
    }
}