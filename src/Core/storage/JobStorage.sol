// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";
import "./Constants.sol";

abstract contract JobStorage is Constants {
    
    // Mapping for jobId -> jobInfo
    mapping(uint256 => Structs.Job) public jobs;

    // Mapping for jobId -> jobStatus
    mapping(uint256 => Status) public jobStatus;
    
    // Array to keep track of active job IDs
    uint256[] public activeJobIds;
    
    // Counter for job IDs
    uint256 public jobIdCounter;

    // Number of jobs to assign per staker
    uint8 public jobsPerStaker;

}
