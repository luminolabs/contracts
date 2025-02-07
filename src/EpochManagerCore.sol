// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IEpochManagerCore.sol";
import "./interfaces/IAccessController.sol";

/**
 * @title EpochManagerCore
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
contract EpochManagerCore is IEpochManagerCore {
    // Core durations
    uint256 public constant COMMIT_DURATION = 10 seconds;
    uint256 public constant REVEAL_DURATION = 10 seconds;
    uint256 public constant ELECT_DURATION = 10 seconds;
    uint256 public constant EXECUTE_DURATION = 60 seconds;
    uint256 public constant CONFIRM_DURATION = 20 seconds;
    uint256 public constant DISPUTE_DURATION = 10 seconds;
    uint256 public constant EPOCH_DURATION = COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION +
    EXECUTE_DURATION + CONFIRM_DURATION + DISPUTE_DURATION;

    // Core contracts
    IAccessController public immutable accessController;

    // State variables
    uint256 private immutable genesisTimestamp;
    bool public isPaused;

    // Custom errors
    error Unauthorized(address caller);
    error InvalidPhase(EpochState required, EpochState current);
    error SystemPaused();

    // Events
    event EpochSystemPaused(address indexed operator);
    event EpochSystemUnpaused(address indexed operator);
    event PhaseSkipped(uint256 indexed epoch, EpochState indexed phase);

    /**
     * @dev Restricts function access to addresses with admin role
     */
    modifier onlyAdmin() {
        if (!accessController.isAuthorized(msg.sender, keccak256("ADMIN_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @dev Restricts function access to addresses with operator role
     */
    modifier onlyOperator() {
        if (!accessController.isAuthorized(msg.sender, keccak256("OPERATOR_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @dev Prevents function execution when system is paused
     */
    modifier whenNotPaused() {
        if (isPaused) {
            revert SystemPaused();
        }
        _;
    }

    /**
     * @dev Initializes the epoch system with access control and marks genesis time
     * @param _accessController Address of the AccessController contract
     */
    constructor(address _accessController) {
        accessController = IAccessController(_accessController);
        genesisTimestamp = block.timestamp;
        isPaused = false;
    }

    /**
     * @dev Returns the current epoch number
     * @return uint256 Current epoch number, starting from 1
     * @notice Returns 0 if the system is paused
     */
    function getCurrentEpoch() external view returns (uint256) {
        if (isPaused) return 0;
        return ((block.timestamp - genesisTimestamp) / EPOCH_DURATION) + 1;
    }

    /**
     * @dev Gets current epoch state and remaining time in the current phase
     * @return state Current phase of the epoch
     * @return timeLeft Time remaining in current phase (in seconds)
     * @notice Returns (COMMIT, 0) if the system is paused
     */
    function getEpochState() external view returns (EpochState state, uint256 timeLeft) {
        if (isPaused) return (EpochState.COMMIT, 0);

        uint256 elapsed = (block.timestamp - genesisTimestamp) % EPOCH_DURATION;

        if (elapsed < COMMIT_DURATION) {
            return (EpochState.COMMIT, COMMIT_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION) {
            return (EpochState.REVEAL, COMMIT_DURATION + REVEAL_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION) {
            return (EpochState.ELECT, COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION) {
            return (EpochState.EXECUTE, COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION - elapsed);
        } else if (elapsed < COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION) {
            return (EpochState.CONFIRM, COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION - elapsed);
        } else {
            return (EpochState.DISPUTE, EPOCH_DURATION - elapsed);
        }
    }

    /**
     * @dev Checks if current epoch is in the specified phase
     * @param phase Phase to check against current state
     * @return bool True if current phase matches specified phase
     * @notice Always returns false if system is paused
     */
    function isInPhase(EpochState phase) external view returns (bool) {
        if (isPaused) return false;
        (EpochState currentState,) = this.getEpochState();
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
     * @dev Pauses the epoch system
     * @notice Only callable by admin
     * @notice Emits EpochSystemPaused event
     */
    function pauseEpochSystem() external onlyAdmin whenNotPaused {
        isPaused = true;
        emit EpochSystemPaused(msg.sender);
    }

    /**
     * @dev Unpauses the epoch system
     * @notice Only callable by admin
     * @notice Emits EpochSystemUnpaused event
     */
    function unpauseEpochSystem() external onlyAdmin {
        isPaused = false;
        emit EpochSystemUnpaused(msg.sender);
    }

    /**
     * @dev Calculates time remaining until next epoch starts
     * @return uint256 Time in seconds until next epoch
     * @notice Returns 0 if system is paused
     */
    function getTimeUntilNextEpoch() external view returns (uint256) {
        if (isPaused) return 0;
        return EPOCH_DURATION - ((block.timestamp - genesisTimestamp) % EPOCH_DURATION);
    }

    /**
     * @dev Returns the duration of a specified phase
     * @param phase Phase to query
     * @return uint256 Duration of the phase in seconds
     */
    function getPhaseDuration(EpochState phase) external pure returns (uint256) {
        if (phase == EpochState.COMMIT) return COMMIT_DURATION;
        if (phase == EpochState.REVEAL) return REVEAL_DURATION;
        if (phase == EpochState.ELECT) return ELECT_DURATION;
        if (phase == EpochState.EXECUTE) return EXECUTE_DURATION;
        if (phase == EpochState.CONFIRM) return CONFIRM_DURATION;
        if (phase == EpochState.DISPUTE) return DISPUTE_DURATION;
        return 0;
    }

    /**
     * @dev Calculates the start timestamp of a specific epoch
     * @param epoch Epoch number to query
     * @return uint256 Start timestamp of the epoch
     * @notice Returns 0 if epoch is 0 or system is paused
     */
    function getEpochStartTime(uint256 epoch) external view returns (uint256) {
        if (epoch == 0 || isPaused) return 0;
        return genesisTimestamp + ((epoch - 1) * EPOCH_DURATION);
    }
}