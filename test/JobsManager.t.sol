// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/JobsManager.sol";
import "../src/Core/storage/Constants.sol";

contract JobsManagerTest is Test, Constants {
    JobsManager public jobsManager;
    address public admin;
    address public user1;
    address public user2;

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        jobsManager = new JobsManager();
        jobsManager.initialize(5); // Initialize with 5 jobs per staker

        vm.prank(admin);
        jobsManager.grantRole(jobsManager.DEFAULT_ADMIN_ROLE(), admin);
    }

    function testInitialization() public view {
        assertEq(jobsManager.jobsPerStaker(), 5);
        assertTrue(jobsManager.hasRole(jobsManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testCreateJob() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        assertEq(jobId, 1);
        assertEq(jobsManager.jobIdCounter(), 2);

        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(job.creator, user1);
        assertEq(job.jobDetailsInJSON, "Test Job Details");
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.Created));
    }

    function testUpdateJobStatus() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        vm.prank(admin);
        jobsManager.updateJobStatus(jobId, Status.Execution);

        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.Execution));

        vm.prank(admin);
        jobsManager.updateJobStatus(jobId, Status.Completed);

        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.Completed));
    }

    function testGetActiveJobs() public {
        vm.startPrank(user1);
        jobsManager.createJob("Job 1");
        jobsManager.createJob("Job 2");
        jobsManager.createJob("Job 3");
        vm.stopPrank();

        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        assertEq(activeJobs.length, 3);
        assertEq(activeJobs[0], 1);
        assertEq(activeJobs[1], 2);
        assertEq(activeJobs[2], 3);
    }

    function testGetJobsForStaker() public {
        // Create some jobs
        vm.startPrank(user1);
        for (uint i = 0; i < 10; i++) {
            jobsManager.createJob(string(abi.encodePacked("Job ", vm.toString(i))));
        }
        vm.stopPrank();

        bytes32 seed = keccak256("test seed");
        uint32 stakerId = 1;

        uint256[] memory assignedJobs = jobsManager.getJobsForStaker(seed, stakerId);
        assertEq(assignedJobs.length, 5); // Should match jobsPerStaker

        // Verify that all assigned jobs are valid
        for (uint i = 0; i < assignedJobs.length; i++) {
            assertTrue(assignedJobs[i] > 0 && assignedJobs[i] <= 10);
        }
    }

    function testUpdateJobStatusInvalidTransition() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        vm.expectRevert("Invalid status transition");
        vm.prank(admin);
        jobsManager.updateJobStatus(jobId, Status.Completed);
    }

    function testRemoveActiveJob() public {
        vm.startPrank(user1);
        uint256 jobId1 = jobsManager.createJob("Job 1");
        uint256 jobId2 = jobsManager.createJob("Job 2");
        uint256 jobId3 = jobsManager.createJob("Job 3");
        vm.stopPrank();

        vm.prank(admin);
        jobsManager.updateJobStatus(jobId2, Status.Execution);
        jobsManager.updateJobStatus(jobId2, Status.Completed);

        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        assertEq(activeJobs.length, 2);
        assertEq(activeJobs[0], 1);
        assertEq(activeJobs[1], 3);
    }
}