// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEscrow} from "./IEscrow.sol";

interface IJobEscrow is IEscrow {
    // Events
    event PaymentReleased(address indexed from, address indexed to, uint256 amount);

    // Job escrow functions
    function releasePayment(address from, address to, uint256 amount) external;
}