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
    uint256 public constant COMPUTE_RATING = 10;
    uint256 public constant STAKE_AMOUNT = 1000 ether; // Increased stake amount
    uint256 public constant JOB_DEPOSIT = 10 ether;
    string public constant MODEL_NAME = "llm_llama3_1_8b";

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
        
        incentiveManager = new IncentiveManager(
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
        
        // Move to execute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        
        // Setup and assign job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();
        
        vm.prank(leader);
        jobManager.startAssignmentRound();
        
        // Get initial balance
        uint256 leaderBalanceBefore = nodeEscrow.getBalance(leader);
        
        // Move to dispute phase for processing
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        
        // Process rewards
        incentiveManager.processAll();
        
        // Verify leader reward
        assertEq(
            nodeEscrow.getBalance(leader) - leaderBalanceBefore,
            LShared.LEADER_REWARD,
            "Leader reward not applied correctly"
        );
    }

    function testJobAvailabilityReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup epoch and reveal secret
        _setupEpochAndLeader();
        
        // Get initial balance
        uint256 cp1BalanceBefore = nodeEscrow.getBalance(cp1);
        
        // Move to dispute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        
        // Process rewards
        incentiveManager.processAll();
        
        // Verify job availability reward
        assertEq(
            nodeEscrow.getBalance(cp1) - cp1BalanceBefore,
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
        jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();
        
        // Get initial balance
        uint256 leaderBalanceBefore = nodeEscrow.getBalance(leader);
        
        // Move to dispute phase
        vm.warp(block.timestamp + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        
        // Process penalties
        incentiveManager.processAll();
        
        // Verify leader penalty
        assertEq(
            leaderBalanceBefore - nodeEscrow.getBalance(leader),
            LShared.LEADER_NOT_EXECUTED_PENALTY,
            "Leader penalty not applied correctly"
        );
    }

    function testJobConfirmationPenalty() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup leader and assign job
        uint256 leaderId = _setupEpochAndLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();
        
        // Move to execute phase and assign job
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        vm.prank(leader);
        jobManager.startAssignmentRound();
        
        // Get assigned node's balance
        uint256 assignedNodeId = jobManager.getAssignedNode(1);
        address assignedNode = nodeManager.getNodeOwner(assignedNodeId);
        uint256 nodeBalanceBefore = nodeEscrow.getBalance(assignedNode);
        
        // Move to dispute phase
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
        
        // Process penalties
        incentiveManager.processAll();
        
        // Verify job confirmation penalty
        assertEq(
            nodeBalanceBefore - nodeEscrow.getBalance(assignedNode),
            LShared.JOB_NOT_CONFIRMED_PENALTY,
            "Job confirmation penalty not applied correctly"
        );
    }

    function testSlashingAfterMaxPenalties() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup leader but don't execute assignments
        uint256 leaderId = _setupEpochAndLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // Submit job to create assignment opportunities
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();
        
        // Process penalties for multiple epochs until slashing
        for (uint256 i = 0; i < LShared.MAX_PENALTIES_BEFORE_SLASH; i++) {
            // Move to dispute phase for current epoch
            vm.warp(block.timestamp + LShared.ELECT_DURATION + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION);
            incentiveManager.processAll();
            
            // Move to next epoch's commit phase
            vm.warp(block.timestamp + LShared.DISPUTE_DURATION + 1);
            
            if (i < LShared.MAX_PENALTIES_BEFORE_SLASH - 1) {
                // Setup next epoch's leader (except for last iteration)
                leaderId = _setupEpochAndLeader();
            }
        }
        
        // Verify slashing occurred
        assertEq(
            nodeEscrow.getBalance(leader),
            0,
            "Account not slashed after max penalties"
        );
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