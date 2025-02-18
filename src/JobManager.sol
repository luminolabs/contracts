// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {IJobEscrow} from "./interfaces/IJobEscrow.sol";
import {IJobManager} from "./interfaces/IJobManager.sol";
import {ILeaderManager} from "./interfaces/ILeaderManager.sol";
import {INodeManager} from "./interfaces/INodeManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract JobManager is IJobManager {
    // Contracts
    INodeManager private immutable nodeManager;
    ILeaderManager private immutable leaderManager;
    IEpochManager private immutable epochManager;
    IJobEscrow private immutable jobEscrow;
    IAccessManager private immutable accessController;

    // State variables
    uint256 private jobCounter;
    mapping(uint256 => Job) private jobs;
    mapping(JobStatus => uint256[]) private jobsByStatus;
    mapping(uint256 => uint256[]) private assignedJobsByEpoch;
    mapping(address => uint256[]) private submitterJobs;
    mapping(uint256 => uint256[]) private nodeAssignments;
    mapping(uint256 => bool) private jobAssigned;
    mapping(uint256 => bool) private processedJobs;
    mapping(address => uint256) private lastWithdrawal;
    mapping(uint256 => bool) private assignmentRoundStarted;

    // Constants
    uint256 private constant MAX_JOBS_PER_NODE = 1;

    /**
     * @notice Initializes the JobManager contract
     */
    constructor(
        address _nodeManager,
        address _leaderManager,
        address _epochManager,
        address _jobEscrow,
        address _accessController
    ) {
        nodeManager = INodeManager(_nodeManager);
        leaderManager = ILeaderManager(_leaderManager);
        epochManager = IEpochManager(_epochManager);
        jobEscrow = IJobEscrow(_jobEscrow);
        accessController = IAccessManager(_accessController);
    }

    function submitJob(
        string calldata jobArgs,
        uint256 requiredPool
    ) external returns (uint256) {
        jobEscrow.requireBalance(msg.sender, LShared.MIN_BALANCE_TO_SUBMIT);

        jobCounter++;
        uint256 jobId = jobCounter;

        // Initialize struct fields individually
        Job storage job = jobs[jobId];
        job.id = jobId;
        job.submitter = msg.sender;
        job.assignedNode = 0;
        job.status = JobStatus.NEW;
        job.requiredPool = requiredPool;
        job.args["base_model_name"] = jobArgs;
        job.tokenCount = 0;
        job.createdAt = block.timestamp;

        jobsByStatus[JobStatus.NEW].push(jobId);
        submitterJobs[msg.sender].push(jobId);

        emit JobSubmitted(jobId, msg.sender, requiredPool);
        return jobId;
    }

    /**
     * @notice Start a new assignment round
     */
    function startAssignmentRound() external {
        epochManager.validateEpochState(IEpochManager.State.EXECUTE);
        leaderManager.validateLeader(msg.sender);

        uint256[] memory newJobs = jobsByStatus[JobStatus.NEW];
        if (newJobs.length == 0) {
            revert NoNewJobs();
        }

        bytes32 randomSeed = leaderManager.getFinalRandomValue(epochManager.getCurrentEpoch());

        for (uint256 i = 0; i < newJobs.length; i++) {
            uint256 jobId = newJobs[i];
            Job storage job = jobs[jobId];

            uint256[] memory nodesInPool = nodeManager.getNodesInPool(job.requiredPool);
            if (nodesInPool.length == 0) continue;

            uint256[] memory eligibleNodes = filterEligibleNodes(nodesInPool);
            if (eligibleNodes.length == 0) continue;

            uint256 selectedIndex = uint256(keccak256(abi.encodePacked(randomSeed, jobId))) % eligibleNodes.length;
            uint256 selectedNode = eligibleNodes[selectedIndex];

            assignNodeToJob(jobId, selectedNode);
        }

        emit AssignmentRoundStarted(epochManager.getCurrentEpoch());
    }

    /**
     * @notice Process payment for a completed job
     */
    function processPayment(uint256 jobId) external {
        if (processedJobs[jobId]) {
            revert JobAlreadyProcessed(jobId);
        }

        Job storage job = jobs[jobId];
        if (job.status != JobStatus.COMPLETE) {
            revert JobNotComplete(jobId);
        }

        address nodeOwner = nodeManager.getNodeOwner(job.assignedNode);
        uint256 payment = calculateJobPayment(job);

        jobEscrow.releasePayment(job.submitter, nodeOwner, payment);
        processedJobs[jobId] = true;
        emit PaymentProcessed(jobId, nodeOwner, payment);
    }

    /**
     * @notice Set the number of tokens required for a job
     */
    function setTokenCountForJob(uint256 jobId, uint256 numTokens) external {
        Job storage job = jobs[jobId];
        nodeManager.validateNodeOwner(job.assignedNode, msg.sender);
        job.tokenCount = numTokens;
    }

    /**
     * @notice Confirm an assigned job
     */
    function confirmJob(uint256 jobId) external {
        Job storage job = jobs[jobId];
        if (job.status != JobStatus.ASSIGNED) {
            revert InvalidJobStatus(jobId, job.status, JobStatus.ASSIGNED);
        }
        nodeManager.validateNodeOwner(job.assignedNode, msg.sender);
        epochManager.validateEpochState(IEpochManager.State.CONFIRM);

        updateJobStatus(jobId, JobStatus.CONFIRMED);
        emit JobConfirmed(jobId, job.assignedNode);
    }

    /**
     * @notice Complete a confirmed job
     */
    function completeJob(uint256 jobId) external {
        Job storage job = jobs[jobId];
        if (job.status != JobStatus.CONFIRMED) {
            revert InvalidJobStatus(jobId, job.status, JobStatus.CONFIRMED);
        }
        nodeManager.validateNodeOwner(job.assignedNode, msg.sender);
        epochManager.validateEpochState(IEpochManager.State.CONFIRM);

        updateJobStatus(jobId, JobStatus.COMPLETE);
        emit JobCompleted(jobId, job.assignedNode);
    }

    /**
     * @notice Reject an assigned job
     */
    function rejectJob(uint256 jobId, string calldata reason) external {
        Job storage job = jobs[jobId];
        if (job.status != JobStatus.ASSIGNED) {
            revert InvalidJobStatus(jobId, job.status, JobStatus.ASSIGNED);
        }
        nodeManager.validateNodeOwner(job.assignedNode, msg.sender);
        epochManager.validateEpochState(IEpochManager.State.CONFIRM);

        uint256 nodeId = job.assignedNode;
        resetJobAssignment(jobId);
        emit JobRejected(jobId, nodeId, reason);
    }

    /**
     * @notice Checks if an assignment round was started for a given epoch
     */
    function wasAssignmentRoundStarted(uint256 epoch) external view returns (bool) {
        return assignmentRoundStarted[epoch];
    }

    /**
     * @notice Returns a list of unconfirmed jobs for a given epoch
     */
    function getUnconfirmedJobs(uint256 epoch) external view returns (uint256[] memory) {
        uint256[] memory assignedJobs = assignedJobsByEpoch[epoch];
        uint256[] memory confirmedJobs = jobsByStatus[JobStatus.CONFIRMED];

        // First, count unconfirmed jobs
        uint256 unconfirmedCount = 0;
        for (uint256 i = 0; i < assignedJobs.length; i++) {
            bool isConfirmed = false;
            for (uint256 j = 0; j < confirmedJobs.length; j++) {
                if (assignedJobs[i] == confirmedJobs[j]) {
                    isConfirmed = true;
                    break;
                }
            }
            if (!isConfirmed) {
                unconfirmedCount++;
            }
        }

        // Create fixed-size array and populate it
        uint256[] memory unconfirmedJobs = new uint256[](unconfirmedCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < assignedJobs.length; i++) {
            bool isConfirmed = false;
            for (uint256 j = 0; j < confirmedJobs.length; j++) {
                if (assignedJobs[i] == confirmedJobs[j]) {
                    isConfirmed = true;
                    break;
                }
            }
            if (!isConfirmed) {
                unconfirmedJobs[currentIndex] = assignedJobs[i];
                currentIndex++;
            }
        }

        return unconfirmedJobs;
    }

    /**
     * @notice Returns the node assigned to a job
     */
    function getAssignedNode(uint256 jobId) external view returns (uint256) {
        return jobs[jobId].assignedNode;
    }

    /**
     * @notice Returns the number of epochs a node has been inactive (did not reveal)
     */
    function getNodeInactivityEpochs(uint256 nodeId) external view returns (uint256) {
        // See if node is running a job
        uint256[] memory confirmedJobs = jobsByStatus[JobStatus.CONFIRMED];
        for (uint256 i = 0; i < confirmedJobs.length; i++) {
            if (jobs[confirmedJobs[i]].assignedNode == nodeId) {
                // Node is active since it's running a job
                return 0;
            }
        }

        // Node is not running a job, see when it last revealed
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        uint256 epochLimit = 30;  // Only look back this many epochs
        for (uint256 i = currentEpoch; i > currentEpoch - epochLimit; i--) {
            uint256[] memory revealedNodes = leaderManager.getNodesWhoRevealed(i);
            for (uint256 j = 0; j < revealedNodes.length; j++) {
                if (revealedNodes[j] == nodeId) {
                    // Node was last active in this epoch
                    return currentEpoch - i;
                }
            }
        }

        // Node has not revealed in the last epochLimit epochs, so consider it inactive for all of them
        return epochLimit;
    }

    // Internal functions


    function calculateJobPayment(Job storage job) internal view returns (uint256) {
        uint256 modelFeePerMillionTokens = 0;
        string memory model_name = job.args["base_model_name"];
        if (keccak256(abi.encodePacked(model_name)) == keccak256(abi.encodePacked("llm_llama3_2_1b"))) {
            modelFeePerMillionTokens = 1;
        } else if (keccak256(abi.encodePacked(model_name)) == keccak256(abi.encodePacked("llm_llama3_1_8b"))) {
            modelFeePerMillionTokens = 2;
        } else {
            revert InvalidModelName(model_name);
        }

        uint256 tokensInMillions = job.tokenCount / 1e6;
        return modelFeePerMillionTokens * tokensInMillions;
    }

    function assignNodeToJob(uint256 jobId, uint256 nodeId) internal {
        Job storage job = jobs[jobId];

        removeFromStatusArray(jobId, JobStatus.NEW);

        job.assignedNode = nodeId;
        job.status = JobStatus.ASSIGNED;

        nodeAssignments[nodeId].push(jobId);
        jobAssigned[jobId] = true;
        jobsByStatus[JobStatus.ASSIGNED].push(jobId);
        assignedJobsByEpoch[epochManager.getCurrentEpoch()].push(jobId);

        emit JobAssigned(jobId, nodeId);
    }

    function updateJobStatus(uint256 jobId, JobStatus newStatus) internal {
        Job storage job = jobs[jobId];
        JobStatus currentStatus = job.status;

        if (!isValidStatusTransition(currentStatus, newStatus)) {
            revert InvalidStatusTransition(currentStatus, newStatus);
        }

        removeFromStatusArray(jobId, currentStatus);
        job.status = newStatus;
        jobsByStatus[newStatus].push(jobId);

        emit JobStatusUpdated(jobId, newStatus);
    }

    function resetJobAssignment(uint256 jobId) internal {
        Job storage job = jobs[jobId];
        uint256 nodeId = job.assignedNode;

        removeFromStatusArray(jobId, job.status);
        job.status = JobStatus.NEW;
        job.assignedNode = 0;
        jobAssigned[jobId] = false;
        jobsByStatus[JobStatus.NEW].push(jobId);

        uint256[] storage assignments = nodeAssignments[nodeId];
        for (uint256 i = 0; i < assignments.length; i++) {
            if (assignments[i] == jobId) {
                assignments[i] = assignments[assignments.length - 1];
                assignments.pop();
                break;
            }
        }
    }

    function removeFromStatusArray(uint256 jobId, JobStatus status) internal {
        uint256[] storage statusArray = jobsByStatus[status];
        for (uint256 i = 0; i < statusArray.length; i++) {
            if (statusArray[i] == jobId) {
                statusArray[i] = statusArray[statusArray.length - 1];
                statusArray.pop();
                break;
            }
        }
    }

    function filterEligibleNodes(uint256[] memory nodes) internal view returns (uint256[] memory) {
        uint256[] memory nodesWhoRevealed = leaderManager.getNodesWhoRevealed(epochManager.getCurrentEpoch());

        // Get the intersection of nodes and nodesWhoRevealed
        uint256[] memory revealedNodes = new uint256[](nodesWhoRevealed.length);
        uint256 revealedCount = 0;
        for (uint256 i = 0; i < nodes.length; i++) {
            for (uint256 j = 0; j < nodesWhoRevealed.length; j++) {
                if (nodes[i] == nodesWhoRevealed[j]) {
                    revealedNodes[revealedCount] = nodes[i];
                    break;
                }
            }
        }

        uint256 eligibleCount = 0;
        for (uint256 i = 0; i < revealedNodes.length; i++) {
            if (nodeAssignments[revealedNodes[i]].length < MAX_JOBS_PER_NODE) {
                eligibleCount++;
            }
        }

        uint256[] memory eligibleNodes = new uint256[](eligibleCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < revealedNodes.length; i++) {
            if (nodeAssignments[revealedNodes[i]].length < MAX_JOBS_PER_NODE) {
                eligibleNodes[currentIndex] = revealedNodes[i];
                currentIndex++;
            }
        }

        return eligibleNodes;
    }

    function isValidStatusTransition(JobStatus from, JobStatus to) internal pure returns (bool) {
        if (from == JobStatus.NEW) return to == JobStatus.ASSIGNED;
        if (from == JobStatus.ASSIGNED) return to == JobStatus.CONFIRMED;
        if (from == JobStatus.CONFIRMED) return to == JobStatus.COMPLETE;
        return false;
    }
}