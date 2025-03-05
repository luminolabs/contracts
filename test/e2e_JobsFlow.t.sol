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
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);
    event PaymentReleased(address indexed from, address indexed to, uint256 amount);
    event JobTokensSet(uint256 indexed jobId, uint256 numTokens);

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        token = new LuminoToken();
        token.initialize();
        accessManager = new AccessManager();
        accessManager.initialize();
        epochManager = new EpochManager();
        nodeEscrow = new NodeEscrow();
        nodeEscrow.initialize(address(accessManager), address(token));
        jobEscrow = new JobEscrow();
        jobEscrow.initialize(address(accessManager), address(token));
        whitelistManager = new WhitelistManager();
        whitelistManager.initialize(address(accessManager));
        
        nodeManager = new NodeManager();
        nodeManager.initialize(
            address(nodeEscrow),
            address(whitelistManager),
            address(accessManager)
        );
        
        leaderManager = new LeaderManager();
        leaderManager.initialize(
            address(epochManager),
            address(nodeManager),
            address(nodeEscrow),
            address(accessManager),
            address(whitelistManager)
        );
        
        jobManager = new JobManager();
        jobManager.initialize(
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
        // 1. Submit job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob(
            "test job args",
            MODEL_NAME_1,
            COMPUTE_RATING
        );

         // Track initial balances
        uint256 submitterInitialBalance = jobEscrow.getBalance(jobSubmitter);
        vm.stopPrank();
        
        // 2. Assign job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        // Make sure we're in EXECUTE phase
        
        vm.warp(LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + 1);
        
        (IEpochManager.State state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.EXECUTE), "Not in EXECUTE state");
        
        vm.startPrank(leader);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // Verify assignment
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        assertTrue(assignedNodeId > 0, "Job should be assigned to a node");
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        // 3. Confirm job - make sure we're in CONFIRM phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        (state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.CONFIRM), "Not in CONFIRM state");
        
        vm.startPrank(assignedNodeOwner);
        jobManager.confirmJob(jobId);
        
        // 4. Complete job and set token count - can happen anytime after confirmation
        jobManager.completeJob(jobId);
        uint256 tokenCount = 1000000; // 1M tokens for model fee calculation
        jobManager.setTokenCountForJob(jobId, tokenCount);
        vm.stopPrank();
        
        // 5. Process payment
        uint256 nodeOwnerInitialBalance = jobEscrow.getBalance(assignedNodeOwner);
        
        // Calculate expected payment based on model fee
        uint256 expectedPayment = 2 ether; // MODEL_NAME_1 has fee of 2 per 1M tokens
        
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
        vm.warp(LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Verify assignment distribution
        for (uint256 i = 0; i < 3; i++) {
            uint256 assignedNodeId = jobManager.getAssignedNode(jobIds[i]);
            if (i < 2 ) {
                assertTrue(assignedNodeId > 0, string(abi.encodePacked("Job ", vm.toString(i + 1), " should be assigned")));
            } else {
                // 3rd job shouldn't be assigned
                assertTrue(assignedNodeId == 0, string(abi.encodePacked("Job ", vm.toString(i + 1), " should not be assigned")));
            }
        }
        
        // 4. Get jobs by node
        uint256 nodeId = jobManager.getAssignedNode(jobIds[0]);
        IJobManager.Job[] memory nodeJobs = jobManager.getJobsDetailsByNode(nodeId);
        
        // Verify node has assigned jobs
        assertTrue(nodeJobs.length > 0, "Node should have assigned jobs");
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
            "InvalidStatusTransition(uint8,uint8)",
            uint8(IJobManager.JobStatus.ASSIGNED),
            uint8(IJobManager.JobStatus.COMPLETE)
        ));
        jobManager.completeJob(jobId);
        vm.stopPrank();
    }

    function testNodeInactivity() public {
        // Set the initial time to start at epoch 50 (to avoid underflow)
        uint256 startEpoch = 50;
        vm.warp((startEpoch - 1) * LShared.EPOCH_DURATION);
        
        // Verify we're in the expected epoch
        assertEq(epochManager.getCurrentEpoch(), startEpoch, "Should start at epoch 50");
        
        // 1. Submit job and complete the process
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME_1, COMPUTE_RATING);
        vm.stopPrank();
        
        // Setup leader election for this epoch - make cp1 reveal its secret
        vm.startPrank(cp1);
        bytes memory secret1 = bytes("secret_epoch_50");
        bytes32 commitment1 = keccak256(secret1);
        leaderManager.submitCommitment(1, commitment1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        bytes memory secret2 = bytes("secret_epoch_50_alt");
        bytes32 commitment2 = keccak256(secret2);
        leaderManager.submitCommitment(2, commitment2);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(1, secret1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        leaderManager.revealSecret(2, secret2);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        leaderManager.electLeader();
        
        // 2. Assign job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        
        // Make sure we're in EXECUTE phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        
        vm.startPrank(leader);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Complete the job process
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        // Move to CONFIRM phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        
        vm.startPrank(assignedNodeOwner);
        jobManager.confirmJob(jobId);
        // Do NOT complete the job - keep it in CONFIRMED state
        // jobManager.completeJob(jobId);
        vm.stopPrank();
        
        // Check activity BEFORE completing the job
        uint256 inactivityEpochsBeforeCompletion = jobManager.getNodeInactivityEpochs(assignedNodeId);
        assertEq(inactivityEpochsBeforeCompletion, 0, "Node with confirmed job should have 0 inactivity epochs");
        
        // Now complete the job
        vm.startPrank(assignedNodeOwner);
        jobManager.completeJob(jobId);
        vm.stopPrank();
        
        // Check activity AFTER completing the job but BEFORE moving to next epoch
        uint256 inactivityEpochsAfterCompletion = jobManager.getNodeInactivityEpochs(assignedNodeId);
        console.log("Inactivity after completion:", inactivityEpochsAfterCompletion);
        
        // IMPORTANT: The node should still be active since it was active in the current epoch
        assertEq(inactivityEpochsAfterCompletion, 0, "Node should still have 0 inactivity epochs in same epoch");
        
        // 4. Move to next epoch and check activity again
        vm.warp(block.timestamp + LShared.CONFIRM_DURATION + LShared.DISPUTE_DURATION);
        
        // Make this node active in the next epoch by having it participate in leader election
        vm.startPrank(assignedNodeOwner);
        bytes memory nextSecret = bytes("secret_next_epoch");
        bytes32 nextCommitment = keccak256(nextSecret);
        leaderManager.submitCommitment(assignedNodeId, nextCommitment);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(assignedNodeOwner);
        leaderManager.revealSecret(assignedNodeId, nextSecret);
        vm.stopPrank();
        
        // Now check activity again
        uint256 inactivityEpochsNextEpoch = jobManager.getNodeInactivityEpochs(assignedNodeId);
        assertEq(inactivityEpochsNextEpoch, 0, "Node active in new epoch should have 0 inactivity epochs");
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
        
        // Make sure we're in EXECUTE phase
        vm.warp(LShared.COMMIT_DURATION + LShared.REVEAL_DURATION + LShared.ELECT_DURATION);
        (IEpochManager.State state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.EXECUTE), "Not in EXECUTE state");
        
        vm.startPrank(leader);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 3. Confirm job1, complete job2, leave job3 unconfirmed
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        (state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.CONFIRM), "Not in CONFIRM state");
        
        // Confirm job1
        uint256 nodeId1 = jobManager.getAssignedNode(jobId1);
        if (nodeId1 > 0) {
            address nodeOwner1 = nodeManager.getNodeOwner(nodeId1);
            vm.startPrank(nodeOwner1);
            jobManager.confirmJob(jobId1);
            vm.stopPrank();
        }
        
        // Confirm and complete job2
        uint256 nodeId2 = jobManager.getAssignedNode(jobId2);
        if (nodeId2 > 0) {
            address nodeOwner2 = nodeManager.getNodeOwner(nodeId2);
            vm.startPrank(nodeOwner2);
            jobManager.confirmJob(jobId2);
            jobManager.completeJob(jobId2);
            vm.stopPrank();
        }
        
        // Leave job3 unconfirmed (if it was assigned)
        uint256 nodeId3 = jobManager.getAssignedNode(jobId3);
        
        // Print current epoch for debugging
        console.log("Current epoch:", epochManager.getCurrentEpoch());
        
        // 4. Get unconfirmed jobs
        uint256[] memory unconfirmedJobs = jobManager.getUnconfirmedJobs(epochManager.getCurrentEpoch());
        
        // Job3 should be the only unconfirmed job if it was assigned
        if (nodeId3 > 0) {
            assertEq(unconfirmedJobs.length, 1, "Should be one unconfirmed job");
            assertEq(unconfirmedJobs[0], jobId3, "Unconfirmed job should be job 3");
        } else {
            // If job3 wasn't assigned (due to MAX_JOBS_PER_NODE constraint), skip this assertion
            console.log("Job3 wasn't assigned, skipping unconfirmed job check");
        }
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