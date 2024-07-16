// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

contract StakeManagerStorage is Structs {
    // total number of staker; used as counter as well
    uint32 public numStaker;

    // mapping of stakerAddress -> stakerId
    mapping(address => uint32) public stakerIds;

    // mapping of stakerAddress -> stakerId
    mapping(uint32 => Structs.Staker) public stakers;
}
