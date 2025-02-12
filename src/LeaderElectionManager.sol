// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {ILeaderElectionManager} from "./interfaces/ILeaderElectionManager.sol";
import {INodeRegistryCore} from "./interfaces/INodeRegistryCore.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {Nodes} from "./libraries/Nodes.sol";

/**
 * @title LeaderElectionManager
 * @dev Manages the leader election process for each epoch using a commit-reveal scheme
 * to ensure fair and verifiable random selection of leaders.
 *
 * The election process consists of three phases:
 * 1. Commit Phase: Nodes submit hashed commitments of their secret values
 * 2. Reveal Phase: Nodes reveal their original secrets which are verified against commitments
 * 3. Election Phase: A leader is randomly selected using the combined revealed secrets
 *
 * Security features:
 * - Two-phase commit-reveal scheme prevents manipulation of randomness
 * - Only registered node owners can participate
 * - Phase-specific actions are enforced through epoch manager
 * - Strict verification of revealed secrets against commitments
 */
contract LeaderElectionManager is ILeaderElectionManager, AccessControlled {
    // Core contracts
    INodeRegistryCore public immutable nodeRegistry;
    IStakingCore public immutable stakingCore;

    // Election state
    /// @dev Mapping of node commitments for each epoch
    mapping(uint256 => mapping(uint256 => bytes32)) private nodeCommitments;
    /// @dev Mapping of node reveals for each epoch
    mapping(uint256 => mapping(uint256 => bytes)) private nodeReveals;
    /// @dev List of nodes that revealed their secrets for each epoch
    mapping(uint256 => uint256[]) private nodeRevealsList;
    /// @dev Mapping of final random values for each epoch
    mapping(uint256 => bytes32) private finalRandomValues;
    /// @dev Mapping of elected leaders for each epoch
    mapping(uint256 => uint256) private epochLeaders;

    // Custom errors
    error WrongPhase(Epoch.State required);
    error NoCommitmentFound(uint256 epoch, uint256 nodeId);
    error InvalidSecret(uint256 nodeId);
    error NoRevealsSubmitted(uint256 epoch);
    error MissingReveal(uint256 nodeId);

    /**
     * @dev Initializes the contract with required dependencies
     * @param _epochManager Address of the epoch manager contract
     * @param _nodeRegistry Address of the node registry contract
     * @param _stakingCore Address of the staking contract
     * @param _accessController Address of the access controller contract
     */
    constructor(
        address _epochManager,
        address _nodeRegistry,
        address _stakingCore,
        address _accessController
    ) AccessControlled(_accessController) {
        epochManager = IEpochManager(_epochManager);
        nodeRegistry = INodeRegistryCore(_nodeRegistry);
        stakingCore = IStakingCore(_stakingCore);
    }

    /**
     * @dev Submit a commitment for the current epoch's leader election
     * @param nodeId The ID of the node submitting the commitment
     * @param commitment The hashed secret value (keccak256 hash of the secret)
     *
     * Requirements:
     * - Must be called during COMMIT phase
     * - Caller must be the owner of the node
     *
     * Emits a {CommitSubmitted} event
     */
    function submitCommitment(uint256 nodeId, bytes32 commitment)
    external
    {
        Nodes.validateNodeOwner(nodeRegistry, nodeId, msg.sender);
        Epoch.validateState(Epoch.State.COMMIT, epochManager);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        nodeCommitments[currentEpoch][nodeId] = commitment;

        emit CommitSubmitted(currentEpoch, nodeId, msg.sender);
    }

    /**
     * @dev Reveal the secret corresponding to a previously submitted commitment
     * @param nodeId The ID of the node revealing its secret
     * @param secret The original secret value whose hash was committed
     *
     * Requirements:
     * - Must be called during REVEAL phase
     * - Caller must be the owner of the node
     * - A commitment must exist for the node in the current epoch
     * - The hash of the revealed secret must match the commitment
     *
     * Emits a {SecretRevealed} event
     */
    function revealSecret(uint256 nodeId, bytes calldata secret)
    external
    {
        Nodes.validateNodeOwner(nodeRegistry, nodeId, msg.sender);
        Epoch.validateState(Epoch.State.REVEAL, epochManager);
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
     * @dev Elect a leader for the current epoch using revealed secrets
     * @return leaderNodeId The ID of the elected leader node
     *
     * The leader is selected randomly using a combined hash of all revealed secrets.
     * The selection probability is uniform among all nodes that completed both commit and reveal phases.
     *
     * Requirements:
     * - Must be called during ELECT phase
     * - At least one node must have completed the reveal phase
     * - All nodes in the reveal list must have valid reveals
     *
     * Emits a {LeaderElected} event
     */
    function electLeader()
    external
    returns (uint256 leaderNodeId)
    {
        Epoch.validateState(Epoch.State.ELECT, epochManager);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
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
     * @dev Get the current epoch's elected leader
     * @return The node ID of the current leader
     */
    function getCurrentLeader() external view returns (uint256) {
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        return epochLeaders[currentEpoch];
    }

    /**
     * @dev Get the final random value generated for a specific epoch
     * @param epoch The epoch number to query
     * @return The final random value used for leader selection
     */
    function getFinalRandomValue(uint256 epoch) external view returns (bytes32) {
        return finalRandomValues[epoch];
    }

    /**
     * @dev Get a node's commitment for a specific epoch
     * @param epoch The epoch number to query
     * @param nodeId The ID of the node
     * @return The commitment hash submitted by the node
     */
    function getCommitment(uint256 epoch, uint256 nodeId) external view returns (bytes32) {
        return nodeCommitments[epoch][nodeId];
    }

    /**
     * @dev Get a node's revealed secret for a specific epoch
     * @param epoch The epoch number to query
     * @param nodeId The ID of the node
     * @return The revealed secret
     */
    function getReveal(uint256 epoch, uint256 nodeId) external view returns (bytes memory) {
        return nodeReveals[epoch][nodeId];
    }

    /**
     * @dev Get all nodes that revealed their secrets for a specific epoch
     * @param epoch The epoch number to query
     * @return Array of node IDs that completed the reveal phase
     */
    function getRevealedNodes(uint256 epoch) external view returns (uint256[] memory) {
        return nodeRevealsList[epoch];
    }
}