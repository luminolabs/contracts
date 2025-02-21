// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AEscrow} from "./abstracts/AEscrow.sol";
import {IEscrow} from "./interfaces/IEscrow.sol";
import {INodeEscrow} from "./interfaces/INodeEscrow.sol";
import {LShared} from "./libraries/LShared.sol";

contract NodeEscrow is AEscrow, INodeEscrow {
    constructor(address _accessManager, address _token) AEscrow(_accessManager, _token) {}

    /**
     * @notice Apply a penalty to a CP's stake for minor infractions
     */
    function applyPenalty(
        address cp,
        uint256 amount,
        string calldata reason
    ) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);

        if (balances[cp] < amount) {
            revert InsufficientBalance(cp, amount, balances[cp]);
        }

        balances[cp] -= amount;
        emit PenaltyApplied(cp, amount, balances[cp], reason);
    }

    /**
     * @notice Apply a slash to a CP's stake for serious infractions
     */
    function applySlash(
        address cp,
        string calldata reason
    ) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);

        balances[cp] = 0;
        emit SlashApplied(cp, balances[cp], reason);
    }

    /**
     * @notice Apply a reward to a CP's stake
     */
    function applyReward(
        address cp,
        uint256 amount,
        string calldata reason
    ) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);

        balances[cp] += amount;
        emit RewardApplied(cp, amount, balances[cp], reason);
    }

    /**
     * @notice Returns the name of this escrow; used for events in the parent contract
     */
    function getEscrowName() internal pure override returns (string memory) {
        return "stake";
    }
}