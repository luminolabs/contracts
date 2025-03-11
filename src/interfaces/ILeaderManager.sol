// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "./IEpochManager.sol";

interface ILeaderManager {
    // Events
    event CommitSubmitted(uint256 indexed epoch, uint256 indexed nodeId, address indexed owner);
    event SecretRevealed(uint256 indexed epoch, uint256 indexed nodeId, address indexed owner, bytes secret);
    event LeaderElected(uint256 indexed epoch, bytes32 randomValue, uint256 indexed leaderNodeId);

    // Errors
    error NoCommitmentFound(uint256 epoch, uint256 nodeId);
    error InvalidSecret(uint256 nodeId);
    error NoRevealsSubmitted(uint256 epoch);
    error MissingReveal(uint256 nodeId);
    error NotCurrentLeader(address caller, address leader);
    error NoRandomValueForEpoch(uint256 epoch);
    error LeaderAlreadyElected(uint256 epoch);

    // Leader election functions
    function submitCommitment(uint256 nodeId, bytes32 commitment) external;
    function revealSecret(uint256 nodeId, bytes calldata secret) external;
    function electLeader() external returns (uint256 leaderNodeId);
    function getCurrentLeader() external view returns (uint256);
    function getLeaderForEpoch(uint256 epoch) external view returns (uint256);
    function validateLeader(address caller) external view;
    function getFinalRandomValue(uint256 epoch) external view returns (bytes32);
    function getNodesWhoRevealed(uint256 epoch) external view returns (uint256[] memory);
}