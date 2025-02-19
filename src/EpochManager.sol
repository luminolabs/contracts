// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract EpochManager is IEpochManager {
    /**
    * @notice Counter for testing purposes
    */
    uint256 public testCounter;

    /**
     * @notice Up a counter, to allow creating a new block
     */
    function upTestCounter() external {
        testCounter++;
    }

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

        uint256 commitOffset = LShared.COMMIT_DURATION;
        uint256 revealOffset = commitOffset + LShared.REVEAL_DURATION;
        uint256 electOffset = revealOffset + LShared.ELECT_DURATION;
        uint256 executeOffset = electOffset + LShared.EXECUTE_DURATION;
        uint256 confirmOffset = executeOffset + LShared.CONFIRM_DURATION;
        uint256 disputeOffset = confirmOffset + LShared.DISPUTE_DURATION;

        if (elapsed < commitOffset) {
            state = State.COMMIT;
            timeLeft = commitOffset - elapsed;
        } else if (elapsed < revealOffset) {
            state = State.REVEAL;
            timeLeft = revealOffset - elapsed;
        } else if (elapsed < electOffset) {
            state = State.ELECT;
            timeLeft = electOffset - elapsed;
        } else if (elapsed < executeOffset) {
            state = State.EXECUTE;
            timeLeft = executeOffset - elapsed;
        } else if (elapsed < confirmOffset) {
            state = State.CONFIRM;
            timeLeft = confirmOffset - elapsed;
        } else if (elapsed < disputeOffset) {
            state = State.DISPUTE;
            timeLeft = disputeOffset - elapsed;
        }

        return (state, timeLeft);
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