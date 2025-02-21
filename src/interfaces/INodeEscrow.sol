// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEscrow} from "./IEscrow.sol";

interface INodeEscrow is IEscrow {
    // Events
    event PenaltyApplied(address indexed cp, uint256 amount, uint256 newBalance, string reason);
    event SlashApplied(address indexed cp, uint256 newBalance, string reason);
    event RewardApplied(address indexed cp, uint256 amount, uint256 newBalance, string reason);

    // Functions
    function applyPenalty(address cp, uint256 amount, string calldata reason) external;
    function applySlash(address cp, string calldata reason) external;
    function applyReward(address cp, uint256 amount, string calldata reason) external;
}