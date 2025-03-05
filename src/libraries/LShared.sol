// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library LShared {
    // AccessManager Constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONTRACTS_ROLE = keccak256("CONTRACTS_ROLE");

    // EpochManager Constants
    uint256 public constant COMMIT_DURATION = 5 seconds;
    uint256 public constant REVEAL_DURATION = 5 seconds;
    uint256 public constant ELECT_DURATION = 5 seconds;
    uint256 public constant EXECUTE_DURATION = 5 seconds;
    uint256 public constant CONFIRM_DURATION = 15 seconds;
    uint256 public constant DISPUTE_DURATION = 5 seconds;
    uint256 public constant EPOCH_DURATION = COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION + DISPUTE_DURATION;

    // IncentiveManager Constants
    uint256 public constant LEADER_REWARD = 5 * 1e18;
    uint256 public constant JOB_AVAILABILITY_REWARD = 1 * 1e18;
    uint256 public constant DISPUTER_REWARD = 0.5 * 1e18;
    uint256 public constant LEADER_NOT_EXECUTED_PENALTY = 15 * 1e18;
    uint256 public constant JOB_NOT_CONFIRMED_PENALTY = 10 * 1e18;
    uint256 public constant MAX_PENALTIES_BEFORE_SLASH = 10;

    // JobManager Constants
    uint256 public constant MIN_BALANCE_TO_SUBMIT = 1 * 1e18;

    // WhitelistManager Constants
    uint256 public constant WHITELIST_COOLDOWN = 3 days;

    // NodeEscrow Constants
    uint256 public constant STAKE_PER_RATING = 10 * 1e18;
}