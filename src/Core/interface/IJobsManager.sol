// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";
import "../storage/Constants.sol";

interface IJobsManager {

    // Events
    event JobCreated(uint256 indexed jobId, address indexed creator, uint32 epoch);
    event JobStatusUpdated(uint256 indexed jobId, Constants.Status newStatus);

    // Functions
    function initialize(uint8 _jobsPerStaker) external;
    
    function createJob(string memory _jobDetailsInJSON) external;
    
    function updateJobStatus(uint256 _jobId, Constants.Status _newStatus) external;
    
    function getActiveJobs() external view returns (uint256[] memory);
    
    function getJobDetails(uint256 _jobId) external view returns (Structs.Job memory);
    
    function getJobsForStaker(bytes32 _seed, uint32 _stakerId) external view returns (uint256[] memory);
    
    // Additional view functions
    function jobsPerStaker() external view returns (uint8);
    
    function jobIdCounter() external view returns (uint256);
}