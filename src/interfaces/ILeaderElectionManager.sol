// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILeaderElectionManager {
    event CommitSubmitted(uint256 indexed epoch, uint256 indexed nodeId, address nodeOwner);
    event SecretRevealed(uint256 indexed epoch, uint256 indexed nodeId, address nodeOwner, bytes secret);
    event LeaderElected(uint256 indexed epoch, bytes32 finalRandom, uint256 leaderNodeId);

    function submitCommitment(uint256 nodeId, bytes32 commitment) external;
    function revealSecret(uint256 nodeId, bytes calldata secret) external;
    function electLeader() external returns (uint256 leaderNodeId);
    function getCurrentLeader() external view returns (uint256);
    function getFinalRandomValue(uint256 epoch) external view returns (bytes32);
    function getCommitment(uint256 epoch, uint256 nodeId) external view returns (bytes32);
    function getReveal(uint256 epoch, uint256 nodeId) external view returns (bytes memory);
}