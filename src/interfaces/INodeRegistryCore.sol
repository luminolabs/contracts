// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface INodeRegistryCore {
    struct NodeInfo {
        address cp;
        uint256 nodeId;
        uint256 computeRating;
        bool active;
    }

    event NodeRegistered(address indexed cp, uint256 nodeId, uint256 computeRating);
    event NodeUnregistered(address indexed cp, uint256 nodeId);
    event NodeUpdated(uint256 indexed nodeId, uint256 newComputeRating);

    function registerNode(uint256 computeRating) external returns (uint256);
    function unregisterNode(uint256 nodeId) external;
    function updateNodeRating(uint256 nodeId, uint256 newComputeRating) external;
    function getNodeInfo(uint256 nodeId) external view returns (NodeInfo memory);
    function getNodeOwner(uint256 nodeId) external view returns (address);
    function getNodesInPool(uint256 poolId) external view returns (uint256[] memory);
    function getNodesByCP(address cp) external view returns (uint256[] memory);
    function isNodeActive(uint256 nodeId) external view returns (bool);
}