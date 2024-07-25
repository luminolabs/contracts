// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

abstract contract StakeManagerStorage {
    // total number of staker; used as counter as well
    uint32 public numStakers;

    // mapping of stakerAddress -> stakerId
    mapping(address => uint32) public stakerIds;

    // mapping of stakerAddress -> stakerId
    mapping(uint32 => Structs.Staker) public stakers;

    // mapping of stakerAddress -> LockInfo
    mapping(address => Structs.Lock) public locks;

    struct SlashNums {
        // percent bounty from staker's stake to be received by the bounty hunter
        uint32 bounty;
        // percent RAZOR burn from staker's stake
        uint32 burn;
        // percent from staker's stake to be kept by staker
        uint32 keep;
    }
}
