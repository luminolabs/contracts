// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/JobManager.sol";
import "../src/LeaderManager.sol";
import "../src/EpochManager.sol";
import "../src/NodeManager.sol";
import "../src/NodeEscrow.sol";
import "../src/JobEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract JobLifecycleE2ETest is Test {
    JobManager public jobManager;
    LeaderManager public leaderManager;
    EpochManager public epochManager;
    NodeManager public nodeManager;
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

    // Node tracking
    uint256[] public nodeIds;
    mapping(address => bytes) public secrets;
    mapping(address => bytes32) public commitments;

    // Constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant COMPUTE_RATING = 10;
    uint256 public constant STAKE_AMOUNT = 1000 ether;
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
    event JobRejected(uint256 indexed jobId, uint256 indexed nodeId, string reason);
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);
    event PaymentReleased(address indexed from, address indexed to, uint256 amount);
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
        
        // Initial token distribution
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(jobSubmitter, INITIAL_BALANCE);
        token.transfer(address(nodeEscrow), INITIAL_BALANCE);

        vm.stopPrank();

        // Start at a clean epoch boundary
        vm.warp(0);
        
        // Setup initial state
        _setupNodesAndLeader();
    }

    function testCompleteJobLifecycle() public {
        // Track initial balances
        uint256 submitterInitialBalance = jobEscrow.getBalance(jobSubmitter);
        
        // 1. Submit job
        vm.startPrank(jobSubmitter);
        
        vm.expectEmit(true, true, false, true);
        emit JobSubmitted(1, jobSubmitter, COMPUTE_RATING);
        
        uint256 jobId = jobManager.submitJob(
            "test job args",
            MODEL_NAME_1,
            COMPUTE_RATING
        );
        
        assertEq(jobId, 1, "Job ID should be 1");
        vm.stopPrank();
        
        // 2. Assign job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        
        // Move to EXECUTE phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        
        vm.expectEmit(true, false, false, true);
        emit AssignmentRoundStarted(epochManager.getCurrentEpoch());
        
        jobManager.startAssignmentRound();
        
        // Verify assignment
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        assertTrue(assignedNodeId > 0, "Job should be assigned to a node");
        
        vm.expectEmit(true, true, false, true);
        emit JobAssigned(jobId, assignedNodeId);
        
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        vm.stopPrank();
        
        // 3. Confirm job
        vm.startPrank(assignedNodeOwner);
        
        // Move to CONFIRM phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        
        vm.expectEmit(true, true, false, true);
        emit JobConfirmed(jobId, assignedNodeId);
        
        jobManager.confirmJob(jobId);
        
        // Verify job status
        assertEq(uint256(jobManager.getJobStatus(jobId)), uint256(IJobManager.JobStatus.CONFIRMED), 
                "Job status should be CONFIRMED");
        
        // 4. Complete job and set token count
        uint256 tokenCount = 1000000; // 1M tokens for model fee calculation
        
        vm.expectEmit(true, true, false, true);
        emit JobCompleted(jobId, assignedNodeId);
        
        jobManager.completeJob(jobId);
        
        vm.expectEmit(true, false, false, true);
        emit JobTokensSet(jobId, tokenCount);
        
        jobManager.setTokenCountForJob(jobId, tokenCount);
        
        vm.stopPrank();
        
        // Verify job status
        assertEq(uint256(jobManager.getJobStatus(jobId)), uint256(IJobManager.JobStatus.COMPLETE), 
                "Job status should be COMPLETE");
        
        // 5. Process payment
        uint256 nodeOwnerInitialBalance = jobEscrow.getBalance(assignedNodeOwner);
        
        // Calculate expected payment based on model fee
        uint256 expectedPayment = 2 ether; // MODEL_NAME_1 has fee of 2 per 1M tokens
        
        vm.expectEmit(true, true, false, true);
        emit PaymentProcessed(jobId, assignedNodeOwner, expectedPayment);
        
        vm.expectEmit(true, true, false, true);
        emit PaymentReleased(jobSubmitter, assignedNodeOwner, expectedPayment);
        
        jobManager.processPayment(jobId);
        
        // 6. Verify final balances
        assertEq(
            jobEscrow.getBalance(assignedNodeOwner) - nodeOwnerInitialBalance,
            expectedPayment,
            "Node owner should receive payment"
        );
        
        assertEq(
            submitterInitialBalance - jobEscrow.getBalance(jobSubmitter),
            expectedPayment,
            "Submitter balance should decrease by payment amount"
        );
    }

    function testJobRejection() public {
        // 1. Submit job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob(
            "test job args",
            MODEL_NAME_1,
            COMPUTE_RATING
        );
        vm.stopPrank();
        
        // 2. Assign job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Reject job
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        vm.startPrank(assignedNodeOwner);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        
        string memory rejectionReason = "Insufficient resources";
        
        vm.expectEmit(true, true, false, true);
        emit JobRejected(jobId, assignedNodeId, rejectionReason);
        
        jobManager.rejectJob(jobId, rejectionReason);
        vm.stopPrank();
        
        // 4. Verify job status reset
        assertEq(jobManager.getAssignedNode(jobId), 0, "Job should be unassigned after rejection");
        assertEq(uint256(jobManager.getJobStatus(jobId)), uint256(IJobManager.JobStatus.NEW), 
                "Job status should be reset to NEW");
    }

    function testMultipleJobsAssignment() public {
        // 1. Submit multiple jobs
        uint256[] memory jobIds = new uint256[](3);
        
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 3);
        jobEscrow.deposit(JOB_DEPOSIT * 3);
        
        for (uint256 i = 0; i < 3; i++) {
            jobIds[i] = jobManager.submitJob(
                string(abi.encodePacked("test job ", vm.toString(i + 1))),
                i % 2 == 0 ? MODEL_NAME_1 : MODEL_NAME_2,
                COMPUTE_RATING
            );
        }
        vm.stopPrank();
        
        // 2. Assign jobs
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Verify assignment distribution
        for (uint256 i = 0; i < 3; i++) {
            uint256 assignedNodeId = jobManager.getAssignedNode(jobIds[i]);
            assertTrue(assignedNodeId > 0, string(abi.encodePacked("Job ", vm.toString(i + 1), " should be assigned")));
        }
        
        // 4. Get jobs by node
        uint256 nodeId = jobManager.getAssignedNode(jobIds[0]);
        IJobManager.Job[] memory nodeJobs = jobManager.getJobsDetailsByNode(nodeId);
        
        // Verify node has assigned jobs
        assertTrue(nodeJobs.length > 0, "Node should have assigned jobs");
    }

    function testDifferentModelFees() public {
        // 1. Submit jobs with different model names
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 2);
        jobEscrow.deposit(JOB_DEPOSIT * 2);
        
        uint256 jobId1 = jobManager.submitJob("test job 1", MODEL_NAME_1, COMPUTE_RATING);
        uint256 jobId2 = jobManager.submitJob("test job 2", MODEL_NAME_2, COMPUTE_RATING);
        vm.stopPrank();
        
        // 2. Assign jobs
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Process jobs
        uint256 tokenCount = 1000000; // 1M tokens
        
        // Complete first job
        uint256 assignedNodeId1 = jobManager.getAssignedNode(jobId1);
        address assignedNodeOwner1 = nodeManager.getNodeOwner(assignedNodeId1);
        
        vm.startPrank(assignedNodeOwner1);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        jobManager.confirmJob(jobId1);
        jobManager.completeJob(jobId1);
        jobManager.setTokenCountForJob(jobId1, tokenCount);
        vm.stopPrank();
        
        // Complete second job
        uint256 assignedNodeId2 = jobManager.getAssignedNode(jobId2);
        address assignedNodeOwner2 = nodeManager.getNodeOwner(assignedNodeId2);
        
        vm.startPrank(assignedNodeOwner2);
        jobManager.confirmJob(jobId2);
        jobManager.completeJob(jobId2);
        jobManager.setTokenCountForJob(jobId2, tokenCount);
        vm.stopPrank();
        
        // 4. Process payments and verify different fees
        uint256 balance1Before = jobEscrow.getBalance(assignedNodeOwner1);
        uint256 balance2Before = jobEscrow.getBalance(assignedNodeOwner2);
        
        jobManager.processPayment(jobId1);
        jobManager.processPayment(jobId2);
        
        uint256 payment1 = jobEscrow.getBalance(assignedNodeOwner1) - balance1Before;
        uint256 payment2 = jobEscrow.getBalance(assignedNodeOwner2) - balance2Before;
        
        // MODEL_NAME_1 fee is 2 per 1M tokens
        // MODEL_NAME_2 fee is 1 per 1M tokens
        assertEq(payment1, 2 ether, "Payment for MODEL_NAME_1 should be 2 ether");
        assertEq(payment2, 1 ether, "Payment for MODEL_NAME_2 should be 1 ether");
    }

    function testInvalidJobStatusTransitions() public {
        // 1. Submit job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();
        
        // 2. Try to confirm job before assignment
        vm.startPrank(cp1);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION);
        
        vm.expectRevert(); // Will revert due to invalid state transition or validation
        jobManager.confirmJob(jobId);
        vm.stopPrank();
        
        // 3. Try to complete job before confirmation
        vm.startPrank(cp1);
        vm.expectRevert(); // Will revert due to invalid state transition or validation
        jobManager.completeJob(jobId);
        vm.stopPrank();
        
        // 4. Assign job properly
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp - LShared.CONFIRM_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 5. Try to complete job before confirmation
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        vm.startPrank(assignedNodeOwner);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        
        // Trying to complete without confirming first should fail
        vm.expectRevert(abi.encodeWithSignature(
            "InvalidJobStatus(uint256,uint8,uint8)",
            jobId,
            uint8(IJobManager.JobStatus.ASSIGNED),
            uint8(IJobManager.JobStatus.CONFIRMED)
        ));
        jobManager.completeJob(jobId);
        vm.stopPrank();
    }

    function testNodeInactivity() public {
        // 1. Submit job and complete the process
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();
        
        // 2. Assign job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Complete the job process
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        vm.startPrank(assignedNodeOwner);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        jobManager.confirmJob(jobId);
        jobManager.completeJob(jobId);
        vm.stopPrank();
        
        // 4. Move to next epoch and check activity
        vm.warp(block.timestamp + LShared.CONFIRM_DURATION + LShared.DISPUTE_DURATION);
        
        // Active node should have 0 inactivity epochs
        uint256 inactivityEpochs = jobManager.getNodeInactivityEpochs(assignedNodeId);
        assertEq(inactivityEpochs, 0, "Active node should have 0 inactivity epochs");
    }

    function testUnconfirmedJobs() public {
        // 1. Submit multiple jobs
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 3);
        jobEscrow.deposit(JOB_DEPOSIT * 3);
        
        uint256 jobId1 = jobManager.submitJob("job 1", MODEL_NAME_1, COMPUTE_RATING);
        uint256 jobId2 = jobManager.submitJob("job 2", MODEL_NAME_1, COMPUTE_RATING);
        uint256 jobId3 = jobManager.submitJob("job 3", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();
        
        // 2. Assign jobs
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Confirm one job, complete another, leave the third unconfirmed
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        
        uint256 nodeId1 = jobManager.getAssignedNode(jobId1);
        address nodeOwner1 = nodeManager.getNodeOwner(nodeId1);
        
        vm.startPrank(nodeOwner1);
        jobManager.confirmJob(jobId1);
        vm.stopPrank();
        
        uint256 nodeId2 = jobManager.getAssignedNode(jobId2);
        address nodeOwner2 = nodeManager.getNodeOwner(nodeId2);
        
        vm.startPrank(nodeOwner2);
        jobManager.confirmJob(jobId2);
        jobManager.completeJob(jobId2);
        vm.stopPrank();
        
        // 4. Get unconfirmed jobs
        uint256[] memory unconfirmedJobs = jobManager.getUnconfirmedJobs(epochManager.getCurrentEpoch());
        
        // Job3 should be the only unconfirmed job
        assertEq(unconfirmedJobs.length, 1, "Should be one unconfirmed job");
        assertEq(unconfirmedJobs[0], jobId3, "Unconfirmed job should be job 3");
    }

    function testInvalidModelName() public {
        // 1. Submit job with invalid model name
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        
        uint256 jobId = jobManager.submitJob("test job", "invalid_model", COMPUTE_RATING);
        vm.stopPrank();
        
        // 2. Assign job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        vm.startPrank(leader);
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Complete job
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(assignedNodeOwner);
        jobManager.confirmJob(jobId);
        jobManager.completeJob(jobId);
        jobManager.setTokenCountForJob(jobId, 1000000); // 1M tokens
        vm.stopPrank();
        
        // 4. Process payment - should revert due to invalid model name
        vm.expectRevert(abi.encodeWithSignature("InvalidModelName(string)", "invalid_model"));
        jobManager.processPayment(jobId);
    }

    // Helper Functions

    function _setupNodesAndLeader() internal {
        // 1. Whitelist CPs
        vm.startPrank(operator);
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);
        vm.stopPrank();

        // 2. Register nodes
        address[2] memory cps = [cp1, cp2];
        for (uint256 i = 0; i < cps.length; i++) {
            vm.startPrank(cps[i]);
            
            // Generate unique secret and commitment
            bytes memory secret = bytes(string(abi.encodePacked("secret", vm.toString(i + 1))));
            bytes32 commitment = keccak256(secret);
            secrets[cps[i]] = secret;
            commitments[cps[i]] = commitment;

            // Stake and register node
            token.approve(address(nodeEscrow), STAKE_AMOUNT);
            nodeEscrow.deposit(STAKE_AMOUNT);
            uint256 nodeId = nodeManager.registerNode(COMPUTE_RATING);
            nodeIds.push(nodeId);

            vm.stopPrank();
        }

        // 3. Set up job submitter funds
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 10);
        jobEscrow.deposit(JOB_DEPOSIT * 5);
        vm.stopPrank();

        // 4. Complete leader election
        for (uint256 i = 0; i < cps.length; i++) {
            vm.startPrank(cps[i]);
            leaderManager.submitCommitment(nodeIds[i], commitments[cps[i]]);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + LShared.COMMIT_DURATION);

        for (uint256 i = 0; i < cps.length; i++) {
            vm.startPrank(cps[i]);
            leaderManager.revealSecret(nodeIds[i], secrets[cps[i]]);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        leaderManager.electLeader();
    }
}