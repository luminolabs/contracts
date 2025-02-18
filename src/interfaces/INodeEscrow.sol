// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEscrow} from "./IEscrow.sol";

interface INodeEscrow is IEscrow {
    // Events
    event PenaltyApplied(address indexed cp, uint256 amount, uint256 newBalance);

    // Stake escrow functions
    function applyPenalty(address cp, uint256 amount) external;
}