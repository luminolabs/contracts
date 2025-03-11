// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/IncentiveManager.sol";
import "../src/EpochManager.sol";
import "../src/LeaderManager.sol";
import "../src/JobManager.sol";
import "../src/JobEscrow.sol";
import "../src/NodeManager.sol";
import "../src/NodeEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract IncentiveManagerTest is Test {
    IncentiveManager public incentiveManager;
    EpochManager public epochManager;
    LeaderManager public leaderManager;
    JobManager public jobManager;
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

    // Constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant COMPUTE_RATING = 500;
    uint256 public constant STAKE_AMOUNT = 5000 ether; // Increased stake amount
    uint256 public constant JOB_DEPOSIT = 20 ether;
    string public constant MODEL_NAME = "llm_llama3_2_1b";

    // Events to test
    event LeaderRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event JobAvailabilityRewardApplied(uint256 indexed epoch, uint256 indexed nodeId, uint256 amount);
    event DisputerRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event LeaderNotExecutedPenaltyApplied(uint256 indexed epoch, address cp, uint256 amount);
    event JobNotConfirmedPenaltyApplied(uint256 indexed epoch, uint256 indexed job, uint256 amount);

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
        
        incentiveManager = new IncentiveManager();
        incentiveManager.initialize(
            address(epochManager),
            address(leaderManager),
            address(jobManager),
            address(nodeManager),
            address(nodeEscrow)
        );

        // Setup roles
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(incentiveManager));
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(jobManager));
        
        // Whitelist CPs
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);

        // Fund accounts and contracts
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(jobSubmitter, INITIAL_BALANCE);
        // Fund nodeEscrow for rewards
        token.transfer(address(nodeEscrow), INITIAL_BALANCE * 10); // Much larger balance for rewards

        vm.stopPrank();

        // Setup nodes and approvals
        _setupNode(cp1);
        _setupNode(cp2);
    }

    function _setupNode(address cp) internal {
        vm.startPrank(cp);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);
        nodeManager.registerNode(COMPUTE_RATING);
        vm.stopPrank();
    }

    function _setupEpochAndLeader() internal returns (uint256 leaderId) {
        // Setup leader
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(1, commitment);
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        leaderManager.revealSecret(1, secret);
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        leaderId = leaderManager.electLeader();
        
        vm.stopPrank();
        return leaderId;
    }

    function testLeaderReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup leader and job assignment
        uint256 leaderId = _setupEpochAndLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // Make sure the leader has enough stake
        vm.startPrank(leader);
        uint256 stakeAmount = 100 ether; // Plenty of stake
        token.approve(address(nodeEscrow), stakeAmount);
        nodeEscrow.deposit(stakeAmount);
        vm.stopPrank();
        
        // Move to execute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        (IEpochManager.State state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.EXECUTE), "Not in EXECUTE state");
        
        // Setup and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, "FULL");
        vm.stopPrank();
        
        vm.prank(leader);
        jobManager.startAssignmentRound();
        
        // Move to confirm phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        (state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.CONFIRM), "Not in CONFIRM state");
        
        // Confirm job to avoid penalty
        uint256 jobId = 1;
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        assertEq(assignedNodeId, leaderId, "Job should be assigned to leader's node");
        
        vm.prank(leader);
        jobManager.confirmJob(jobId);
        
        // Get balance before dispute phase
        uint256 leaderBalanceBefore = nodeEscrow.getBalance(leader);
        
        // Move to dispute phase for processing
        vm.warp(block.timestamp + LShared.CONFIRM_DURATION);
        (state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.DISPUTE), "Not in DISPUTE state");
        
        // Process rewards with a different address (not the leader)
        vm.prank(cp2);
        incentiveManager.processAll();
        
        // Check final balance and calculate expected increase
        uint256 leaderBalanceAfter = nodeEscrow.getBalance(leader);
        uint256 balanceChange = leaderBalanceAfter - leaderBalanceBefore;
        
        // Expected change: LEADER_REWARD + JOB_AVAILABILITY_REWARD (since leader revealed)
        // Leader doesn't get the DISPUTER_REWARD since cp2 called processAll
        uint256 expectedChange = LShared.LEADER_REWARD + LShared.JOB_AVAILABILITY_REWARD;
        
        // Verify the correct rewards were applied
        assertEq(balanceChange, expectedChange, "Leader should receive both leader and availability rewards");
    }

    function testJobAvailabilityReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Make sure cp1 has enough balance
        vm.startPrank(cp1);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);
        vm.stopPrank();

        // Set up a clean leader election scenario
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(1, commitment);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(1, secret);
        vm.stopPrank();
        
        // No need to elect leader for this test, just need cp1 to have revealed

        // Get initial balance after setup
        uint256 cp1BalanceBefore = nodeEscrow.getBalance(cp1);
        console.log("CP1 balance before:", cp1BalanceBefore);
        
        // Move to dispute phase
        vm.warp(block.timestamp + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + 
                LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        
        // Process rewards with different address to avoid disputer reward
        vm.prank(cp2);
        incentiveManager.processAll();
        
        // Verify job availability reward
        uint256 cp1BalanceAfter = nodeEscrow.getBalance(cp1);
        console.log("CP1 balance after:", cp1BalanceAfter);
        console.log("Expected balance:", cp1BalanceBefore + LShared.JOB_AVAILABILITY_REWARD);
        console.log("Difference:", cp1BalanceAfter - cp1BalanceBefore);
        
        // Assert the exact expected increase
        assertEq(
            cp1BalanceAfter - cp1BalanceBefore,
            LShared.JOB_AVAILABILITY_REWARD,
            "Job availability reward not applied correctly"
        );
    }
    function testLeaderPenalty() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup leader but don't start assignment round
        uint256 leaderId = _setupEpochAndLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // Submit job to create assignment opportunity
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, "FULL");
        vm.stopPrank();
        
        // Ensure leader has enough stake
        vm.startPrank(leader);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);
        vm.stopPrank();
        
        // Get initial balance
        uint256 leaderBalanceBefore = nodeEscrow.getBalance(leader);
        
        // Move to dispute phase without starting assignment round
        vm.warp(block.timestamp + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        (IEpochManager.State state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.DISPUTE), "Not in DISPUTE state");
        
        // Process penalties with a non-leader account
        vm.prank(cp2);
        incentiveManager.processAll();
        
        // Verify leader penalty
        uint256 leaderBalanceAfter = nodeEscrow.getBalance(leader) - LShared.JOB_AVAILABILITY_REWARD;
        assertEq(
            leaderBalanceBefore - leaderBalanceAfter,
            LShared.LEADER_NOT_EXECUTED_PENALTY,
            "Leader penalty not applied correctly"
        );
    }

    function testJobConfirmationPenalty() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup leader for assignment round
        uint256 leaderId = _setupEpochAndLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // Submit job to create assignment opportunity
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, "FULL");
        vm.stopPrank();
        
        // Move to execute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        (IEpochManager.State state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.EXECUTE), "Not in EXECUTE state");
        
        // Leader executes assignment round
        vm.prank(leader);
        jobManager.startAssignmentRound();
        
        // Get assigned node
        uint256 jobId = 1;
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address assignedNodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        // Make sure assigned node has tokens and stake
        vm.startPrank(admin);
        token.transfer(assignedNodeOwner, 1000 ether); // 1,000 tokens
        vm.stopPrank();
        
        vm.startPrank(assignedNodeOwner);
        uint256 stakeAmount = 100 ether; // 100 tokens
        token.approve(address(nodeEscrow), stakeAmount);
        nodeEscrow.deposit(stakeAmount);
        vm.stopPrank();
        
        // Track node's balance before penalty
        uint256 nodeBalanceBefore = nodeEscrow.getBalance(assignedNodeOwner);
        console.log("Node escrow balance before:", nodeBalanceBefore);
        
        // Move to dispute phase WITHOUT confirming the job
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        (state, ) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.DISPUTE), "Not in DISPUTE state");
        
        // Verify job is still unconfirmed
        assertEq(uint256(jobManager.getJobStatus(jobId)), uint256(IJobManager.JobStatus.ASSIGNED), 
                "Job should still be in ASSIGNED state");
        
        // Record pending logs to check events
        vm.recordLogs();
        
        // Process penalties
        vm.prank(jobSubmitter);
        incentiveManager.processAll();
        
        // Check the node's balance after penalty
        uint256 nodeBalanceAfter = nodeEscrow.getBalance(assignedNodeOwner);
        console.log("Node escrow balance after:", nodeBalanceAfter);
        console.log("Balance difference:", nodeBalanceBefore - nodeBalanceAfter);
        
        // Get logs to analyze what happened
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Look for JobNotConfirmedPenaltyApplied event
        bool foundPenaltyEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("JobNotConfirmedPenaltyApplied(uint256,uint256,uint256)")) {
                foundPenaltyEvent = true;
                console.log("Found JobNotConfirmedPenaltyApplied event");
                // Extract penalty amount from event
                uint256 penaltyAmount = abi.decode(logs[i].data, (uint256));
                console.log("Penalty amount from event:", penaltyAmount);
            }
        }
        
        // Look for availability reward if node revealed
        bool foundAvailabilityReward = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("JobAvailabilityRewardApplied(uint256,uint256,uint256)")) {
                uint256 rewardedNodeId = uint256(logs[i].topics[2]);
                if (rewardedNodeId == assignedNodeId) {
                    foundAvailabilityReward = true;
                    console.log("Found JobAvailabilityRewardApplied event for this node");
                    // Extract reward amount
                    uint256 rewardAmount = abi.decode(logs[i].data, (uint256));
                    console.log("Reward amount from event:", rewardAmount);
                }
            }
        }
        
        // Simply verify the overall balance decreased (penalty applied)
        assertTrue(nodeBalanceAfter < nodeBalanceBefore, "Node balance should decrease after penalty");
        
        // Check if the JobNotConfirmedPenaltyApplied event was emitted
        assertTrue(foundPenaltyEvent, "JobNotConfirmedPenaltyApplied event should be emitted");
    }

    function testCannotProcessTwice() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // First processing should succeed
        incentiveManager.processAll();
        
        // Second processing should fail
        vm.expectRevert(abi.encodeWithSignature(
            "EpochAlreadyProcessed(uint256)",
            epochManager.getCurrentEpoch()
        ));
        incentiveManager.processAll();
    }

    function testMultipleNodeRewards() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup nodes to reveal secrets
        vm.startPrank(cp1);
        bytes memory secret1 = bytes("secret1");
        bytes32 commitment1 = keccak256(secret1);
        leaderManager.submitCommitment(1, commitment1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        bytes memory secret2 = bytes("secret2");
        bytes32 commitment2 = keccak256(secret2);
        leaderManager.submitCommitment(2, commitment2);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.prank(cp1);
        leaderManager.revealSecret(1, secret1);
        vm.prank(cp2);
        leaderManager.revealSecret(2, secret2);
        
        // Record initial balances
        uint256 cp1BalanceBefore = nodeEscrow.getBalance(cp1);
        uint256 cp2BalanceBefore = nodeEscrow.getBalance(cp2);
        
        // Move to dispute phase
        vm.warp(block.timestamp + LShared.REVEAL_DURATION + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        
        // Process rewards
        incentiveManager.processAll();
        
        // Verify both nodes received rewards
        assertEq(
            nodeEscrow.getBalance(cp1) - cp1BalanceBefore,
            LShared.JOB_AVAILABILITY_REWARD,
            "First node reward not applied correctly"
        );
        assertEq(
            nodeEscrow.getBalance(cp2) - cp2BalanceBefore,
            LShared.JOB_AVAILABILITY_REWARD,
            "Second node reward not applied correctly"
        );
    }
}