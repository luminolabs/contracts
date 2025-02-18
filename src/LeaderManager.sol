// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {ILeaderManager} from "./interfaces/ILeaderManager.sol";
import {INodeManager} from "./interfaces/INodeManager.sol";
import {INodeEscrow} from "./interfaces/INodeEscrow.sol";
import {IWhitelistManager} from "./interfaces/IWhitelistManager.sol";

contract LeaderManager is ILeaderManager {
    // Contracts
    IEpochManager public immutable epochManager;
    INodeManager public immutable nodeManager;
    INodeEscrow public immutable stakeEscrow;
    IAccessManager public immutable accessManager;
    IWhitelistManager public immutable whitelistManager;

    // State variables
    mapping(uint256 => mapping(uint256 => bytes32)) private nodeCommitments;
    mapping(uint256 => mapping(uint256 => bytes)) private nodeReveals;
    mapping(uint256 => uint256[]) private nodeRevealsList;
    mapping(uint256 => bytes32) private finalRandomValues;
    mapping(uint256 => uint256) private epochLeaders;

    constructor(
        address _epochManager,
        address _nodeManager,
        address _stakeEscrow,
        address _accessManager,
        address _whitelistManager
    ) {
        epochManager = IEpochManager(_epochManager);
        nodeManager = INodeManager(_nodeManager);
        stakeEscrow = INodeEscrow(_stakeEscrow);
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
        epochManager.validateEpochState(IEpochManager.State.ELECT);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        if (epochLeaders[currentEpoch] != 0) {
            revert LeaderAlreadyElected(currentEpoch);
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
        stakeEscrow.requireBalance(cp, requiredStake);
    }
}