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
import "../src/IncentiveTreasury.sol";
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
    IncentiveTreasury public treasury;
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

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        token = new LuminoToken();
        accessManager = new AccessManager();
        epochManager = new EpochManager();
        nodeEscrow = new NodeEscrow(address(accessManager), address(token));
        jobEscrow = new JobEscrow(address(accessManager), address(token));
        whitelistManager = new WhitelistManager(address(accessManager));
        treasury = new IncentiveTreasury(address(token), address(accessManager));
        
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
            address(nodeEscrow),
            address(treasury)
        );

        // Setup roles
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(incentiveManager));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(treasury));
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        
        // Whitelist CPs
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);

        // Fund accounts and treasury
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(jobSubmitter, INITIAL_BALANCE);
        token.transfer(address(treasury), INITIAL_BALANCE * 10);

        vm.stopPrank();

        // Setup nodes and approvals
        _setupNode(cp1);
        _setupNode(cp2);
    }

    function _setupNode(address cp) internal {
        vm.startPrank(cp);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        token.approve(address(treasury), INITIAL_BALANCE); // For penalties
        nodeEscrow.deposit(STAKE_AMOUNT);
        nodeManager.registerNode(COMPUTE_RATING);
        vm.stopPrank();
    }

    function _setupEpochAndLeader() internal returns (uint256 leaderId) {
        // Make sure we're at the start of an epoch
        uint256 currentEpochStart = (block.timestamp / LShared.EPOCH_DURATION) * LShared.EPOCH_DURATION;
        vm.warp(currentEpochStart);
        
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(1, commitment);
        
        vm.warp(currentEpochStart + LShared.COMMIT_DURATION);
        leaderManager.revealSecret(1, secret);
        
        vm.warp(currentEpochStart + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION);
        leaderId = leaderManager.electLeader();
        
        vm.stopPrank();
        return leaderId;
    }

    function testSecretRevealReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup epoch and reveal secret
        _setupEpochAndLeader();
        
        // Move to next epoch
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        uint256 previousEpoch = epochManager.getCurrentEpoch() - 1;
        
        // Get initial balances
        uint256 cp1BalanceBefore = token.balanceOf(cp1);
        
        // Process rewards
        incentiveManager.processAll(previousEpoch);
        
        // Verify reward was distributed
        assertEq(
            token.balanceOf(cp1) - cp1BalanceBefore,
            LShared.SECRET_REVEAL_REWARD,
            "Secret reveal reward not distributed correctly"
        );
    }

    function testLeaderAssignmentReward() public {
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
        
        // Move to next epoch
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        uint256 previousEpoch = epochManager.getCurrentEpoch() - 1;
        
        // Get initial balance
        uint256 leaderBalanceBefore = token.balanceOf(leader);
        
        // Process rewards
        incentiveManager.processAll(previousEpoch);
        
        // Verify leader reward
        assertEq(
            token.balanceOf(leader) - leaderBalanceBefore,
            LShared.LEADER_ASSIGNMENT_REWARD,
            "Leader assignment reward not distributed correctly"
        );
    }

    function testMissedAssignmentPenalty() public {
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
        
        // Move to next epoch without starting assignment round
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        uint256 previousEpoch = epochManager.getCurrentEpoch() - 1;
        
        // Get initial balance
        uint256 leaderBalanceBefore = token.balanceOf(leader);
        
        // Process penalties
        incentiveManager.processAll(previousEpoch);
        
        // Verify penalty was applied
        assertEq(
            leaderBalanceBefore - token.balanceOf(leader),
            LShared.MISSED_ASSIGNMENT_PENALTY,
            "Missed assignment penalty not applied correctly"
        );
    }

    function testMissedConfirmationPenalty() public {
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
        
        // Move to next epoch without confirming job
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        uint256 previousEpoch = epochManager.getCurrentEpoch() - 1;
        
        // Get assigned node's balance
        uint256 assignedNodeId = jobManager.getAssignedNode(1);
        address assignedNode = nodeManager.getNodeOwner(assignedNodeId);
        uint256 nodeBalanceBefore = token.balanceOf(assignedNode);
        
        // Process penalties
        incentiveManager.processAll(previousEpoch);
        
        // Verify penalty was applied
        assertEq(
            nodeBalanceBefore - token.balanceOf(assignedNode),
            LShared.MISSED_CONFIRMATION_PENALTY,
            "Missed confirmation penalty not applied correctly"
        );
    }

    function testMaxPenaltiesSlashing() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup leader
        uint256 leaderId = _setupEpochAndLeader();
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // Submit job to create assignment opportunities
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();
        
        // Accumulate max penalties
        for (uint256 i = 0; i < LShared.MAX_PENALTIES_BEFORE_SLASH; i++) {
            vm.warp(block.timestamp + LShared.EPOCH_DURATION);
            incentiveManager.processAll(epochManager.getCurrentEpoch() - 1);
        }
        
        // Verify complete stake slashing
        assertEq(
            nodeEscrow.getBalance(leader), 
            0,
            "Stake not completely slashed after max penalties"
        );
    }

    function testCannotProcessCurrentEpoch() public {
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        vm.expectRevert("Cannot process current epoch");
        incentiveManager.processAll(currentEpoch);
    }

    function testCannotProcessEpochTwice() public {
        // Setup and complete an epoch
        _setupEpochAndLeader();
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        uint256 previousEpoch = epochManager.getCurrentEpoch() - 1;
        
        // Process first time
        incentiveManager.processAll(previousEpoch);
        
        // Try to process same epoch again
        vm.expectRevert("Epoch already processed");
        incentiveManager.processAll(previousEpoch);
    }

    function testMultipleNodesRevealReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup first node
        vm.startPrank(cp1);
        bytes memory secret1 = bytes("secret1");
        bytes32 commitment1 = keccak256(secret1);
        leaderManager.submitCommitment(1, commitment1);
        vm.stopPrank();
        
        // Setup second node
        vm.startPrank(cp2);
        bytes memory secret2 = bytes("secret2");
        bytes32 commitment2 = keccak256(secret2);
        leaderManager.submitCommitment(2, commitment2);
        vm.stopPrank();
        
        // Move to reveal phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        // Both nodes reveal
        vm.prank(cp1);
        leaderManager.revealSecret(1, secret1);
        vm.prank(cp2);
        leaderManager.revealSecret(2, secret2);
        
        // Complete epoch
        vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        uint256 previousEpoch = epochManager.getCurrentEpoch() - 1;
        
        // Record initial balances
        uint256 cp1BalanceBefore = token.balanceOf(cp1);
        uint256 cp2BalanceBefore = token.balanceOf(cp2);
        
        // Process rewards
        incentiveManager.processAll(previousEpoch);
        
        // Verify both nodes received reveal reward
        assertEq(
            token.balanceOf(cp1) - cp1BalanceBefore,
            LShared.SECRET_REVEAL_REWARD,
            "First node did not receive reveal reward"
        );
        assertEq(
            token.balanceOf(cp2) - cp2BalanceBefore,
            LShared.SECRET_REVEAL_REWARD,
            "Second node did not receive reveal reward"
        );
    }
}