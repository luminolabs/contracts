// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {AccessManager} from "../src/AccessManager.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {JobEscrow} from "../src/JobEscrow.sol";
import {JobManager} from "../src/JobManager.sol";
import {LeaderManager} from "../src/LeaderManager.sol";
import {LuminoToken} from "../src/LuminoToken.sol";
import {NodeEscrow} from "../src/NodeEscrow.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {WhitelistManager} from "../src/WhitelistManager.sol";
import {IJobManager} from "../src/interfaces/IJobManager.sol";
import {IEpochManager} from "../src/interfaces/IEpochManager.sol";
import {LShared} from "../src/libraries/LShared.sol";

contract JobManagerTest is Test {
    JobManager public jobManager;
    NodeManager public nodeManager;
    LeaderManager public leaderManager;
    EpochManager public epochManager;
    NodeEscrow public nodeEscrow;
    JobEscrow public jobEscrow;
    WhitelistManager public whitelistManager;
    AccessManager public accessManager;
    LuminoToken public token;

    // Test addresses
    address public admin = address(1);
    address public operator = address(2);
    address public cp1 = address(3);
    address public cp2 = address(4);
    address public jobSubmitter = address(5);

    // Constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant COMPUTE_RATING = 10;
    uint256 public constant STAKE_AMOUNT = 100 ether;
    uint256 public constant JOB_DEPOSIT = 10 ether;
    string public constant MODEL_NAME_1 = "llm_llama3_1_8b";
    string public constant MODEL_NAME_2 = "llm_llama3_2_1b";

    // Events to test
    event JobSubmitted(uint256 indexed jobId, address indexed submitter, uint256 requiredPool);
    event JobStatusUpdated(uint256 indexed jobId, IJobManager.JobStatus status);
    event JobAssigned(uint256 indexed jobId, uint256 indexed nodeId);
    event AssignmentRoundStarted(uint256 indexed epoch);
    event JobConfirmed(uint256 indexed jobId, uint256 indexed nodeId);
    event JobCompleted(uint256 indexed jobId, uint256 indexed nodeId);
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);
    event JobTokensSet(uint256 indexed jobId, uint256 numTokens);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        token = new LuminoToken();
        accessManager = new AccessManager();
        epochManager = new EpochManager();
        nodeEscrow = new NodeEscrow(address(accessManager), address(token));
        jobEscrow = new JobEscrow(address(accessManager), address(token));
        whitelistManager = new WhitelistManager(address(accessManager));

        nodeManager = new NodeManager(
            address(nodeEscrow),
            address(whitelistManager),
            address(accessManager)
        );

        leaderManager = new LeaderManager(
            address(epochManager),
            address(nodeManager),
            address(nodeEscrow),
            address(accessManager),
            address(whitelistManager)
        );

        jobManager = new JobManager(
            address(nodeManager),
            address(leaderManager),
            address(epochManager),
            address(jobEscrow),
            address(accessManager)
        );

        // Setup roles
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(jobManager));

        // Whitelist CPs
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);

        // Fund accounts
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(jobSubmitter, INITIAL_BALANCE);

        vm.stopPrank();

        // Setup nodes
        _setupNode(cp1);
        _setupNode(cp2);
    }

    // Helper function to setup a node with proper staking and registration
    function _setupNode(address cp) internal {
        vm.startPrank(cp);

        // Stake tokens
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);

        // Register node
        nodeManager.registerNode(COMPUTE_RATING);

        vm.stopPrank();
    }

    function testSubmitJob() public {
        vm.startPrank(jobSubmitter);

        // Deposit funds for job
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);

        // Test event emission
        vm.expectEmit(true, true, false, true);
        emit JobSubmitted(1, jobSubmitter, COMPUTE_RATING);

        // Submit job
        uint256 jobId = jobManager.submitJob(
            "test job args",
            MODEL_NAME_1,
            COMPUTE_RATING
        );

        assertGt(jobId, 0, "Job ID should be greater than 0");
        assertEq(jobManager.getAssignedNode(jobId), 0, "New job should not have assigned node");

        vm.stopPrank();
    }

    function testGetJobStatus() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        IJobManager.JobStatus status = jobManager.getJobStatus(jobId);
        assertEq(uint256(status), uint256(IJobManager.JobStatus.NEW), "Initial job status should be NEW");
    }

    function testGetJobDetails() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job args", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        IJobManager.Job memory job = jobManager.getJobDetails(jobId);
        assertEq(job.id, jobId);
        assertEq(job.submitter, jobSubmitter);
        assertEq(job.assignedNode, 0);
        assertEq(uint256(job.status), uint256(IJobManager.JobStatus.NEW));
        assertEq(job.requiredPool, COMPUTE_RATING);
        assertEq(job.args, "test job args");
        assertEq(job.base_model_name, MODEL_NAME_1);
        assertEq(job.tokenCount, 0);
        assertEq(job.createdAt, block.timestamp);
    }

    function testGetJobsDetailsByNode() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job args", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        IJobManager.Job[] memory jobs = jobManager.getJobsDetailsByNode(assignedNode);

        assertEq(jobs.length, 1, "Should return one job");
        assertEq(jobs[0].id, jobId, "Job ID should match");
        assertEq(jobs[0].submitter, jobSubmitter, "Submitter should match");
        assertEq(jobs[0].assignedNode, assignedNode, "Assigned node should match");
        assertEq(uint256(jobs[0].status), uint256(IJobManager.JobStatus.ASSIGNED), "Status should be ASSIGNED");
        assertEq(jobs[0].requiredPool, COMPUTE_RATING, "Required pool should match");
        assertEq(jobs[0].args, "test job args", "Args should match");
        assertEq(jobs[0].base_model_name, MODEL_NAME_1, "Model name should match");
        assertEq(jobs[0].tokenCount, 0, "Token count should be 0");
        assertGt(jobs[0].createdAt, 0, "Created at should be set");
    }

    function testGetJobsBySubmitter() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 2);
        jobEscrow.deposit(JOB_DEPOSIT * 2);

        uint256 jobId1 = jobManager.submitJob("job 1", MODEL_NAME_1, COMPUTE_RATING);
        uint256 jobId2 = jobManager.submitJob("job 2", MODEL_NAME_2, COMPUTE_RATING);
        vm.stopPrank();

        uint256[] memory jobs = jobManager.getJobsBySubmitter(jobSubmitter);
        assertEq(jobs.length, 2);
        assertEq(jobs[0], jobId1);
        assertEq(jobs[1], jobId2);

        uint256[] memory noJobs = jobManager.getJobsBySubmitter(address(6));
        assertEq(noJobs.length, 0);
    }

    function testStartAssignmentRound() public {
        // Submit a job first
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        // Setup leader election
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(1, commitment);

        // Move to reveal phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        leaderManager.revealSecret(1, secret);

        // Move to elect phase and elect leader
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        uint256 leaderId = leaderManager.electLeader();
        address leader = nodeManager.getNodeOwner(leaderId);

        // Move to execute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION);

        vm.startPrank(leader);

        // Test event emission
        vm.expectEmit(true, false, false, true);
        emit AssignmentRoundStarted(epochManager.getCurrentEpoch());

        // Start assignment round
        jobManager.startAssignmentRound();

        // Verify job was assigned
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        assertGt(assignedNode, 0, "Job should be assigned to a node");

        vm.stopPrank();
    }

    function testConfirmJob() public {
        // Setup: submit and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Get assigned node
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Move to confirm phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);

        vm.startPrank(nodeOwner);

        // Test event emission
        vm.expectEmit(true, true, false, true);
        emit JobConfirmed(jobId, assignedNode);

        // Confirm job
        jobManager.confirmJob(jobId);

        // Verify status
        assertEq(
            uint256(jobManager.getJobStatus(jobId)),
            uint256(IJobManager.JobStatus.CONFIRMED),
            "Job status should be CONFIRMED"
        );

        vm.stopPrank();
    }

    function testInvalidConfirmation() public {
        // Setup: submit and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Move to confirm phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);

        // Try to confirm from wrong address
        vm.startPrank(jobSubmitter);
        vm.expectRevert(); // Should revert as jobSubmitter is not the assigned node owner
        jobManager.confirmJob(jobId);
        vm.stopPrank();
    }

    function testConfirmJobWrongState() public {
        // Setup: submit and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Get assigned node
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Try confirming in EXECUTE phase instead of CONFIRM phase
        vm.startPrank(nodeOwner);
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.CONFIRM)));
        jobManager.confirmJob(jobId);
        vm.stopPrank();
    }

    function testCompleteJob() public {
        // Setup: submit, assign and confirm job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Get assigned node
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Move to confirm phase and confirm job
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.prank(nodeOwner);
        jobManager.confirmJob(jobId);

        vm.startPrank(nodeOwner);

        // Test event emission
        vm.expectEmit(true, true, false, true);
        emit JobCompleted(jobId, assignedNode);

        // Complete job
        jobManager.completeJob(jobId);

        // Verify status
        assertEq(
            uint256(jobManager.getJobStatus(jobId)),
            uint256(IJobManager.JobStatus.COMPLETE),
            "Job status should be COMPLETE"
        );

        vm.stopPrank();
    }

    function testCompleteJobInvalidStatus() public {
        // Setup: submit and assign job (no confirmation)
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Get assigned node
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Move to confirm phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);

        // Try to complete without confirming first
        vm.startPrank(nodeOwner);
        vm.expectRevert(abi.encodeWithSignature(
            "InvalidStatusTransition(uint8,uint8)",
            uint8(IJobManager.JobStatus.ASSIGNED),
            uint8(IJobManager.JobStatus.CONFIRMED)
        ));
        jobManager.completeJob(jobId);
        vm.stopPrank();
    }

    function testSetTokenCountForJob() public {
        // Setup: submit, assign and confirm job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Get assigned node
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Set token count
        uint256 tokenCount = 1000000; // 1M tokens
        vm.startPrank(nodeOwner);
        
        // Test event emission
        vm.expectEmit(true, false, false, true);
        emit JobTokensSet(jobId, tokenCount);
        
        jobManager.setTokenCountForJob(jobId, tokenCount);
        vm.stopPrank();

        // Verify token count
        IJobManager.Job memory job = jobManager.getJobDetails(jobId);
        assertEq(job.tokenCount, tokenCount, "Token count should be set");
    }

    function testProcessPayment() public {
        // Setup: submit, assign, confirm and complete job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Get assigned node
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Complete job
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId);
        jobManager.completeJob(jobId);
        jobManager.setTokenCountForJob(jobId, 1000000); // 1M tokens
        vm.stopPrank();

        // Record balances before payment
        uint256 nodeOwnerBalanceBefore = jobEscrow.getBalance(nodeOwner);
        uint256 submitterBalanceBefore = jobEscrow.getBalance(jobSubmitter);

        // Process payment
        jobManager.processPayment(jobId);

        // Verify payment
        assertGt(jobEscrow.getBalance(nodeOwner), nodeOwnerBalanceBefore, "Node owner balance should increase");
        assertLt(jobEscrow.getBalance(jobSubmitter), submitterBalanceBefore, "Job submitter balance should decrease");
    }

    function testCannotProcessPaymentTwice() public {
        // Setup complete job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId);
        jobManager.completeJob(jobId);
        jobManager.setTokenCountForJob(jobId, 1000000);
        vm.stopPrank();

        // Process payment first time
        jobManager.processPayment(jobId);

        // Try to process payment again
        vm.expectRevert(abi.encodeWithSignature("JobAlreadyProcessed(uint256)", jobId));
        jobManager.processPayment(jobId);
    }

    function testProcessPaymentNotComplete() public {
        // Setup assigned job but do not complete it
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Try to process payment for a job that's not complete
        vm.expectRevert(abi.encodeWithSignature("JobNotComplete(uint256)", jobId));
        jobManager.processPayment(jobId);
    }

    function testNodeCanPickUpNewJobAfterCompletion() public {
        // Submit first job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 2);
        jobEscrow.deposit(JOB_DEPOSIT * 2);
        uint256 jobId1 = jobManager.submitJob("job 1", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();

        // Assign first job
        _setupAssignment();

        // Get assigned node for job 1
        uint256 assignedNode1 = jobManager.getAssignedNode(jobId1);
        assertGt(assignedNode1, 0, "Job 1 should be assigned");
        
        // Complete job 1
        address nodeOwner = nodeManager.getNodeOwner(assignedNode1);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId1);
        jobManager.completeJob(jobId1);
        vm.stopPrank();

        // Move to next epoch
        vm.warp(block.timestamp + LShared.CONFIRM_DURATION + LShared.DISPUTE_DURATION);
        
        // Submit second job
        vm.startPrank(jobSubmitter);
        uint256 jobId2 = jobManager.submitJob("job 2", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();
        
        // Verify job 2 is not assigned yet
        assertEq(jobManager.getAssignedNode(jobId2), 0, "Job 2 should not be assigned yet");
        
        // Set up new leader election and assignment
        _setupAssignment();

        // Verify job 2 is now assigned
        uint256 assignedNode2 = jobManager.getAssignedNode(jobId2);
        assertGt(assignedNode2, 0, "Job 2 should be assigned after job 1 is completed");
    }

    function testInvalidModelName() public {
        // Setup: submit job with invalid model name
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        
        uint256 jobId = jobManager.submitJob("test job", "invalid_model", COMPUTE_RATING);
        vm.stopPrank();
        
        // Assign job
        _setupAssignment();
        
        // Complete job
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId);
        jobManager.completeJob(jobId);
        jobManager.setTokenCountForJob(jobId, 1000000); // 1M tokens
        vm.stopPrank();
        
        // Try to process payment with invalid model
        vm.expectRevert(abi.encodeWithSignature("InvalidModelName(string)", "invalid_model"));
        jobManager.processPayment(jobId);
    }

    // function testNodeInactivity() public {
    //     // Set the initial time to start at epoch 31 (to avoid underflow)
    //     uint256 startEpoch = 50;
    //     vm.warp((startEpoch - 1) * LShared.EPOCH_DURATION);
        
    //     // Verify we're in the expected epoch
    //     assertEq(epochManager.getCurrentEpoch(), startEpoch, "Should start at specified epoch");
        
    //     // Epoch 31: Set up CP1 as active
    //     for (uint i = 0; i < 30; i++) {
    //         vm.startPrank(cp1);
    //         console.log(i);
    //         bytes memory secret = bytes(abi.encodePacked(i));
    //         bytes32 commitment = keccak256(secret);
    //         leaderManager.submitCommitment(1, commitment);
    //         vm.stopPrank();

    //         vm.warp((startEpoch * (i+1) * LShared.EPOCH_DURATION) + LShared.COMMIT_DURATION);
    
    //         vm.startPrank(cp1);
    //         leaderManager.revealSecret(1, bytes(abi.encodePacked(i)));
    //         vm.stopPrank();        
    //     }
        
        
    //     // Now, check inactivity - should be 0 because node just revealed
    //     uint256 inactivity = jobManager.getNodeInactivityEpochs(1);
    //     assertEq(inactivity, 0, "Active node should have 0 inactivity epochs");
        
    //     // Move to next epoch where the node doesn't participate
    //     vm.warp((startEpoch + 1) * LShared.EPOCH_DURATION);
    //     assertEq(epochManager.getCurrentEpoch(), startEpoch + 1, "Should be in next epoch");
        
    //     // Check inactivity - should be 1 since it was active in epoch 31 but not in epoch 32
    //     uint256 inactivityAfter = jobManager.getNodeInactivityEpochs(1);
    //     assertEq(inactivityAfter, 1, "Node should have 1 inactivity epoch after not participating");
    // }
    
    function testWasAssignmentRoundStarted() public {
        // Setup leader election
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(1, commitment);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(1, secret);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        uint256 leaderId = leaderManager.electLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // Move to execute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        
        // Check before assignment round
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        assertEq(jobManager.wasAssignmentRoundStarted(currentEpoch), false, "Assignment round should not be started initially");
        
        // Start assignment round
        vm.startPrank(leader);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // Check after assignment round
        assertEq(jobManager.wasAssignmentRoundStarted(currentEpoch), true, "Assignment round should be marked as started");
    }
    
    function testMultipleJobsAssignment() public {
        // 1. Submit one job first
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 3);
        jobEscrow.deposit(JOB_DEPOSIT * 3);
        
        uint256 jobId1 = jobManager.submitJob("test job 1", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();
        
        // 2. Assign first job
        _setupAssignment();
        
        // 3. Verify first job assignment
        uint256 assignedNodeId1 = jobManager.getAssignedNode(jobId1);
        assertTrue(assignedNodeId1 > 0, "Job 1 should be assigned");
        
        // Complete first job to free up the node
        address nodeOwner1 = nodeManager.getNodeOwner(assignedNodeId1);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner1);
        jobManager.confirmJob(jobId1);
        jobManager.completeJob(jobId1);
        vm.stopPrank();
        
        // Move to next epoch
        vm.warp(block.timestamp + LShared.CONFIRM_DURATION + LShared.DISPUTE_DURATION);
        
        // Submit second job
        vm.startPrank(jobSubmitter);
        uint256 jobId2 = jobManager.submitJob("test job 2", MODEL_NAME_2, COMPUTE_RATING);
        vm.stopPrank();
        
        // Assign second job
        _setupAssignment();
        
        // Verify second job assignment
        uint256 assignedNodeId2 = jobManager.getAssignedNode(jobId2);
        assertTrue(assignedNodeId2 > 0, "Job 2 should be assigned");
        
        // Get jobs by node for the assigned node
        IJobManager.Job[] memory assignedJobs = jobManager.getJobsDetailsByNode(assignedNodeId2);
        
        // Verify node has assigned jobs
        assertTrue(assignedJobs.length > 0, "Node should have assigned jobs");
        assertEq(assignedJobs[0].id, jobId2, "Node should be assigned job 2");
    }

    // Helper function to setup job assignment
    function _setupAssignment() internal {
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(1, commitment);

        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        leaderManager.revealSecret(1, secret);

        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        uint256 leaderId = leaderManager.electLeader();
        address leader = nodeManager.getNodeOwner(leaderId);

        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        vm.startPrank(leader);
        jobManager.startAssignmentRound();
        vm.stopPrank();
    }
}