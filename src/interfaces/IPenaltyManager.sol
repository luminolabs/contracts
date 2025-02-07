// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IPenaltyManager {
    event PenaltyApplied(address indexed cp, uint256 amount, string reason);
    event SlashExecuted(address indexed cp, uint256 amount);
    event PenaltyThresholdUpdated(uint256 newThreshold);
    event PenaltyRateUpdated(uint256 newRate);

    function applyPenalty(address cp, string calldata reason) external;
    function executeSlash(address cp) external;
    function updatePenaltyThreshold(uint256 newThreshold) external;
    function updatePenaltyRate(uint256 newRate) external;
    function getPenaltyCount(address cp) external view returns (uint256);
    function getTotalPenalties(address cp) external view returns (uint256);
    function checkSlashThreshold(address cp) external view returns (bool exceeded, uint256 count);
}