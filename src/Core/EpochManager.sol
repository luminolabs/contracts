// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Shared} from "./storage/Shared.sol";

/**
 * @title EpochManager
 * @dev Manages the lifecycle and phases of epochs in the system.
 *
 * The contract divides time into fixed-length epochs, with each epoch containing
 * multiple sequential phases:
 * - COMMIT: Nodes submit commitments for leader election
 * - REVEAL: Nodes reveal their secrets
 * - ELECT: Leader is elected based on revealed secrets
 * - EXECUTE: Leader assigns jobs to nodes
 * - CONFIRM: Nodes confirm job completion
 * - DISPUTE: Period for raising disputes
 *
 * Each phase has a fixed duration, and the contract provides utilities to:
 * - Track current epoch and phase
 * - Calculate time remaining in current phase
 * - Verify if system is in a specific phase
 * - Handle emergency pausing of the epoch system
 */
contract EpochManager is Shared {

    /**
     * @dev Modifier to ensure the function is called with the correct epoch.
     * @param epoch The epoch value to check against the current epoch.
     */
    modifier checkEpoch(uint32 epoch) {
        require(epoch == getEpoch(), "Incorrect epoch");
        _;
    }

    /**
     * @dev Modifier to ensure the function is called in the specified state.
     * @param _state The expected state.
     */
    modifier checkState(State _state) {
        (State current,) = getState();
        require(current == _state, "Not allowed state");
        _;
    }

    /**
     * @dev Modifier to ensure the function is called in the correct epoch and state.
     * @param state The expected state.
     * @param epoch The expected epoch.
     */
    modifier checkEpochAndState(uint32 epoch, State state) {
        require(getEpoch() == epoch, "Not the expected epoch");
        (State currentState,) = getState();
        require(currentState == state, "Not the expected state");
        _;
    }

    /**
     * @dev Calculates and returns the current epoch number.
     * @return The current epoch number.
     */
    function getEpoch() public view returns (uint32) {
        // Calculate the epoch by dividing the current timestamp by the EPOCH_LENGTH
        return (uint32(block.timestamp) / EPOCH_LENGTH);
    }

    /**
     * @dev Gets current epoch state and remaining time in the current phase
     * @return state Current phase of the epoch
     * @return timeLeft Time remaining in current phase (in seconds)
     */
    function getState() public view returns (State state, uint32 timeLeft) {
        uint32 elapsed = uint32(block.timestamp) % EPOCH_LENGTH;

        if (elapsed < COMMIT_DURATION) {
            return (State.COMMIT, COMMIT_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION) {
            return (State.REVEAL, COMMIT_DURATION + REVEAL_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION) {
            return (State.ELECT, COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION) {
            return (State.EXECUTE, COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION) {
            return (State.CONFIRM, COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION - elapsed);
        } else {
            return (State.DISPUTE, EPOCH_LENGTH - elapsed);
        }
    }

    /**
     * @dev Calculates time remaining until next epoch starts
     * @return uint32 Time in seconds until next epoch
     */
    function getTimeUntilNextEpoch() external view returns (uint32) {
        return EPOCH_LENGTH - (uint32(block.timestamp) % EPOCH_LENGTH);
    }

    /**
     * @dev Returns the duration of a specified phase
     * @param phase Phase to query
     * @return uint32 Duration of the phase in seconds
     */
    function getPhaseDuration(State phase) external pure returns (uint32) {
        if (phase == State.COMMIT) return COMMIT_DURATION;
        if (phase == State.REVEAL) return REVEAL_DURATION;
        if (phase == State.ELECT) return ELECT_DURATION;
        if (phase == State.EXECUTE) return EXECUTE_DURATION;
        if (phase == State.CONFIRM) return CONFIRM_DURATION;
        if (phase == State.DISPUTE) return DISPUTE_DURATION;
        return 0;
    }

    /**
     * @dev Calculates the start timestamp of a specific epoch
     * @param epoch Epoch number to query
     * @return uint32 Start timestamp of the epoch
     */
    function getEpochStartTime(uint32 epoch) public pure returns (uint32) {
        return ((epoch - 1) * EPOCH_LENGTH);
    }
}