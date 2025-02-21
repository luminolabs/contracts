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
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant COMPUTE_RATING = 10;
    uint256 public constant STAKE_AMOUNT = 100 ether;
    uint256 public constant JOB_DEPOSIT = 10 ether;
    string public constant MODEL_NAME = "llm_llama3_1_8b";

    // Events to test
    event LeaderRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event NodeRewardApplied(uint256 indexed epoch, uint256[] indexed nodeIds, uint256 amount);
    event DisputerRewardApplied(uint256 indexed epoch, address cp, uint256 amount);
    event LeaderPenaltyApplied(uint256 indexed epoch, address cp, uint256 amount);
    event NodePenaltyApplied(uint256 indexed epoch, uint256[] indexed jobs, uint256 amount);

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
        
        // Whitelist CPs
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);

        // Fund accounts
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(jobSubmitter, INITIAL_BALANCE);

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

    function testSecretRevealReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        
        // Setup epoch and reveal secret
        _setupEpochAndLeader();
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        
        // Get initial balance
        uint256 cp1BalanceBefore = nodeEscrow.getBalance(cp1);
        
        // Process rewards
        incentiveManager.processAll(currentEpoch);
        
        // Verify reward was distributed
        assertEq(
            token.balanceOf(cp1) - cp1BalanceBefore,
            LShared.JOB_AVAILABILITY_REWARD,
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
        
        // Get initial balance
        uint256 leaderBalanceBefore = nodeEscrow.getBalance(leader);
        
        // Process rewards for current epoch
        incentiveManager.processAll(epochManager.getCurrentEpoch());
        
        // Verify leader reward
        assertEq(
            token.balanceOf(leader) - leaderBalanceBefore,
            LShared.LEADER_REWARD,
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
        
        // Get initial balance
        uint256 leaderBalanceBefore = nodeEscrow.getBalance(leader);
        
        // Process penalties for current epoch
        incentiveManager.processAll(epochManager.getCurrentEpoch());
        
        // Verify penalty was applied
        assertEq(
            leaderBalanceBefore - token.balanceOf(leader),
            LShared.LEADER_NOT_EXECUTED_PENALTY,
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
        
        // Get assigned node's balance
        uint256 assignedNodeId = jobManager.getAssignedNode(1);
        address assignedNode = nodeManager.getNodeOwner(assignedNodeId);
        uint256 nodeBalanceBefore = nodeEscrow.getBalance(assignedNode);
        
        // Process penalties for current epoch
        incentiveManager.processAll(epochManager.getCurrentEpoch());
        
        // Verify penalty was applied
        assertEq(
            nodeBalanceBefore - token.balanceOf(assignedNode),
            LShared.JOB_NOT_CONFIRMED_PENALTY,
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
        
        // Process penalties for multiple epochs until slash
        for (uint256 i = 0; i < LShared.MAX_PENALTIES_BEFORE_SLASH; i++) {
            incentiveManager.processAll(epochManager.getCurrentEpoch());
            // Move to next epoch
            vm.warp(block.timestamp + LShared.EPOCH_DURATION);
        }
        
        // Verify complete stake slashing
        assertEq(
            nodeEscrow.getBalance(leader),
            0,
            "Stake not completely slashed after max penalties"
        );
    }

    function testCannotProcessPastEpoch() public {
        vm.warp(LShared.EPOCH_DURATION * 2); // Move to epoch 3
        vm.expectRevert(abi.encodeWithSignature(
            "CanOnlyProcessCurrentEpoch(uint256,uint256)",
            1,
            3
        ));
        incentiveManager.processAll(1);
    }

    function testCannotProcessFutureEpoch() public {
        vm.warp(LShared.EPOCH_DURATION); // At epoch 2
        vm.expectRevert(abi.encodeWithSignature(
            "CanOnlyProcessCurrentEpoch(uint256,uint256)",
            3,
            2
        ));
        incentiveManager.processAll(3);
    }

    function testCannotProcessEpochTwice() public {
        // Start at epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        
        // Process first time
        incentiveManager.processAll(currentEpoch);
        
        // Try to process same epoch again
        vm.expectRevert(abi.encodeWithSignature(
            "EpochAlreadyProcessed(uint256)",
            currentEpoch
        ));
        incentiveManager.processAll(currentEpoch);
    }

    function testMultipleNodesRevealReward() public {
        // Start at a clean epoch boundary
        vm.warp(LShared.EPOCH_DURATION);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        
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
        
        // Record initial balances
        uint256 cp1BalanceBefore = nodeEscrow.getBalance(cp1);
        uint256 cp2BalanceBefore = nodeEscrow.getBalance(cp2);
        
        // Process rewards
        incentiveManager.processAll(currentEpoch);
        
        // Verify both nodes received reveal reward
        assertEq(
            token.balanceOf(cp1) - cp1BalanceBefore,
            LShared.JOB_AVAILABILITY_REWARD,
            "First node did not receive reveal reward"
        );
        assertEq(
            token.balanceOf(cp2) - cp2BalanceBefore,
            LShared.JOB_AVAILABILITY_REWARD,
            "Second node did not receive reveal reward"
        );
    }
}