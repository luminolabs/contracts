// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract EpochManager is IEpochManager {
    /**
     * @notice Returns the current epoch number, starting from epoch 1
     */
    function getCurrentEpoch() external view returns (uint256) {
        return (block.timestamp / LShared.EPOCH_DURATION) + 1;
    }

    /**
     * @notice Gets current epoch state and remaining time in the current phase
     */
    function getEpochState() public view returns (State state, uint256 timeLeft) {
        uint256 elapsed = block.timestamp % LShared.EPOCH_DURATION;

        if (elapsed < LShared.COMMIT_DURATION) {
            return (State.COMMIT, LShared.COMMIT_DURATION - elapsed);
        } else if (elapsed < LShared.COMMIT_DURATION + LShared.REVEAL_DURATION) {
            return (State.REVEAL, LShared.COMMIT_DURATION + LShared.REVEAL_DURATION - elapsed);
        } else if (elapsed < LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION) {
            return (State.ELECT, LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION - elapsed);
        } else if (elapsed < LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION) {
            return (State.EXECUTE, LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION - elapsed);
        } else if (elapsed < LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION) {
            return (State.CONFIRM, LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION - elapsed);
        } else {
            return (State.DISPUTE, LShared.EPOCH_DURATION - elapsed);
        }
    }

    /**
     * @notice Validates that the current epoch state matches the expected state
     */
    function validateEpochState(State state) external view {
        (State currentState,) = getEpochState();
        if (currentState != state) {
            revert InvalidState(state);
        }
    }
}