// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface INodeManager {
    // Structs
    struct NodeInfo {
        address cp;
        uint256 nodeId;
        uint256 computeRating;
    }

    // Events
    event NodeRegistered(address indexed cp, uint256 nodeId, uint256 computeRating);
    event NodeUnregistered(address indexed cp, uint256 nodeId);
    event NodeUpdated(uint256 indexed nodeId, uint256 newComputeRating);
    event StakeValidated(address indexed cp, uint256 computeRating, bool isValid);
    event StakeRequirementUpdated(address indexed cp, uint256 newRequirement);

    // Errors
    error NodeNotFound(uint256 nodeId);
    error NodeNotActive(uint256 nodeId);
    error InsufficientStake(address cp, uint256 computeRating);
    error InvalidNodeOwner(uint256 nodeId, address sender);

    // Node management functions
    function registerNode(uint256 computeRating) external returns (uint256);
    function unregisterNode(uint256 nodeId) external;
    function getNodesInPool(uint256 poolId) external view returns (uint256[] memory);
    function getNodeOwner(uint256 nodeId) external view returns (address);
    function getNodeInfo(uint256 nodeId) external view returns (NodeInfo memory);
    function validateNodeOwner(uint256 nodeId, address sender) external view;
    function getStakeRequirement(address cp) external view returns (uint256);
    function getAllComputePools() external view returns (uint256[] memory);
}