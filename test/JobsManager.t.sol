// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/JobsManager.sol";
import "../src/Core/StakeManager.sol";
import "../src/Core/StateManager.sol";
import "../src/Core/storage/Constants.sol";
import "forge-std/console.sol";

contract JobsManagerTest is Test, Constants, StateManager {
    JobsManager public jobsManager;
    StakeManager public stakeManager;
    address public admin;
    address public user1;
    address public user2;
    uint8 public constant BUFFER = 5;

    event JobCreated(uint256 indexed jobId, address indexed creator, uint32 epoch);
    event JobStatusUpdated(uint256 indexed jobId, Status newStatus);
    event JobAssigned(uint256 indexed jobId, address indexed assigneeAddress);

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy contracts
        stakeManager = new StakeManager();
        jobsManager = new JobsManager();
        
        // Initialize contracts
        stakeManager.initialize(address(jobsManager));
        jobsManager.initialize(5, address(stakeManager));

        // Setup roles
        jobsManager.grantRole(jobsManager.DEFAULT_ADMIN_ROLE(), admin);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testInitialization() public view {
        assertEq(jobsManager.jobsPerStaker(), 5);
        assertTrue(jobsManager.hasRole(jobsManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(jobsManager.jobIdCounter(), 1);
    }

    function testCreateJob() public {
        uint256 jobFee = 1 ether;
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, true, true);
        emit JobCreated(1, user1, 0);
        
        uint256 jobId = jobsManager.createJob{value: jobFee}("Test Job Details");
        vm.stopPrank();

        assertEq(jobId, 1);
        assertEq(jobsManager.jobIdCounter(), 2);

        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(job.creator, user1);
        assertEq(job.jobDetailsInJSON, "Test Job Details");
        assertEq(job.jobFee, jobFee);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.NEW));
        
        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        assertEq(activeJobs.length, 1);
        assertEq(activeJobs[0], jobId);
    }

    function testAssignJob() public {
        // Setup staker
        vm.startPrank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");
        vm.stopPrank();

        // Create job
        vm.prank(user2);
        uint256 jobId = jobsManager.createJob{value: 1 ether}("Test Job");

        // Move to Assign state
        uint256 assignTime = (EPOCH_LENGTH / NUM_STATES) / 2;
        vm.warp(assignTime);

        // Assign job
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true);
        emit JobAssigned(jobId, user1);
        jobsManager.assignJob(jobId, user1, BUFFER);
        vm.stopPrank();

        // Verify assignment
        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(job.assignee, user1);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.QUEUED));
        assertEq(jobsManager.getJobForStaker(user1), jobId);
    }

    function testJobStatusTransitions() public {
        // Setup staker
        vm.startPrank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");
        vm.stopPrank();

        // Create and assign job
        vm.prank(user2);
        uint256 jobId = jobsManager.createJob{value: 1 ether}("Test Job");

        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;

        // Assign state
        vm.warp(stateLength / 2);
        vm.prank(admin);
        jobsManager.assignJob(jobId, user1, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.QUEUED));

        // Update state - Set to RUNNING
        vm.warp(stateLength + (stateLength / 2));
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit JobStatusUpdated(jobId, Status.RUNNING);
        jobsManager.updateJobStatus(jobId, Status.RUNNING, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.RUNNING));

        // Confirm state - Complete job
        vm.warp(2 * stateLength + (stateLength / 2));
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.COMPLETED, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.COMPLETED));
    }

    function testFailedJobStatus() public {
        // Setup staker
        vm.startPrank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");
        vm.stopPrank();

        // Create and assign job
        vm.prank(user2);
        uint256 jobId = jobsManager.createJob{value: 1 ether}("Test Job");

        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;

        // Assign job in Assign state (first state)
        uint256 assignTime = (stateLength / 2); // Middle of Assign state
        vm.warp(assignTime);
        vm.prank(admin);
        jobsManager.assignJob(jobId, user1, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.QUEUED), "Job should be QUEUED after assignment");

        // Update to RUNNING in Update state (second state)
        uint256 updateTime = stateLength + (stateLength / 2); // Middle of Update state
        vm.warp(updateTime);
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.RUNNING, BUFFER);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.RUNNING), "Job should be RUNNING after update");

        // Set to FAILED in Confirm state (third state)
        uint256 confirmTime = 2 * stateLength + (stateLength / 2); // Middle of Confirm state
        vm.warp(confirmTime);
        
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.FAILED, BUFFER);
        
        // Verify job is properly failed
        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(uint(jobsManager.getJobStatus(jobId)), uint(Status.FAILED), "Job status should be FAILED");
        assertTrue(job.conclusionEpoch > 0, "Conclusion epoch should be set");
        assertEq(job.assignee, user1, "Assignee should remain unchanged");
    } 

    function testJobReward() public {
        // Setup staker
        vm.startPrank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");
        vm.stopPrank();

        // Create job with fee
        uint256 jobFee = 1 ether;
        vm.prank(user2);
        uint256 jobId = jobsManager.createJob{value: jobFee}("Test Job");

        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        
        // Assign job
        vm.warp(stateLength / 2);
        vm.prank(admin);
        jobsManager.assignJob(jobId, user1, BUFFER);

        // Complete job successfully
        vm.warp(stateLength + (stateLength / 2));
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.RUNNING, BUFFER);

        vm.warp(2 * stateLength + (stateLength / 2));
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        jobsManager.updateJobStatus(jobId, Status.COMPLETED, BUFFER);

        // Verify reward transfer
        assertEq(user1.balance - balanceBefore, jobFee);
    }

    function testInvalidStateTransitions() public {
        // Setup staker
        vm.startPrank(user1);
        stakeManager.stake{value: 10 ether}(0, 10 ether, "test-spec");
        vm.stopPrank();

        // Create job
        vm.prank(user2);
        uint256 jobId = jobsManager.createJob{value: 1 ether}("Test Job");

        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;

        // Try to complete job without assignment
        vm.warp(2 * stateLength + (stateLength / 2));
        vm.prank(user1);
        vm.expectRevert("Only assignee can update the jobStatus");
        jobsManager.updateJobStatus(jobId, Status.COMPLETED, BUFFER);

        // Try to assign in wrong state
        vm.warp(stateLength + (stateLength / 2));
        vm.prank(admin);
        vm.expectRevert("Can only assign job in Assign State");
        jobsManager.assignJob(jobId, user1, BUFFER);
    }

    function testGetJobDetails() public {
        vm.prank(user1);
        uint256 jobId = jobsManager.createJob{value: 1 ether}("Test Job");

        Structs.Job memory job = jobsManager.getJobDetails(jobId);
        assertEq(job.jobId, jobId);
        assertEq(job.creator, user1);
        assertEq(job.assignee, address(0));
        assertEq(job.jobFee, 1 ether);
        assertEq(job.jobDetailsInJSON, "Test Job");
    }

    function testMultipleJobs() public {
        uint256 numJobs = 5;
        for (uint256 i = 0; i < numJobs; i++) {
            vm.prank(user1);
            jobsManager.createJob{value: 1 ether}(string(abi.encodePacked("Job ", vm.toString(i))));
        }

        assertEq(jobsManager.jobIdCounter(), numJobs + 1);
        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        assertEq(activeJobs.length, numJobs);
    }

    function testInvalidJobOperations() public {
        // Test non-existent job
        vm.expectRevert("Job does not exist");
        jobsManager.getJobDetails(999);

        // Test unauthorized job assignment
        vm.prank(user2);
        uint256 jobId = jobsManager.createJob{value: 1 ether}("Test Job");
        
        vm.prank(user1);
        vm.expectRevert("Job assigner Role required to assignJob");
        jobsManager.assignJob(jobId, user1, BUFFER);
    }
}