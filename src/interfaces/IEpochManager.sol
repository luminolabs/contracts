// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../libraries/Epoch.sol";

interface IEpochManager {
    function getCurrentEpoch() external view returns (uint256);
    function getEpochState() external view returns (Epoch.State state, uint256 timeLeft);
    function isInPhase(Epoch.State phase) external view returns (bool);
    function getGenesisTimestamp() external view returns (uint256);
}