// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IIncentiveManager {
    // Errors
    error EpochAlreadyProcessed(uint256 epoch);
    error CanOnlyProcessCurrentEpoch(uint256 epoch, uint256 currentEpoch);

    // Events
    event LeaderRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event NodeRewardApplied(uint256 indexed epoch, uint256[] indexed nodeIds, uint256 amount);
    event DisputerRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event LeaderPenaltyApplied(uint256 indexed epoch, address cp, uint256 amount);
    event NodePenaltyApplied(uint256 indexed epoch, uint256[] indexed jobs, uint256 amount);


    // Incentive manager functions
    function processAll(uint256 epoch) external;
}