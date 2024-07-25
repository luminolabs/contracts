// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

contract VoteManagerStorage {
    
    /// mapping of stakerId -> commitment
    mapping(uint32 => Structs.Commitment) public commitments;

    /// mapping of epoch -> stakerid -> jobId -> vote
    mapping(uint32 => mapping(uint32 =>  Structs.AssignedJob[])) public assignedJob;

    /// mapping of epoch -> stakerid->stake
    mapping(uint32 => mapping(uint32 => uint256)) public stakeSnapshot;

    /// mapping of stakerid -> epochLastRevealed
    mapping(uint32 => uint32) public epochLastRevealed;

    /// hash of last epoch and its jobId medians
    bytes32 public salt;

    /// depth of a valid merkle tree
    uint256 public depth; // uint32 possible
}