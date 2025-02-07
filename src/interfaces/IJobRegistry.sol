// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IJobRegistry {
    enum JobStatus { NEW, ASSIGNED, CONFIRMED, COMPLETE }

    struct Job {
        uint256 jobId;
        address submitter;
        uint256 assignedNode;
        JobStatus status;
        uint256 requiredPool;
        string jobArgs;
        uint256 createdAt;
    }

    event JobSubmitted(uint256 indexed jobId, address indexed submitter, uint256 requiredPool);
    event JobStatusUpdated(uint256 indexed jobId, JobStatus status);
    event JobAssigned(uint256 indexed jobId, uint256 indexed nodeId);

    function submitJob(string calldata jobArgs, uint256 requiredPool) external returns (uint256);
    function getJob(uint256 jobId) external view returns (Job memory);
    function getJobsByStatus(JobStatus status) external view returns (uint256[] memory);
    function getJobsBySubmitter(address submitter) external view returns (uint256[] memory);
    function updateJobStatus(uint256 jobId, JobStatus newStatus) external;
    function assignNode(uint256 jobId, uint256 nodeId) external;
}