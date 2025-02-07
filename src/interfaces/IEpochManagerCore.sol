// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEpochManagerCore {
    enum EpochState {COMMIT, REVEAL, ELECT, EXECUTE, CONFIRM, DISPUTE}

    function getCurrentEpoch() external view returns (uint256);
    function getEpochState() external view returns (EpochState state, uint256 timeLeft);
    function isInPhase(EpochState phase) external view returns (bool);
    function getGenesisTimestamp() external view returns (uint256);
}