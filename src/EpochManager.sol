// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {PausableController} from "./abstracts/PausableController.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {Epoch} from "./libraries/Epoch.sol";

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
contract EpochManager is IEpochManager, PausableController {
    // Core contracts
    //

    // State variables
    uint256 private immutable genesisTimestamp;

    // Custom errors
    //

    // Events
    //

    /**
     * @dev Initializes the epoch system with access control and marks genesis time
     * @param _accessController Address of the AccessController contract
     */
    constructor(address _accessController) PausableController(_accessController) {
        genesisTimestamp = block.timestamp;
    }

    /**
     * @dev Returns the current epoch number
     * @return uint256 Current epoch number, starting from 1
     */
    function getCurrentEpoch() external view returns (uint256) {
        if (paused()) return 0;
        return ((block.timestamp - genesisTimestamp) / Epoch.EPOCH_DURATION) + 1;
    }

    /**
     * @dev Gets current epoch state and remaining time in the current phase
     * @return state Current phase of the epoch
     * @return timeLeft Time remaining in current phase (in seconds)
     */
    function getEpochState() external view returns (Epoch.State state, uint256 timeLeft) {
        if (paused()) return (Epoch.State.PAUSED, 0);
        uint256 elapsed = (block.timestamp - genesisTimestamp) % Epoch.EPOCH_DURATION;

        if (elapsed < Epoch.COMMIT_DURATION) {
            return (Epoch.State.COMMIT, Epoch.COMMIT_DURATION - elapsed);
        } else if (elapsed < Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION) {
            return (Epoch.State.REVEAL, Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION - elapsed);
        } else if (elapsed < Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION + Epoch.ELECT_DURATION) {
            return (Epoch.State.ELECT, Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION + Epoch.ELECT_DURATION - elapsed);
        } else if (elapsed < Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION + Epoch.ELECT_DURATION + Epoch.EXECUTE_DURATION) {
            return (Epoch.State.EXECUTE, Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION + Epoch.ELECT_DURATION + Epoch.EXECUTE_DURATION - elapsed);
        } else if (elapsed < Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION + Epoch.ELECT_DURATION + Epoch.EXECUTE_DURATION + Epoch.CONFIRM_DURATION) {
            return (Epoch.State.CONFIRM, Epoch.COMMIT_DURATION + Epoch.REVEAL_DURATION + Epoch.ELECT_DURATION + Epoch.EXECUTE_DURATION + Epoch.CONFIRM_DURATION - elapsed);
        } else {
            return (Epoch.State.DISPUTE, Epoch.EPOCH_DURATION - elapsed);
        }
    }

    /**
     * @dev Checks if current epoch is in the specified phase
     * @param phase Phase to check against current state
     * @return bool True if current phase matches specified phase
     */
    function isInPhase(Epoch.State phase) external view returns (bool) {
        if (paused()) return false;
        (Epoch.State currentState,) = this.getEpochState();
        return currentState == phase;
    }

    /**
     * @dev Returns the timestamp when the epoch system was initialized
     * @return uint256 Genesis timestamp in seconds since Unix epoch
     */
    function getGenesisTimestamp() external view returns (uint256) {
        return genesisTimestamp;
    }

    /**
     * @dev Calculates time remaining until next epoch starts
     * @return uint256 Time in seconds until next epoch
     */
    function getTimeUntilNextEpoch() external view returns (uint256) {
        if (paused()) return 0;
        return Epoch.EPOCH_DURATION - ((block.timestamp - genesisTimestamp) % Epoch.EPOCH_DURATION);
    }

    /**
     * @dev Returns the duration of a specified phase
     * @param phase Phase to query
     * @return uint256 Duration of the phase in seconds
     */
    function getPhaseDuration(Epoch.State phase) external pure returns (uint256) {
        if (phase == Epoch.State.COMMIT) return Epoch.COMMIT_DURATION;
        if (phase == Epoch.State.REVEAL) return Epoch.REVEAL_DURATION;
        if (phase == Epoch.State.ELECT) return Epoch.ELECT_DURATION;
        if (phase == Epoch.State.EXECUTE) return Epoch.EXECUTE_DURATION;
        if (phase == Epoch.State.CONFIRM) return Epoch.CONFIRM_DURATION;
        if (phase == Epoch.State.DISPUTE) return Epoch.DISPUTE_DURATION;
        return 0;
    }

    /**
     * @dev Calculates the start timestamp of a specific epoch
     * @param epoch Epoch number to query
     * @return uint256 Start timestamp of the epoch
     */
    function getEpochStartTime(uint256 epoch) external view returns (uint256) {
        if (epoch == 0 || paused()) return 0;
        return genesisTimestamp + ((epoch - 1) * Epoch.EPOCH_DURATION);
    }
}