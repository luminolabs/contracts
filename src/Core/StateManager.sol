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
        uint16 stateLength = EPOCH_LENGTH / NUM_STATES;

        // Calculate the current position within the current state
        uint16 statePosition = uint16(block.timestamp % stateLength);

        // Check if we're in the buffer period
        if (statePosition < buffer || statePosition > (stateLength - buffer)) {
            return State.Buffer;
        }

        // Calculate the current state based on the timestamp
        uint8 stateIndex = uint8((block.timestamp / stateLength) % NUM_STATES);
        return State(stateIndex);
    }
}