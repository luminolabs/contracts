// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {ILeaderManager} from "./interfaces/ILeaderManager.sol";
import {INodeManager} from "./interfaces/INodeManager.sol";
import {INodeEscrow} from "./interfaces/INodeEscrow.sol";
import {IWhitelistManager} from "./interfaces/IWhitelistManager.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract LeaderManager is Initializable, ILeaderManager {
    // Contracts
    IEpochManager public epochManager;
    INodeManager public nodeManager;
    INodeEscrow public nodeEscrow;
    IAccessManager public accessManager;
    IWhitelistManager public whitelistManager;

    // State variables
    mapping(uint256 => mapping(uint256 => bytes32)) private nodeCommitments;
    mapping(uint256 => mapping(uint256 => bytes)) private nodeReveals;
    mapping(uint256 => uint256[]) private nodeRevealsList;
    mapping(uint256 => bytes32) private finalRandomValues;
    mapping(uint256 => uint256) private epochLeaders;

    /**
     * @notice Initializes the LeaderManager contract
     */
    function initialize(
        address _epochManager,
        address _nodeManager,
        address _nodeEscrow,
        address _accessManager,
        address _whitelistManager
    ) external initializer {
        epochManager = IEpochManager(_epochManager);
        nodeManager = INodeManager(_nodeManager);
        nodeEscrow = INodeEscrow(_nodeEscrow);
        accessManager = IAccessManager(_accessManager);
        whitelistManager = IWhitelistManager(_whitelistManager);
    }

    /**
     * @notice Submit a commitment for the current epoch
     */
    function submitCommitment(uint256 nodeId, bytes32 commitment) external {
        nodeManager.validateNodeOwner(nodeId, msg.sender);
        epochManager.validateEpochState(IEpochManager.State.COMMIT);
        validateStakeAndWhitelist(msg.sender);


        uint256 currentEpoch = epochManager.getCurrentEpoch();
        nodeCommitments[currentEpoch][nodeId] = commitment;

        emit CommitSubmitted(currentEpoch, nodeId, msg.sender);
    }

    /**
     * @notice Reveal the secret for a node
     */
    function revealSecret(uint256 nodeId, bytes calldata secret) external {
        nodeManager.validateNodeOwner(nodeId, msg.sender);
        epochManager.validateEpochState(IEpochManager.State.REVEAL);

        uint256 currentEpoch = epochManager.getCurrentEpoch();
        bytes32 committed = nodeCommitments[currentEpoch][nodeId];

        if (committed == 0) {
            revert NoCommitmentFound(currentEpoch, nodeId);
        }
        if (keccak256(secret) != committed) {
            revert InvalidSecret(nodeId);
        }

        nodeReveals[currentEpoch][nodeId] = secret;
        nodeRevealsList[currentEpoch].push(nodeId);

        emit SecretRevealed(currentEpoch, nodeId, msg.sender, secret);
    }

    /**
     * @notice Elect the leader for the current epoch
     */
    function electLeader() external returns (uint256 leaderNodeId) {
        // TODO: Make sure node revealed
        epochManager.validateEpochState(IEpochManager.State.ELECT);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        if (epochLeaders[currentEpoch] != 0) {
            return epochLeaders[currentEpoch];
        }
        uint256[] memory nodeIds = nodeRevealsList[currentEpoch];

        if (nodeIds.length == 0) {
            revert NoRevealsSubmitted(currentEpoch);
        }

        bytes memory combinedReveals;
        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes memory secret = nodeReveals[currentEpoch][nodeIds[i]];
            if (secret.length == 0) {
                revert MissingReveal(nodeIds[i]);
            }
            combinedReveals = abi.encodePacked(combinedReveals, secret);
        }

        bytes32 finalRandom = keccak256(combinedReveals);
        finalRandomValues[currentEpoch] = finalRandom;

        uint256 leaderIndex = uint256(finalRandom) % nodeIds.length;
        leaderNodeId = nodeIds[leaderIndex];
        epochLeaders[currentEpoch] = leaderNodeId;

        emit LeaderElected(currentEpoch, finalRandom, leaderNodeId);
        return leaderNodeId;
    }

    /**
     * @notice Gets the current leader for the active epoch
     */
    function getCurrentLeader() public view returns (uint256) {
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        return epochLeaders[currentEpoch];
    }

    /**
     * @notice Gets the leader for the given epoch
     */
    function getLeaderForEpoch(uint256 epoch) external view returns (uint256) {
        return epochLeaders[epoch];
    }

    /**
     * @notice Validates if a caller is the leader for the active epoch
     */
    function validateLeader(address caller) external view {
        address leader = nodeManager.getNodeOwner(getCurrentLeader());
        if (caller != leader) {
            revert NotCurrentLeader(caller, leader);
        }
    }

    /**
     * @notice Gets the final random value for an epoch
     */
    function getFinalRandomValue(uint256 epoch) external view returns (bytes32) {
        bytes32 randomValue = finalRandomValues[epoch];
        if (randomValue == 0) {
            revert NoRandomValueForEpoch(epoch);
        }
        return randomValue;
    }

    /**
     * @notice Gets the list of nodes that revealed their secret for an epoch
     */
    function getNodesWhoRevealed(uint256 epoch) external view returns (uint256[] memory) {
        return nodeRevealsList[epoch];
    }

    // Internal functions

    function validateStakeAndWhitelist(address cp) internal view {
        whitelistManager.requireWhitelisted(cp);
        uint256 requiredStake = nodeManager.getStakeRequirement(cp);
        nodeEscrow.requireBalance(cp, requiredStake);
    }
}