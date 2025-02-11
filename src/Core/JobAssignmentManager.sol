// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {IJobAssignmentManager} from "./interfaces/IJobAssignmentManager.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {ILeaderElectionManager} from "./interfaces/ILeaderElectionManager.sol";
import {INodeRegistryCore} from "./interfaces/INodeRegistryCore.sol";
import {Epoch} from "./libraries/Epoch.sol";

/**
 * @title JobAssignmentManager
 * @dev Manages the assignment of jobs to compute nodes in the network.
 * This contract handles the fair distribution of jobs based on node capacity
 * and randomized selection using entropy from the leader election process.
 *
 * Key responsibilities:
 * - Starting assignment rounds during EXECUTE phase
 * - Assigning jobs to eligible nodes based on capacity and random selection
 * - Managing job confirmation and rejection by assigned nodes
 * - Tracking node assignments and job status
 */
contract JobAssignmentManager is IJobAssignmentManager {
    // Core contracts for job and node management
    IJobRegistry public immutable jobRegistry;
    INodeRegistryCore public immutable nodeRegistry;
    ILeaderElectionManager public immutable leaderManager;
    IEpochManager public immutable epochManager;

    // Track assignments and constraints
    mapping(uint256 => uint256[]) private nodeAssignments; // nodeId => jobIds
    mapping(uint256 => bool) private jobAssigned; // jobId => assigned status

    // Assignment configuration
    uint256 public maxJobsPerNode;
    uint256 public assignmentTimeout;

    /**
     * @dev Constructor initializes core contract references and assignment parameters
     * @param _jobRegistry Address of the JobRegistry contract
     * @param _nodeRegistry Address of the NodeRegistryCore contract
     * @param _leaderManager Address of the LeaderElectionManager contract
     * @param _epochManager Address of the EpochManager contract
     * @param _assignmentTimeout Duration before an unconfirmed assignment expires
     */
    constructor(
        address _jobRegistry,
        address _nodeRegistry,
        address _leaderManager,
        address _epochManager,
        uint256 _assignmentTimeout
    ) {
        jobRegistry = IJobRegistry(_jobRegistry);
        nodeRegistry = INodeRegistryCore(_nodeRegistry);
        leaderManager = ILeaderElectionManager(_leaderManager);
        epochManager = IEpochManager(_epochManager);
        maxJobsPerNode = 1;
        assignmentTimeout = _assignmentTimeout;
    }

    /**
     * @dev Initiates a new assignment round for unassigned jobs
     * @notice Can only be called by the current leader during EXECUTE phase
     * Uses random entropy from leader election to ensure fair job distribution
     * Assigns jobs based on node capacity and pool requirements
     * Emits JobAssigned events for each successful assignment
     */
    function startAssignmentRound() external {
        Epoch.validateState(Epoch.State.EXECUTE, epochManager);
        validateLeader();

        uint256[] memory newJobs = jobRegistry.getJobsByStatus(IJobRegistry.JobStatus.NEW);
        bytes32 randomSeed = leaderManager.getFinalRandomValue(epochManager.getCurrentEpoch());

        for (uint256 i = 0; i < newJobs.length; i++) {
            uint256 jobId = newJobs[i];
            IJobRegistry.Job memory job = jobRegistry.getJob(jobId);

            // Get eligible nodes
            uint256[] memory nodesInPool = nodeRegistry.getNodesInPool(job.requiredPool);
            if (nodesInPool.length == 0) continue;

            // Filter nodes by capacity
            uint256[] memory eligibleNodes = filterEligibleNodes(nodesInPool);
            if (eligibleNodes.length == 0) continue;

            // Select node using random seed
            uint256 selectedIndex = uint256(keccak256(abi.encodePacked(randomSeed, jobId))) % eligibleNodes.length;
            uint256 selectedNode = eligibleNodes[selectedIndex];

            // Assign job
            jobRegistry.assignNode(jobId, selectedNode);
            nodeAssignments[selectedNode].push(jobId);
            jobAssigned[jobId] = true;

            emit JobAssigned(jobId, selectedNode);
        }

        emit AssignmentRoundStarted(epochManager.getCurrentEpoch());
    }

    /**
     * @dev Allows a node to confirm acceptance of an assigned job
     * @param jobId Identifier of the job to confirm
     * @notice Can only be called by the owner of the assigned node
     * @notice Must be called within assignment timeout period
     * Updates job status to CONFIRMED in the job registry
     */
    function confirmJob(uint256 jobId) external {
        IJobRegistry.Job memory job = jobRegistry.getJob(jobId);
        require(job.status == IJobRegistry.JobStatus.ASSIGNED, "JobAssignmentManager: Job not assigned");
        validateNodeOwner(job);
        Epoch.validateState(Epoch.State.CONFIRM, epochManager);

        jobRegistry.updateJobStatus(jobId, IJobRegistry.JobStatus.CONFIRMED);
        emit JobConfirmed(jobId, job.assignedNode);
    }

    /**
     * @dev Allows a node to mark a confirmed job as complete
     * @param jobId Identifier of the job to complete
     * @notice Can only be called by the owner of the assigned node
     * Updates job status to COMPLETE in the job registry
     */
    function completeJob(uint256 jobId) external {
        IJobRegistry.Job memory job = jobRegistry.getJob(jobId);
        require(job.status == IJobRegistry.JobStatus.CONFIRMED, "JobAssignmentManager: Job not confirmed");
        validateNodeOwner(job);
        Epoch.validateState(Epoch.State.CONFIRM, epochManager);

        jobRegistry.updateJobStatus(jobId, IJobRegistry.JobStatus.COMPLETE);
        emit JobCompleted(jobId, job.assignedNode);
    }

    /**
     * @dev Allows a node to reject an assigned job
     * @param jobId Identifier of the job to reject
     * @param reason String explanation for the rejection
     * @notice Can only be called by the owner of the assigned node
     * Resets job status to NEW and removes assignment tracking
     */
    function rejectJob(uint256 jobId, string calldata reason) external {
        IJobRegistry.Job memory job = jobRegistry.getJob(jobId);
        require(job.status == IJobRegistry.JobStatus.ASSIGNED, "JobAssignmentManager: Job not assigned");
        validateNodeOwner(job);
        Epoch.validateState(Epoch.State.CONFIRM, epochManager);

        // Reset job status
        jobRegistry.updateJobStatus(jobId, IJobRegistry.JobStatus.NEW);
        jobAssigned[jobId] = false;

        // Remove from node assignments
        uint256[] storage assignments = nodeAssignments[job.assignedNode];
        for (uint256 i = 0; i < assignments.length; i++) {
            if (assignments[i] == jobId) {
                assignments[i] = assignments[assignments.length - 1];
                assignments.pop();
                break;
            }
        }

        emit JobRejected(jobId, job.assignedNode, reason);
    }

    /**
     * @dev Returns all jobs currently assigned to a node
     * @param nodeId Identifier of the node to query
     * @return Array of job IDs assigned to the node
     */
    function getAssignedJobs(uint256 nodeId) external view returns (uint256[] memory) {
        return nodeAssignments[nodeId];
    }

    /**
     * @dev Checks if a job is currently assigned
     * @param jobId Identifier of the job to check
     * @return bool True if the job is assigned, false otherwise
     */
    function isJobAssigned(uint256 jobId) external view returns (bool) {
        return jobAssigned[jobId];
    }

    /**
     * @dev Internal helper to filter nodes based on capacity
     * @param nodes Array of node IDs to filter
     * @return Array of node IDs that have available capacity
     */
    function filterEligibleNodes(uint256[] memory nodes) internal view returns (uint256[] memory) {
        uint256 eligibleCount = 0;

        // First pass: count eligible nodes
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodeAssignments[nodes[i]].length < maxJobsPerNode) {
                eligibleCount++;
            }
        }

        // Second pass: create filtered array
        uint256[] memory eligibleNodes = new uint256[](eligibleCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodeAssignments[nodes[i]].length < maxJobsPerNode) {
                eligibleNodes[currentIndex] = nodes[i];
                currentIndex++;
            }
        }

        return eligibleNodes;
    }

    /**
     * @dev Validates that the caller is the owner of the node currently elected as leader
     */
    function validateLeader() internal view {
        require(
            nodeRegistry.getNodeOwner(leaderManager.getCurrentLeader()) == msg.sender,
            "JobAssignmentManager: Not current leader"
        );
    }

    /**
     * @dev Validates that the caller is the owner of the assigned node for a job
     * @param job Job to validate
     */
    function validateNodeOwner(IJobRegistry.Job memory job) internal view {
        require(
            nodeRegistry.getNodeOwner(job.assignedNode) == msg.sender,
            "JobAssignmentManager: Not assigned node owner"
        );
    }
}