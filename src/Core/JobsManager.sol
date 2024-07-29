// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./ACL.sol";
import "./StateManager.sol";
import "../Initializable.sol";
import "../lib/Structs.sol";
import "../Core/storage/JobStorage.sol";

contract JobsManager is Initializable, StateManager, ACL, JobStorage {

    // Events
    event JobCreated(uint256 indexed jobId, address indexed creator, uint32 epoch);
    event JobStatusUpdated(uint256 indexed jobId, Status newStatus);

    function initialize(uint8 _jobsPerStaker) external initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        jobIdCounter = 1;
        jobsPerStaker = _jobsPerStaker;
    }

    function createJob(string memory _jobDetailsInJSON) external {
        uint32 currentEpoch = getEpoch();
        uint256 newJobId = jobIdCounter++;

        jobs[newJobId] = Structs.Job({
            jobId: newJobId,
            creator: msg.sender,
            assignee: address(0),
            creationEpoch: currentEpoch,
            executionEpoch: 0,
            completionEpoch: 0,
            jobDetailsInJSON: _jobDetailsInJSON
        });
        jobStatus[newJobId] = Status.Create;

        activeJobIds.push(newJobId);

        emit JobCreated(newJobId, msg.sender, currentEpoch);
    }

    function updateJobStatus(uint256 _jobId, Status _newStatus) external {
        require(jobs[_jobId].jobId != 0, "Job does not exist");
        require(_newStatus > jobStatus[_jobId], "Invalid status transition");

        jobStatus[_jobId] = _newStatus;

        if (_newStatus == Status.Execution) {
            jobs[_jobId].executionEpoch = getEpoch();
        } else if (_newStatus == Status.Completed) {
            jobs[_jobId].completionEpoch = getEpoch();
            removeActiveJob(_jobId);
        }

        emit JobStatusUpdated(_jobId, _newStatus);
    }

    function getActiveJobs() external view returns (uint256[] memory) {
        return activeJobIds;
    }

    function getJobDetails(uint256 _jobId) external view returns (Structs.Job memory) {
        require(jobs[_jobId].jobId != 0, "Job does not exist");
        return jobs[_jobId];
    }

    function getJobStatus(uint256 _jobId) external view returns (Status) {
        return jobStatus[_jobId];
    }

    function getJobsForStaker(bytes32 _seed, uint32 _stakerId) external view returns (uint256[] memory) {
        require(activeJobIds.length >= jobsPerStaker, "Not enough active jobs");
        
        uint256[] memory assignedJobs = new uint256[](jobsPerStaker);
        for (uint8 i = 0; i < jobsPerStaker; i++) {
            uint256 index = uint256(keccak256(abi.encodePacked(_seed, _stakerId, i))) % activeJobIds.length;
            assignedJobs[i] = activeJobIds[index];
        }
        
        return assignedJobs;
    }

    function removeActiveJob(uint256 _jobId) internal {
        for (uint256 i = 0; i < activeJobIds.length; i++) {
            if (activeJobIds[i] == _jobId) {
                activeJobIds[i] = activeJobIds[activeJobIds.length - 1];
                activeJobIds.pop();
                break;
            }
        }
    }
}