// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface INodeStakingManager {
    event StakeRequirementUpdated(address indexed cp, uint256 newRequirement);
    event StakeValidated(address indexed cp, uint256 nodeId, bool valid);

    function calculateRequiredStake(uint256 computeRating) external pure returns (uint256);
    function validateStake(address cp, uint256 computeRating) external view returns (bool);
    function updateStakeRequirement(address cp, uint256 newRequirement) external;
    function getTotalRequiredStake(address cp) external view returns (uint256);
    function getStakeRequirementForRating(uint256 computeRating) external pure returns (uint256);
}