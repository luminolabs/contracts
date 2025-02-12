// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Shared {
    // Available states
    enum State {COMMIT, REVEAL, ELECT, EXECUTE, CONFIRM, DISPUTE, PAUSED}

    // State durations
    uint32 public constant COMMIT_DURATION = 10 seconds;
    uint32 public constant REVEAL_DURATION = 10 seconds;
    uint32 public constant ELECT_DURATION = 10 seconds;
    uint32 public constant EXECUTE_DURATION = 60 seconds;
    uint32 public constant CONFIRM_DURATION = 20 seconds;
    uint32 public constant DISPUTE_DURATION = 10 seconds;

    // Epoch duration
    uint32 public constant EPOCH_LENGTH = COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION + DISPUTE_DURATION;

    // Custom errors
    error InvalidState(State state);
}