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
        Commit,  // Stakers commit their votes
        Reveal,  // Stakers reveal their votes
        Propose, // Block proposers submit block proposals
        Buffer   // Transition period between epochs
    }

    /**
     * @notice Represents the different statuses of a job
     */
    enum Status {
        Create,        // Job is created but not yet started
        Execution,     // Job is currently being executed
        ProofCreation, // Proof of job completion is being created
        Completed      // Job is fully completed and verified
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
     * @dev 20,000 LUMINO tokens (assuming 18 decimal places)
     */
    uint256 public minStake = 20_000 * (10 ** 18);

    /**
     * @notice Minimum safe amount of LUMINO tokens for a staker
     * @dev 10,000 LUMINO tokens (assuming 18 decimal places)
     */
    uint256 public minSafeLumToken = 10_000 * (10 ** 18);

    /**
     * @notice Buffer time in seconds for state transitions
     */
    uint8 public buffer = 5;

    /**
     * @notice Number of epochs for which stake is locked after calling unstake()
     */
    uint16 public unstakeLockPeriod = 1;
}