// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {INodeManager} from "./interfaces/INodeManager.sol";
import {INodeEscrow} from "./interfaces/INodeEscrow.sol";
import {IWhitelistManager} from "./interfaces/IWhitelistManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract NodeManager is Initializable, INodeManager {
    // Contracts
    INodeEscrow internal nodeEscrow;
    IWhitelistManager internal whitelistManager;
    IAccessManager internal accessManager;

    // State variables
    uint256 private nodeCounter;
    mapping(uint256 => NodeInfo) private nodes; // nodeId => NodeInfo
    mapping(address => uint256[]) private ownerNodes; // owner => array of nodeIds
    mapping(address => uint256) private stakeRequirements; // cp => total required stake
    mapping(uint256 => uint256[]) private computePools; // computeRating => array of nodeIds

    // New state for tracking compute pools
    mapping(uint256 => uint256) private poolNodeCount; // computeRating => number of active nodes
    mapping(uint256 => bool) private poolExists; // computeRating => exists flag
    uint256[] private activeComputePools; // Array of all active compute ratings

    function initialize(
        address _nodeEscrow,
        address _whitelistManager,
        address _accessManager
    ) external initializer {
        nodeEscrow = INodeEscrow(_nodeEscrow);
        whitelistManager = IWhitelistManager(_whitelistManager);
        accessManager = IAccessManager(_accessManager);
    }

    /**
     * @notice Registers a new node with the specified compute rating
     */
    function registerNode(uint256 computeRating) external returns (uint256) {
        whitelistManager.requireWhitelisted(msg.sender);

        uint256 requiredStake = computeRating * LShared.STAKE_PER_RATING;
        nodeEscrow.requireBalance(msg.sender, requiredStake);

        nodeCounter++;
        uint256 nodeId = nodeCounter;

        nodes[nodeId] = NodeInfo({
            cp: msg.sender,
            nodeId: nodeId,
            computeRating: computeRating
        });

        ownerNodes[msg.sender].push(nodeId);
        computePools[computeRating].push(nodeId);
        stakeRequirements[msg.sender] += requiredStake;

        // Update active compute pools
        if (!poolExists[computeRating]) {
            poolExists[computeRating] = true;
            activeComputePools.push(computeRating);
        }
        poolNodeCount[computeRating]++;

        emit NodeRegistered(msg.sender, nodeId, computeRating);
        emit StakeRequirementUpdated(msg.sender, stakeRequirements[msg.sender]);

        return nodeId;
    }

    /**
     * @notice Unregisters an existing node
     */
    function unregisterNode(uint256 nodeId) external {
        validateNodeOwner(nodeId, msg.sender);

        NodeInfo memory node = nodes[nodeId];
        if (node.nodeId == 0) {
            revert NodeNotFound(nodeId);
        }

        // Remove from ownerNodes
        removeFromArray(ownerNodes[msg.sender], nodeId);

        // Remove from computePools
        removeFromArray(computePools[node.computeRating], nodeId);

        // Update stake requirements
        uint256 stakeReduction = node.computeRating * LShared.STAKE_PER_RATING;
        stakeRequirements[msg.sender] -= stakeReduction;

        // Update active compute pools
        poolNodeCount[node.computeRating]--;
        if (poolNodeCount[node.computeRating] == 0) {
            poolExists[node.computeRating] = false;
            removeFromArray(activeComputePools, node.computeRating);
        }

        delete nodes[nodeId];

        emit NodeUnregistered(msg.sender, nodeId);
        emit StakeRequirementUpdated(msg.sender, stakeRequirements[msg.sender]);
    }

    /**
     * @notice Gets all nodes in a specific compute pool
     */
    function getNodesInPool(uint256 poolId) external view returns (uint256[] memory) {
        return computePools[poolId];
    }

    /**
     * @notice Gets all active compute pools
     * @return Array of active compute ratings
     */
    function getAllComputePools() external view returns (uint256[] memory) {
        return activeComputePools;
    }

    /**
     * @notice Gets the owner of a specific node
     */
    function getNodeOwner(uint256 nodeId) external view returns (address) {
        NodeInfo memory node = nodes[nodeId];
        if (node.nodeId == 0) {
            revert NodeNotFound(nodeId);
        }
        return node.cp;
    }

    /**
     * @notice Gets detailed information about a node
     */
    function getNodeInfo(uint256 nodeId) external view returns (NodeInfo memory) {
        NodeInfo memory node = nodes[nodeId];
        if (node.nodeId == 0) {
            revert NodeNotFound(nodeId);
        }
        return node;
    }

    /**
     * @notice Validates that the sender owns the specified node
     */
    function validateNodeOwner(uint256 nodeId, address sender) public view {
        NodeInfo memory node = nodes[nodeId];
        if (node.nodeId == 0) {
            revert NodeNotFound(nodeId);
        }
        if (node.cp != sender) {
            revert InvalidNodeOwner(nodeId, sender);
        }
    }

    /**
     * @notice Gets the total stake requirement for a computing provider
     */
    function getStakeRequirement(address cp) external view returns (uint256) {
        return stakeRequirements[cp];
    }

    /**
     * @notice Internal helper function to remove an element from an array
     */
    function removeFromArray(uint256[] storage array, uint256 value) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }
}