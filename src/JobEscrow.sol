// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AEscrow} from "./abstracts/AEscrow.sol";
import {IJobEscrow} from "./interfaces/IJobEscrow.sol";
import {LShared} from "./libraries/LShared.sol";

contract JobEscrow is AEscrow, IJobEscrow {
    constructor (address _accessManager, address _token) AEscrow(_accessManager, _token) {}

    /**
      * @notice Release payment to a worker
      */
    function releasePayment(address from, address to, uint256 amount) external {
        accessManager.requireRole(LShared.CONTRACTS_ROLE, msg.sender);
        requireBalance(from, amount);

        balances[from] -= amount;
        balances[to] += amount;

        emit PaymentReleased(from, to, amount);
    }

    /**
     * @notice Returns the name of this escrow; used for events in the parent contract
     */
    function getEscrowName() internal override pure returns (string memory) {
        return "job";
    }
}