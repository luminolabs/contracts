// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title Constants
 * @notice Defines constant values and enums used throughout the Lumino protocol
 * @dev This contract should be inherited by other contracts that need these constants
 */
contract Constants {
    /**
     * @notice Represents the different states of an epoch
     */
    enum State {
        Assign, // JobsManager assign jobs to stakers
        Accept, // Stakers accept the jobs
        Confirm, // A Proposer is selected and a block is prooposed
        Buffer // Buffer Transition period between epochs
    }

    /**
     * @notice Represents the different statuses of a job
     */
    enum Status {
        Cancelled,          // Job is cancelled
        Created,            // Job is created but not yet assigned
        Assigned,           // Job is assigned but hasn't started yet
        Execution,          // Job is currently being executed
        ProofGeneration,    // Proof of job completion is being created
        Completed           // Job is fully completed and verified
    }

    /**
     * @notice Total number of states in an epoch (excluding Buffer)
     */
    uint8 public constant NUM_STATES = 3;

    /**
     * @notice Duration of an epoch in seconds
     * @dev 1200 seconds = 20 minutes
     */
    uint16 public constant EPOCH_LENGTH = 1200;

    /**
     * @notice Minimum amount of stake required to become a staker
     * @dev 10 LUMINO native tokens (assuming 18 decimal places)
     */
    uint256 public minStake = 10 * (10 ** 18);

    /**
     * @notice Minimum safe amount of LUMINO tokens for a staker
     * @dev 1 LUMINO token (assuming 18 decimal places)
     */
    uint256 public minSafeLumToken = 1 * (10 ** 18);

    /**
     * @notice Buffer time in seconds for state transitions
     */
    uint8 public buffer = 5;

    /**
     * @notice Number of epochs for which stake is locked after calling unstake()
     */
    uint16 public unstakeLockPeriod = 1;
}
