// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LuminoToken} from "./LuminoToken.sol";
import {AEscrow} from "./abstracts/AEscrow.sol";
import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IEscrow} from "./interfaces/IEscrow.sol";
import {INodeEscrow} from "./interfaces/INodeEscrow.sol";
import {LShared} from "./libraries/LShared.sol";

contract NodeEscrow is AEscrow, INodeEscrow {
    constructor (address _accessController, address _token) AEscrow(_accessController, _token) {}

    /**
     * @notice Apply a penalty to a CP's stake
     */
    function applyPenalty(address cp, uint256 amount) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);
        if (balances[cp] < amount) {
            revert InsufficientBalance(cp, amount, balances[cp]);
        }

        balances[cp] -= amount;

        emit PenaltyApplied(cp, amount, balances[cp]);
    }

    // Internal functions

    /**
     * @notice Returns the name of this escrow; used for events in the parent contract
     */
    function getEscrowName() internal override pure returns (string memory) {
        return "stake";
    }
}