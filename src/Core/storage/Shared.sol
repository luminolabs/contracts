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

    // Epoch errors
    error InvalidState(State state);
    // Stake and Node errors
    error BelowMinimumStake(uint256 provided, uint256 minimum);
    error InsufficientStake(address cp, uint256 requested, uint256 available);
    error ExistingUnstakeRequest(address cp);
    error NoUnstakeRequest(address cp);
    error LockPeriodActive(address cp, uint256 remainingTime);
    error TransferFailed();
    error ZeroAddress();


    /**
     * @notice Duration that stakes must be locked before withdrawal
     * @dev Set to 1 day to balance security with provider flexibility
     * @dev 1 epoch = 2mins, 720 * 2 = 1440 minutes = 1 day
     */
    uint32 public constant LOCK_PERIOD = 720;
    /// @notice Counter for generating unique node IDs
    uint32 public nodeCounter;
    /**
     * @notice Minimum amount that can be staked
     * @dev Set to 100 tokens to ensure meaningful economic stake
     */
    uint256 public constant MIN_STAKE = 100 ether; // 100 tokens minimum
}