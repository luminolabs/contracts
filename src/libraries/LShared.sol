// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library LShared {
    // Constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONTRACTS_ROLE = keccak256("CONTRACTS_ROLE");

    // Constants
    uint256 public constant COMMIT_DURATION = 10 seconds;
    uint256 public constant REVEAL_DURATION = 10 seconds;
    uint256 public constant ELECT_DURATION = 10 seconds;
    uint256 public constant EXECUTE_DURATION = 60 seconds;
    uint256 public constant CONFIRM_DURATION = 20 seconds;
    uint256 public constant DISPUTE_DURATION = 10 seconds;
    uint256 public constant EPOCH_DURATION = COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION + CONFIRM_DURATION + DISPUTE_DURATION;

    // Constants
    uint256 public constant LEADER_ASSIGNMENT_REWARD = 100 * 10 ** 18; // 100 tokens
    uint256 public constant SECRET_REVEAL_REWARD = 50 * 10 ** 18;      // 50 tokens
    uint256 public constant DISPUTE_REWARD = 200 * 10 ** 18;           // 200 tokens
    uint256 public constant MISSED_ASSIGNMENT_PENALTY = 200 * 10 ** 18; // 200 tokens
    uint256 public constant MISSED_CONFIRMATION_PENALTY = 100 * 10 ** 18; // 100 tokens
    uint256 public constant MAX_PENALTIES_BEFORE_SLASH = 20;

    // Constants
    uint256 public constant MIN_BALANCE_TO_SUBMIT = 1;

    // Constants
    uint256 public constant WHITELIST_COOLDOWN = 7 days;

    // Constants
    uint256 public constant STAKE_PER_RATING = 1e18; // 1 token per compute rating unit
}