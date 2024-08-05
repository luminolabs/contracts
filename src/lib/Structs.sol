// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title Structs
 * @notice Library containing struct definitions used throughout the Lumino protocol
 * @dev This library should be imported by contracts that need to use these structs
 */
library Structs {
    /**
     * @notice Represents a staker in the Lumino network
     * @dev Used to store comprehensive information about each staker
     */
    struct Staker {
        bool isSlashed;             // Whether the staker has been slashed
        address _address;           // Ethereum address of the staker
        uint32 id;                  // Unique identifier for the staker
        uint32 age;                 // Number of epochs the staker has been active
        uint32 epochFirstStaked;    // Epoch when the staker first staked
        uint32 epochLastPenalized;  // Last epoch when the staker was penalized
        uint256 stake;              // Current stake amount
        uint256 stakerReward;       // Accumulated rewards
        string machineSpecInJSON;   // JSON string containing machine specifications
    }

    /**
     * @notice Represents a locked stake
     * @dev Used when a staker initiates the unstaking process
     */
    struct Lock {
        uint256 amount;      // Amount of tokens locked
        uint256 unlockAfter; // Epoch after which the locked tokens can be withdrawn
    }

    /**
     * @notice Represents a commitment made by a staker during the voting process
     */
    struct Commitment {
        uint32 epoch;           // Epoch for which the commitment is made
        bytes32 commitmentHash; // Hash of the commitment
        bool revealed;          // Whether the commitment has been revealed
    }

    /**
     * @notice Represents a job in the Lumino network
     */
    struct Job {
        uint256 jobId;           // Unique identifier for the job
        address creator;         // Address of the job creator
        address assignee;        // Address of the staker assigned to the job
        uint32 creationEpoch;    // Epoch when the job was created
        uint32 executionEpoch;   // Epoch when the job execution started
        uint32 completionEpoch;  // Epoch when the job was completed
        string jobDetailsInJSON; // JSON string containing job details
    }

    /**
     * @notice Represents a job and its verification result
     * @dev Used during the voting process
     */
    struct JobVerifier {
        uint256 jobId;     // ID of the job
        bytes32 resultHash; // Hash of the job result
    }

    /**
     * @notice Represents an assigned job and its result
     */
    struct AssignedJob {
        uint256 jobId;     // ID of the assigned job
        bytes32 resultHash; // Hash of the job result
    }

    /**
     * @notice Represents a Merkle tree used for efficient vote commitments
     */
    struct MerkleTree {
        AssignedJob[] values; // Array of assigned jobs (leaf nodes)
        bytes32[][] proofs;   // Array of proof paths for each leaf
        bytes32 root;         // Root of the Merkle tree
    }

    /**
     * @notice Represents a block in the Lumino network
     */
    struct Block {
        bool valid;           // Whether the block is valid
        uint32 proposerId;    // ID of the staker who proposed this block
        uint256[] jobIds;     // Array of job IDs included in this block
        uint256 iteration;    // Block iteration number
        uint256 biggestStake; // Largest stake amount among included jobs
    }
}