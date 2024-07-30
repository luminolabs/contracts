// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

/**
 * @title VoteManagerStorage
 * @notice Manages storage for voting-related data in the Lumino network
 * @dev This contract is intended to be inherited by the VoteManager contract
 */
contract VoteManagerStorage {

    /**
     * @notice Stores commitment information for each staker
     * @dev Mapping of stakerId -> Commitment struct
     */
    mapping(uint32 => Structs.Commitment) public commitments;

    /**
     * @notice Stores assigned jobs and their results for each staker in each epoch
     * @dev Mapping of epoch -> stakerId -> array of AssignedJob structs
     */
    mapping(uint32 => mapping(uint32 =>  Structs.AssignedJob[])) public assignedJobs;

    /**
     * @notice Stores the stake snapshot for each staker in each epoch
     * @dev Mapping of epoch -> stakerId -> stake amount
     */
    mapping(uint32 => mapping(uint32 => uint256)) public stakeSnapshot;

    /**
     * @notice Tracks the last epoch in which each staker revealed their vote
     * @dev Mapping of stakerId -> epoch number
     */
    mapping(uint32 => uint32) public epochLastRevealed;

    /**
     * @notice The current salt used for commitment hashing
     * @dev Updated periodically to prevent long-term attacks
     */
    bytes32 public salt;

    /**
     * @notice The depth of the Merkle tree used for vote commitments
     * @dev Determines the maximum number of jobs that can be committed in a single vote
     */
    uint256 public merkleTreeDepth;

    /**
     * @notice Emitted when a staker makes a vote commitment
     * @param stakerId The ID of the staker
     * @param epoch The epoch in which the commitment was made
     * @param commitmentHash The hash of the commitment
     */
    event VoteCommitted(uint32 indexed stakerId, uint32 indexed epoch, bytes32 commitmentHash);

    /**
     * @notice Emitted when a staker reveals their vote
     * @param stakerId The ID of the staker
     * @param epoch The epoch in which the vote was revealed
     */
    event VoteRevealed(uint32 indexed stakerId, uint32 indexed epoch);

    /**
     * @notice Emitted when the salt is updated
     * @param newSalt The new salt value
     */
    event SaltUpdated(bytes32 newSalt);

    /**
     * @notice Emitted when the Merkle tree depth is updated
     * @param newDepth The new depth value
     */
    event MerkleTreeDepthUpdated(uint256 newDepth);
}