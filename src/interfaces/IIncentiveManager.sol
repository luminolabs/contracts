// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IIncentiveManager {
    // Incentive manager functions
    function processAll(uint256 epoch) external;
}