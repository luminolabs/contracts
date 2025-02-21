// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IIncentiveManager {
    // Errors
    error EpochAlreadyProcessed(uint256 epoch);

    // Events
    event LeaderRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event JobAvailabilityRewardApplied(uint256 indexed epoch, uint256 indexed nodeIds, uint256 amount);
    event DisputerRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event LeaderNotExecutedPenaltyApplied(uint256 indexed epoch, address cp, uint256 amount);
    event JobNotConfirmedPenaltyApplied(uint256 indexed epoch, uint256 indexed job, uint256 amount);


    // Incentive manager functions
    function processAll() external;
}