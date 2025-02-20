// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/JobManager.sol";
import "../src/NodeManager.sol";
import "../src/LeaderManager.sol";
import "../src/EpochManager.sol";
import "../src/JobEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract JobManagerTest is Test {
    JobManager public jobManager;
    NodeManager public nodeManager;
    LeaderManager public leaderManager;
    EpochManager public epochManager;
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
        jobEscrow = new JobEscrow(address(accessManager), address(token));
        whitelistManager = new WhitelistManager(address(accessManager));
        
        nodeManager = new NodeManager(
            address(jobEscrow),
            address(whitelistManager),
            address(accessManager)
        );
        
        leaderManager = new LeaderManager(
            address(epochManager),
            address(nodeManager),
            address(jobEscrow),
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