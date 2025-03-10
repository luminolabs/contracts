// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEpochManager {
    // Enums
    enum State {COMMIT, REVEAL, ELECT, EXECUTE, CONFIRM, DISPUTE, PAUSED}

    // Errors
    error InvalidState(State state);

    // Epoch management functions
    function getCurrentEpoch() external view returns (uint256);
    function getEpochState() external view returns (State state, uint256 timeLeft);
    function validateEpochState(State state) external view;
}