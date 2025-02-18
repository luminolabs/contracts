// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LuminoToken} from "../LuminoToken.sol";
import {IAccessManager} from "./IAccessManager.sol";

interface IIncentiveTreasury {
    // Events
    event RewardDistributed(address indexed recipient, uint256 amount, string reason);
    event PenaltyApplied(address indexed offender, uint256 amount, string reason);

    // Errors
    error InsufficientBalance(address offender, uint256 requested, uint256 available);
    error TransferFailed();

    // Functions
    function distributeReward(address recipient, uint256 amount, string calldata reason) external;
    function applyPenalty(address offender, uint256 amount, string calldata reason) external;
    function getBalance() external view returns (uint256);
}