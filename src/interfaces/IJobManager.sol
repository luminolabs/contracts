// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IJobManager {
    // Enums
    enum JobStatus {NEW, ASSIGNED, CONFIRMED, COMPLETE, FAILED}

    // Structs
    struct Job {
        uint256 id;
        address submitter;
        uint256 assignedNode;
        JobStatus status;
        uint256 requiredPool;
        string args;
        string baseModelName;  // TODO: Make configurable enum
        string ftType;  // TODO: Make configurable enum
        uint256 tokenCount;
        uint256 createdAt;
    }

    // Errors
    error InvalidStatusTransition(JobStatus from, JobStatus to);
    error JobAlreadyProcessed(uint256 jobId);
    error JobNotComplete(uint256 jobId);
    error InvalidModelName(string modelName);

    // Events
    event JobSubmitted(uint256 indexed jobId, address indexed submitter, uint256 requiredPool);
    event JobStatusUpdated(uint256 indexed jobId, JobStatus status);
    event JobAssigned(uint256 indexed jobId, uint256 indexed nodeId);
    event AssignmentRoundStarted(uint256 indexed epoch);
    event JobTokensSet(uint256 indexed jobId, uint256 numTokens);
    event JobConfirmed(uint256 indexed jobId, uint256 indexed nodeId);
    event JobCompleted(uint256 indexed jobId, uint256 indexed nodeId);
    event JobFailed(uint256 indexed jobId, uint256 indexed nodeId, string reason);
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);

    // Job management functions
    function submitJob(string calldata jobArgs, string calldata baseModelName, string calldata ftType) external returns (uint256);
    function startAssignmentRound() external;
    function processPayment(uint256 jobId) external;
    function setTokenCountForJob(uint256 jobId, uint256 numTokens) external;
    function confirmJob(uint256 jobId) external;
    function completeJob(uint256 jobId) external;
    function failJob(uint256 jobId, string calldata reason) external;
    function wasAssignmentRoundStarted(uint256 epoch) external view returns (bool);
    function getUnconfirmedJobs(uint256 epoch) external view returns (uint256[] memory);
    function getAssignedNode(uint256 jobId) external view returns (uint256);
    function getNodeInactivityEpochs(uint256 nodeId) external view returns (uint256);
    function getJobsDetailsByNode(uint256 nodeId) external view returns (Job[] memory);
    function getJobStatus(uint256 jobId) external view returns (JobStatus);
    function getJobDetails(uint256 jobId) external view returns (Job memory);
    function getJobsBySubmitter(address submitter) external view returns (uint256[] memory);
}