// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./storage/Constants.sol";

/**
 * @title StateManager
 * @dev Manages the state and epoch transitions in the Lumino Staking System.
 * This contract provides core functionality for epoch-based operations and state transitions.
 */
contract StateManager is Constants {
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
     * @param state The expected state.
     * @param buffer The buffer time (in seconds) around state transitions.
     */
    modifier checkState(State state, uint8 buffer) {
        require(state == getState(buffer), "Incorrect state");
        _;
    }

    /**
     * @dev Modifier to ensure the function is called in the correct epoch and state.
     * @param state The expected state.
     * @param epoch The expected epoch.
     * @param buffer The buffer time (in seconds) around state transitions.
     */
    modifier checkEpochAndState(State state, uint32 epoch, uint8 buffer) {
        require(epoch == getEpoch(), "Incorrect epoch");
        require(state == getState(buffer), "Incorrect state");
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
     * @dev Determines the current state within an epoch.
     * @param buffer The buffer time (in seconds) around state transitions.
     * @return The current state of the system.
     */
    function getState(uint8 buffer) public view returns (State) {
        // Calculate the length of each state within an epoch
        uint8 lowerLimit = buffer;

        uint16 upperLimit = EPOCH_LENGTH / NUM_STATES - buffer;

        if (block.timestamp % (EPOCH_LENGTH / NUM_STATES) > upperLimit || block.timestamp % (EPOCH_LENGTH / NUM_STATES) < lowerLimit) {
            return State.Buffer;
        }

        uint8 state = uint8(((block.timestamp) / (EPOCH_LENGTH / NUM_STATES)) % (NUM_STATES));
        return State(state);
    }
}