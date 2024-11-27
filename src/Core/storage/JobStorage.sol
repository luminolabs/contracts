// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";
import "./Constants.sol";

/**
 * @title JobStorage
 * @notice Manages the storage of job-related data for the Lumino network
 * @dev This contract is intended to be inherited by the JobsManager contract
 */
abstract contract JobStorage is Constants {

    /**
     * @notice Stores job information for each job ID
     * @dev Mapping of jobId -> Job struct
     */
    mapping(uint256 => Structs.Job) public jobs;

    /**
     * @notice Tracks the current status of each job
     * @dev Mapping of jobId -> Status enum
     */
    mapping(uint256 => Status) public jobStatus;

    mapping (address => uint256) assignedJob;

    /**
     * @notice List of all active job IDs
     * @dev Used to iterate over active jobs efficiently
     */
    uint256[] public activeJobIds;

    /**
     * @notice Counter for generating unique job IDs
     * @dev Incremented each time a new job is created
     */
    uint256 public jobIdCounter;

    /**
     * @notice Number of jobs to assign per staker in each epoch
     * @dev This value can be adjusted to balance workload and network capacity
     */
    uint8 public jobsPerStaker;
   
}