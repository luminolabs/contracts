// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/JobsManager.sol";
import "../src/Core/StakeManager.sol";
import "../src/Core/storage/Constants.sol";

contract JobsManagerTest is Test, Constants {
    JobsManager public jobsManager;
    StakeManager public stakeManager;
    address public admin;
    address public user1;
    address public user2;
    uint8 public constant BUFFER = 5;

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy & initialize contracts in the correct order
        // 1. Deploy StakeManager
        stakeManager = new StakeManager();
        
        // 2. Deploy JobsManager
        jobsManager = new JobsManager();
        
        // 3. Initialize both with correct references to each other
        stakeManager.initialize(address(jobsManager));
        jobsManager.initialize(5, address(stakeManager));

        vm.prank(admin);
        jobsManager.grantRole(jobsManager.DEFAULT_ADMIN_ROLE(), admin);
    }

    function testInitialization() public view {
        assertEq(jobsManager.jobsPerStaker(), 5);
        assertTrue(jobsManager.hasRole(jobsManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(jobsManager.jobIdCounter(), 1);
    }

    function testCreateJob() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        assertEq(jobId, 1);
        assertEq(jobsManager.jobIdCounter(), 2);

        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(job.creator, user1);
        assertEq(job.jobDetailsInJSON, "Test Job Details");
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.NEW));
        
        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        assertEq(activeJobs.length, 1);
        assertEq(activeJobs[0], jobId);
    }

    function testUpdateJobStatus() public {
        // First, register user1 as a staker
        vm.deal(user1, 10 ether); // Give user1 some ETH to stake
        vm.prank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");

        // Create a job
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        // Assign job (in Assign state)
        uint256 assignTime = (EPOCH_LENGTH / NUM_STATES) / 2; // Middle of Assign state
        vm.warp(assignTime);
        vm.prank(admin);
        jobsManager.assignJob(jobId, user1, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.QUEUED));

        // Update to RUNNING (in Update state)
        uint256 updateTime = (EPOCH_LENGTH / NUM_STATES) + (EPOCH_LENGTH / NUM_STATES / 2);
        vm.warp(updateTime);
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.RUNNING, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.RUNNING));

        // Complete job (in Confirm state)
        uint256 confirmTime = 2 * (EPOCH_LENGTH / NUM_STATES) + (EPOCH_LENGTH / NUM_STATES / 2);
        vm.warp(confirmTime);
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.COMPLETED, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.COMPLETED));
    }

    function testUpdateJobStatusInvalidTransition() public {
        // First, register user1 as a staker
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");

        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        // Try to update status without being in the correct state
        uint256 wrongTime = (EPOCH_LENGTH / NUM_STATES) / 2; // In Assign state
        vm.warp(wrongTime);
        vm.prank(user1);
        vm.expectRevert("Only assignee can update the jobStatus");
        jobsManager.updateJobStatus(jobId, Status.RUNNING, BUFFER);
    }

    function testUpdateNonExistentJob() public {
        vm.prank(admin);
        vm.expectRevert("Job does not exist");
        jobsManager.updateJobStatus(999, Status.QUEUED, BUFFER);
    }

    function testUpdateJobStatusUnauthorized() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Test Job Details");

        vm.prank(user2);
        vm.expectRevert("Only assignee can update the jobStatus");
        jobsManager.updateJobStatus(jobId, Status.QUEUED, BUFFER);
    }

    function testCreateMultipleJobs() public {
        uint256 numJobs = 5;
        for (uint256 i = 0; i < numJobs; i++) {
            vm.prank(user1);
            jobsManager.createJob(string(abi.encodePacked("Job ", vm.toString(i))));
        }

        assertEq(jobsManager.jobIdCounter(), numJobs + 1);
        assertEq(jobsManager.getActiveJobs().length, numJobs);
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

    function testJobDetailsRetrieval() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob("Detailed Job Info");

        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(job.jobId, jobId);
        assertEq(job.creator, user1);
        assertEq(job.assignee, address(0));
        assertEq(job.creationEpoch, jobsManager.getEpoch());
        assertEq(job.executionEpoch, 0);
        assertEq(job.proofGenerationEpoch, 0);
        assertEq(job.conclusionEpoch, 0);
        assertEq(job.jobDetailsInJSON, "Detailed Job Info");
    }

    function testNonExistentJobDetails() public {
        vm.expectRevert("Job does not exist");
        jobsManager.getJobDetails(999);
    }
}