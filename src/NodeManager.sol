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
    INodeEscrow public nodeEscrow;
    IAccessManager private accessManager;
    IWhitelistManager private whitelistManager;

    // State variables
    uint256 private nodeCounter;
    mapping(uint256 => NodeInfo) private nodes;
    mapping(address => uint256[]) private cpNodes;
    mapping(uint256 => uint256[]) private poolNodes;
    mapping(address => uint256) private cpStakeRequirements;

    /**
     * @notice Initializes the NodeManager contract
     */
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
     * @notice Register a new compute node
     */
    function registerNode(uint256 computeRating) external returns (uint256) {
        // Validate whitelist and stake
        whitelistManager.requireWhitelisted(msg.sender);
        validateStake(msg.sender, computeRating);

        // Create new node
        nodeCounter++;
        nodes[nodeCounter] = NodeInfo({
            cp: msg.sender,
            nodeId: nodeCounter,
            computeRating: computeRating
        });

        // Update mappings
        cpNodes[msg.sender].push(nodeCounter);
        poolNodes[computeRating].push(nodeCounter);

        // Update stake requirements
        uint256 newRequirement = cpStakeRequirements[msg.sender] + calculateStakeForRating(computeRating);
        cpStakeRequirements[msg.sender] = newRequirement;
        emit StakeRequirementUpdated(msg.sender, newRequirement);

        emit NodeRegistered(msg.sender, nodeCounter, computeRating);
        return nodeCounter;
    }

    function unregisterNode(uint256 nodeId) external {
        // Validate node ownership
        validateNodeOwner(nodeId, msg.sender);

        // Get node info
        NodeInfo memory node = nodes[nodeId];

        // Remove node from CP's list
        uint256[] storage cpNodeList = cpNodes[msg.sender];
        for (uint256 i = 0; i < cpNodeList.length; i++) {
            if (cpNodeList[i] == nodeId) {
                cpNodeList[i] = cpNodeList[cpNodeList.length - 1];
                cpNodeList.pop();
                break;
            }
        }

        // Remove node from pool's list
        uint256[] storage poolNodeList = poolNodes[node.computeRating];
        for (uint256 i = 0; i < poolNodeList.length; i++) {
            if (poolNodeList[i] == nodeId) {
                poolNodeList[i] = poolNodeList[poolNodeList.length - 1];
                poolNodeList.pop();
                break;
            }
        }

        // Update stake requirements
        uint256 newRequirement = cpStakeRequirements[msg.sender] - calculateStakeForRating(node.computeRating);
        cpStakeRequirements[msg.sender] = newRequirement;
        emit StakeRequirementUpdated(msg.sender, newRequirement);

        emit NodeUnregistered(msg.sender, nodeId);
    }

    /**
     * @notice Gets all nodes in a pool
     */
    function getNodesInPool(uint256 poolId) external view returns (uint256[] memory) {
        return poolNodes[poolId];
    }

    /**
     * @notice Gets the owner of a node
     */
    function getNodeOwner(uint256 nodeId) public view returns (address) {
        return nodes[nodeId].cp;
    }

    /**
     * @notice Validates if a caller is the owner of a node
     */
    function validateNodeOwner(uint256 nodeId, address caller) public view {
        if (getNodeOwner(nodeId) != caller) {
            revert InvalidNodeOwner(nodeId, caller);
        }
    }

    function getStakeRequirement(address cp) external view returns (uint256) {
        return cpStakeRequirements[cp];
    }

    function getNodeInfo(uint256 nodeId) external view returns (NodeInfo memory) {
        return nodes[nodeId];
    }

    // Internal functions

    /**
     * @notice Calculates the required stake for a given node's compute rating
     */
    function calculateStakeForRating(uint256 computeRating) internal pure returns (uint256) {
        uint256 stake = computeRating * LShared.STAKE_PER_RATING;
        if (stake == 0) {
            stake = LShared.MIN_DEPOSIT;
        }
        return stake;
    }

    /**
     * @notice Validates if a CP has sufficient stake for a given compute rating
     */
    function validateStake(address cp, uint256 computeRating) internal view {
        uint256 currentRequirement = cpStakeRequirements[cp];
        uint256 newRequirement = computeRating * LShared.STAKE_PER_RATING;
        uint256 totalRequired = currentRequirement + newRequirement;

        nodeEscrow.requireBalance(cp, totalRequired);
    }
}