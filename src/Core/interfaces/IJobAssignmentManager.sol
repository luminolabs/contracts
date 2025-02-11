// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IJobAssignmentManager {
    event AssignmentRoundStarted(uint256 indexed epoch);
    event JobAssigned(uint256 indexed jobId, uint256 indexed nodeId);
    event JobConfirmed(uint256 indexed jobId, uint256 indexed nodeId);
    event JobCompleted(uint256 indexed jobId, uint256 indexed nodeId);
    event JobRejected(uint256 indexed jobId, uint256 indexed nodeId, string reason);

    function startAssignmentRound() external;
    function confirmJob(uint256 jobId) external;
    function rejectJob(uint256 jobId, string calldata reason) external;
    function getAssignedJobs(uint256 nodeId) external view returns (uint256[] memory);
    function isJobAssigned(uint256 jobId) external view returns (bool);
}