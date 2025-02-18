// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IJobManager {
    // Enums
    enum JobStatus {NEW, ASSIGNED, CONFIRMED, COMPLETE}

    // Structs
    struct Job {
        uint256 id;
        address submitter;
        uint256 assignedNode;
        JobStatus status;
        uint256 requiredPool;
        mapping(string => string) args;
        uint256 tokenCount;
        uint256 createdAt;
    }

    // Errors
    error InvalidJobStatus(uint256 jobId, JobStatus currentStatus, JobStatus newStatus);
    error InvalidStatusTransition(JobStatus from, JobStatus to);
    error JobAlreadyProcessed(uint256 jobId);
    error JobNotComplete(uint256 jobId);
    error InvalidModelName(string modelName);
    error NoNewJobs();

    // Events
    event JobSubmitted(uint256 indexed jobId, address indexed submitter, uint256 requiredPool);
    event JobStatusUpdated(uint256 indexed jobId, JobStatus status);
    event JobAssigned(uint256 indexed jobId, uint256 indexed nodeId);
    event AssignmentRoundStarted(uint256 indexed epoch);
    event JobConfirmed(uint256 indexed jobId, uint256 indexed nodeId);
    event JobCompleted(uint256 indexed jobId, uint256 indexed nodeId);
    event JobRejected(uint256 indexed jobId, uint256 indexed nodeId, string reason);
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);

    // Job management functions
    function submitJob(string calldata jobArgs, uint256 requiredPool) external returns (uint256);
    function startAssignmentRound() external;
    function processPayment(uint256 jobId) external;
    function confirmJob(uint256 jobId) external;
    function completeJob(uint256 jobId) external;
    function rejectJob(uint256 jobId, string calldata reason) external;
    function wasAssignmentRoundStarted(uint256 epoch) external view returns (bool);
    function getUnconfirmedJobs(uint256 epoch) external view returns (uint256[] memory);
    function getAssignedNode(uint256 jobId) external view returns (uint256);
    function getNodeInactivityEpochs(uint256 nodeId) external view returns (uint256);
}