// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {WhitelistControlled} from "./abstracts/WhitelistControlled.sol";
import {INodeRegistryCore} from "./interfaces/INodeRegistryCore.sol";
import {INodeStakingManager} from "./interfaces/INodeStakingManager.sol";
import {Nodes} from "./libraries/Nodes.sol";

/**
 * @title NodeRegistryCore
 * @dev Core contract for managing compute node registration and tracking in the Lumino network.
 * This contract maintains the registry of all compute nodes, their ownership, compute ratings,
 * and active status. It works in conjunction with the staking and whitelist systems to ensure
 * nodes meet participation requirements.
 *
 * Key features:
 * - Node registration with compute rating validation
 * - Node pool management for compute capacity grouping
 * - Node activity status tracking
 * - Ownership verification for node operations
 */
contract NodeRegistryCore is INodeRegistryCore, AccessControlled, WhitelistControlled {
    // Core contracts
    INodeStakingManager public immutable stakingManager;

    // State variables
    /// @notice Counter for generating unique node IDs
    uint256 private nodeCounter;
    /// @notice Mapping from node ID to node information
    mapping(uint256 => NodeInfo) private nodes;
    /// @notice Mapping from computing provider address to their node IDs
    mapping(address => uint256[]) private cpNodes;
    /// @notice Mapping from pool ID (compute rating) to node IDs in that pool
    mapping(uint256 => uint256[]) private poolNodes;

    // Custom errors
    error NodeNotFound(uint256 nodeId);
    error NodeNotActive(uint256 nodeId);
    error InsufficientStake(address cp, uint256 computeRating);

    /**
     * @dev Modifier to verify node exists
     * @param nodeId ID of the node to check
     */
    modifier nodeExists(uint256 nodeId) {
        if (nodes[nodeId].nodeId != nodeId) {
            revert NodeNotFound(nodeId);
        }
        _;
    }

    /**
     * @dev Constructor initializes core contract dependencies
     * @param _stakingManager Address of the NodeStakingManager contract
     * @param _whitelistManager Address of the WhitelistManager contract
     * @param _accessController Address of the AccessController contract
     */
    constructor(
        address _stakingManager,
        address _whitelistManager,
        address _accessController
    )
    AccessControlled(_accessController)
    WhitelistControlled(_whitelistManager)
    {
        stakingManager = INodeStakingManager(_stakingManager);
    }

    /**
     * @dev Register a new compute node
     * @param computeRating Compute rating indicating node's processing capacity
     * @return nodeId Unique identifier for the registered node
     *
     * Requirements:
     * - Computing provider must be whitelisted
     * - Computing provider must have sufficient stake for the compute rating
     *
     * Emits a {NodeRegistered} event
     */
    function registerNode(uint256 computeRating) external isWhitelisted returns (uint256) {
        if (!stakingManager.validateStake(msg.sender, computeRating)) {
            revert InsufficientStake(msg.sender, computeRating);
        }

        // TODO: Update stake requirement for CP in staking manager

        nodeCounter++;
        nodes[nodeCounter] = NodeInfo({
            cp: msg.sender,
            nodeId: nodeCounter,
            computeRating: computeRating,
            active: true
        });

        cpNodes[msg.sender].push(nodeCounter);
        poolNodes[computeRating].push(nodeCounter);

        emit NodeRegistered(msg.sender, nodeCounter, computeRating);
        return nodeCounter;
    }

    /**
     * @dev Unregister an existing node
     * @param nodeId ID of the node to unregister
     *
     * Requirements:
     * - Node must exist and be active
     * - Caller must be the node owner
     *
     * Emits a {NodeUnregistered} event
     */
    function unregisterNode(uint256 nodeId)
    external
    nodeExists(nodeId)
    {
        Nodes.validateNodeOwner(this, nodeId, msg.sender);
        if (!nodes[nodeId].active) {
            revert NodeNotActive(nodeId);
        }

        // TODO: Update stake requirement for CP in staking manager

        nodes[nodeId].active = false;

        // Remove from pool nodes
        uint256[] storage pool = poolNodes[nodes[nodeId].computeRating];
        for (uint256 i = 0; i < pool.length; i++) {
            if (pool[i] == nodeId) {
                pool[i] = pool[pool.length - 1];
                pool.pop();
                break;
            }
        }

        emit NodeUnregistered(msg.sender, nodeId);
    }

    /**
     * @dev Update node's compute rating
     * @param nodeId ID of the node to update
     * @param newComputeRating New compute rating value
     *
     * Requirements:
     * - Node must exist and be active
     * - Caller must be the node owner
     * - Computing provider must have sufficient stake for new rating
     *
     * Emits a {NodeUpdated} event
     */
    function updateNodeRating(
        uint256 nodeId,
        uint256 newComputeRating
    ) external nodeExists(nodeId) {
        Nodes.validateNodeOwner(this, nodeId, msg.sender);
        if (!nodes[nodeId].active) {
            revert NodeNotActive(nodeId);
        }
        if (!stakingManager.validateStake(msg.sender, newComputeRating)) {
            revert InsufficientStake(msg.sender, newComputeRating);
        }

        // TODO: Update stake requirement for CP in staking manager

        // Remove from old pool
        uint256 oldRating = nodes[nodeId].computeRating;
        uint256[] storage oldPool = poolNodes[oldRating];
        for (uint256 i = 0; i < oldPool.length; i++) {
            if (oldPool[i] == nodeId) {
                oldPool[i] = oldPool[oldPool.length - 1];
                oldPool.pop();
                break;
            }
        }

        // Add to new pool
        nodes[nodeId].computeRating = newComputeRating;
        poolNodes[newComputeRating].push(nodeId);

        emit NodeUpdated(nodeId, newComputeRating);
    }

    /**
     * @dev Get detailed information about a node
     * @param nodeId ID of the node to query
     * @return NodeInfo struct containing node details
     */
    function getNodeInfo(uint256 nodeId)
    external
    view
    nodeExists(nodeId)
    returns (NodeInfo memory)
    {
        return nodes[nodeId];
    }

    /**
     * @dev Get the owner (computing provider) of a node
     * @param nodeId ID of the node to query
     * @return address Owner's address
     */
    function getNodeOwner(uint256 nodeId)
    external
    view
    nodeExists(nodeId)
    returns (address)
    {
        return nodes[nodeId].cp;
    }

    /**
     * @dev Get all nodes in a specific compute rating pool
     * @param poolId Compute rating value defining the pool
     * @return uint256[] Array of node IDs in the pool
     */
    function getNodesInPool(uint256 poolId) external view returns (uint256[] memory) {
        return poolNodes[poolId];
    }

    /**
     * @dev Get all nodes owned by a computing provider
     * @param cp Address of the computing provider
     * @return uint256[] Array of node IDs owned by the CP
     */
    function getNodesByCP(address cp) external view returns (uint256[] memory) {
        return cpNodes[cp];
    }

    /**
     * @dev Check if a node is currently active
     * @param nodeId ID of the node to check
     * @return bool True if node is active, false otherwise
     */
    function isNodeActive(uint256 nodeId) external view nodeExists(nodeId) returns (bool) {
        return nodes[nodeId].active;
    }
}