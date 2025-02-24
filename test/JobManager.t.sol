// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "../lib/forge-std/src/Base.sol";
import {StdAssertions} from "../lib/forge-std/src/StdAssertions.sol";
import {StdChains} from "../lib/forge-std/src/StdChains.sol";
import {StdCheats, StdCheatsSafe} from "../lib/forge-std/src/StdCheats.sol";
import {StdUtils} from "../lib/forge-std/src/StdUtils.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
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
    string public constant MODEL_NAME = "llm_llama3_1_8b";

    // Events to test
    event JobSubmitted(uint256 indexed jobId, address indexed submitter, uint256 requiredPool);
    event JobStatusUpdated(uint256 indexed jobId, IJobManager.JobStatus status);
    event JobAssigned(uint256 indexed jobId, uint256 indexed nodeId);
    event AssignmentRoundStarted(uint256 indexed epoch);
    event JobConfirmed(uint256 indexed jobId, uint256 indexed nodeId);
    event JobCompleted(uint256 indexed jobId, uint256 indexed nodeId);
    event JobRejected(uint256 indexed jobId, uint256 indexed nodeId, string reason);
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);

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
        token.approve(address(jobEscrow), STAKE_AMOUNT);
        jobEscrow.deposit(STAKE_AMOUNT);

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
            MODEL_NAME,
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
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();

        IJobManager.JobStatus status = jobManager.getJobStatus(jobId);
        assertEq(uint256(status), uint256(IJobManager.JobStatus.NEW), "Initial job status should be NEW");
    }

    function testGetJobDetails() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job args", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();

        IJobManager.Job memory job = jobManager.getJobDetails(jobId);
        assertEq(job.id, jobId);
        assertEq(job.submitter, jobSubmitter);
        assertEq(job.assignedNode, 0);
        assertEq(uint256(job.status), uint256(IJobManager.JobStatus.NEW));
        assertEq(job.requiredPool, COMPUTE_RATING);
        assertEq(job.args, "test job args");
        assertEq(job.base_model_name, MODEL_NAME);
        assertEq(job.tokenCount, 0);
        assertEq(job.createdAt, block.timestamp);
    }

    function testGetJobsDetailsByNode() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job args", MODEL_NAME, COMPUTE_RATING);
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
        assertEq(jobs[0].base_model_name, MODEL_NAME, "Model name should match");
        assertEq(jobs[0].tokenCount, 0, "Token count should be 0");
        assertGt(jobs[0].createdAt, 0, "Created at should be set");
    }

    function testGetJobsBySubmitter() public {
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 2);
        jobEscrow.deposit(JOB_DEPOSIT * 2);

        uint256 jobId1 = jobManager.submitJob("job 1", MODEL_NAME, COMPUTE_RATING);
        uint256 jobId2 = jobManager.submitJob("job 2", MODEL_NAME, COMPUTE_RATING);
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
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
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
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
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

        vm.stopPrank();
    }

    function testInvalidConfirmation() public {
        // Setup: submit and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Try to confirm from wrong address
        vm.startPrank(jobSubmitter);
        vm.expectRevert(); // Should revert as jobSubmitter is not the assigned node owner
        jobManager.confirmJob(jobId);
        vm.stopPrank();
    }

    function testCompleteJob() public {
        // Setup: submit, assign and confirm job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
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

        vm.stopPrank();
    }

    function testRejectJob() public {
        // Setup: submit and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
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
        emit JobRejected(jobId, assignedNode, "Test rejection");

        // Reject job
        jobManager.rejectJob(jobId, "Test rejection");

        // Verify assignment was reset
        assertEq(jobManager.getAssignedNode(jobId), 0, "Job should no longer be assigned");

        vm.stopPrank();
    }

    function testProcessPayment() public {
        // Setup: submit, assign, confirm and complete job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
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
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
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

    function testGetUnconfirmedJobs() public {
        // Setup: submit multiple jobs and progress them to different states
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 3);
        jobEscrow.deposit(JOB_DEPOSIT * 3);
        uint256 jobId1 = jobManager.submitJob("job1", MODEL_NAME, COMPUTE_RATING);
        uint256 jobId2 = jobManager.submitJob("job2", MODEL_NAME, COMPUTE_RATING);
        uint256 jobId3 = jobManager.submitJob("job3", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();

        _setupAssignment();

        // Progress jobs to different states
        uint256 assignedNode = jobManager.getAssignedNode(jobId1);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId1); // CONFIRMED
        jobManager.confirmJob(jobId2);
        jobManager.completeJob(jobId2); // COMPLETE
        // jobId3 remains ASSIGNED
        vm.stopPrank();

        // Test
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        uint256[] memory unconfirmedJobs = jobManager.getUnconfirmedJobs(currentEpoch);

        assertEq(unconfirmedJobs.length, 1, "Should return only one unconfirmed job");
        assertEq(unconfirmedJobs[0], jobId3, "Should return only the ASSIGNED job");
    }

    function testNodeCanPickUpNewJobAfterCompletion() public {
        // Setup: submit two jobs
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT * 2);
        jobEscrow.deposit(JOB_DEPOSIT * 2);
        uint256 jobId1 = jobManager.submitJob("job 1", MODEL_NAME, COMPUTE_RATING);
        uint256 jobId2 = jobManager.submitJob("job 2", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();

        // Assign first job
        _setupAssignment();

        // Get assigned node for job 1
        uint256 assignedNode1 = jobManager.getAssignedNode(jobId1);
        assertGt(assignedNode1, 0, "Job 1 should be assigned");
        assertEq(jobManager.getAssignedNode(jobId2), 0, "Job 2 should not be assigned yet");

        // Complete job 1
        address nodeOwner = nodeManager.getNodeOwner(assignedNode1);
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId1);
        jobManager.completeJob(jobId1);
        vm.stopPrank();

        // Move to next epoch and assign job 2
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        _setupAssignment();

        // Verify job 2 is now assigned to the same node
        uint256 assignedNode2 = jobManager.getAssignedNode(jobId2);
        assertGt(assignedNode2, 0, "Job 2 should be assigned after job 1 is completed");
        assertEq(assignedNode2, assignedNode1, "Job 2 should be assigned to the same node");

        // Verify nodeAssignments
        IJobManager.Job[] memory nodeJobs = jobManager.getJobsDetailsByNode(assignedNode1);
        assertEq(nodeJobs.length, 1, "Node should have only one active assignment");
        assertEq(nodeJobs[0].id, jobId2, "Node should be assigned job 2");
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