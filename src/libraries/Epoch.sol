// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "../interfaces/IEpochManager.sol";

library Epoch {
    // Available states
    enum State {COMMIT, REVEAL, ELECT, EXECUTE, CONFIRM, DISPUTE, PAUSED}

    // State durations
    uint256 public constant COMMIT_DURATION = 10 seconds;
    uint256 public constant REVEAL_DURATION = 10 seconds;
    uint256 public constant ELECT_DURATION = 10 seconds;
    uint256 public constant EXECUTE_DURATION = 60 seconds;
    uint256 public constant CONFIRM_DURATION = 20 seconds;
    uint256 public constant DISPUTE_DURATION = 10 seconds;

    // Epoch duration
    uint256 public constant EPOCH_DURATION = COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION + DISPUTE_DURATION;

    // Custom errors
    error InvalidState(State state);

    /**
     * @dev Validates the current state of the epoch
     * @param state The current state
     * @param epochManager The EpochManager contract
     */
    function validateState(State state, IEpochManager epochManager) internal view {
        if (!epochManager.isInPhase(state)) {
            revert InvalidState(state);
        }
    }
}