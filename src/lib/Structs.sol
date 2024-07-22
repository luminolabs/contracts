// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Structs {
    struct Staker {
        bool isSlashed;
        address _address;
        // address tokenAddress;
        uint32 id;
        uint32 age;
        uint32 epochFirstStaked;
        uint32 epochLastPenalized;
        uint256 stake;
        uint256 stakerReward;
        string machineSpecInJSON;
    }

    struct Lock {
        uint256 amount;
        uint256 unlockAfter;
    }
}
