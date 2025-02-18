// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AccessManager.sol";
import "../src/EpochManager.sol";
import "../src/IncentiveManager.sol";
import "../src/IncentiveTreasury.sol";
import "../src/JobEscrow.sol";
import "../src/JobManager.sol";
import "../src/LeaderManager.sol";
import "../src/LuminoToken.sol";
import "../src/NodeEscrow.sol";
import "../src/NodeManager.sol";
import "../src/WhitelistManager.sol";

contract LuminoE2ETest is Test {
    // Contract instances
    AccessManager public accessManager;
    EpochManager public epochManager;
    IncentiveManager public incentiveManager;
    IncentiveTreasury public incentiveTreasury;
    JobEscrow public jobEscrow;
    JobManager public jobManager;
    LeaderManager public leaderManager;
    LuminoToken public token;
    NodeEscrow public nodeEscrow;
    NodeManager public nodeManager;
    WhitelistManager public whitelistManager;

    // Test accounts
    address public admin = address(1);
    address public operator = address(2);
    address public cp1 = address(3);
    address public cp2 = address(4);
    address public cp3 = address(5);
    address public jobSubmitter = address(6);

    // Test constants
    uint256 public constant INITIAL_TOKEN_SUPPLY = 1000 ether;
    uint256 public constant COMPUTE_RATING = 50;
    uint256 public constant STAKE_AMOUNT = 100 ether;
    uint256 public constant JOB_DEPOSIT = 10 ether;
    string public constant MODEL_NAME = "llm_llama3_1_8b";

    function setUp() public {
        vm.startPrank(admin);

        // Deploy core contracts
        token = new LuminoToken();
        accessManager = new AccessManager();
        whitelistManager = new WhitelistManager(address(accessManager));
        epochManager = new EpochManager();

        // Deploy escrow contracts
        nodeEscrow = new NodeEscrow(
            address(accessManager),
            address(token)
        );
        jobEscrow = new JobEscrow(
            address(accessManager),
            address(token)
        );
        incentiveTreasury = new IncentiveTreasury(
            address(token),
            address(accessManager)
        );

        // Deploy manager contracts
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
            address(incentiveTreasury)
        );

        // Set up roles
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(nodeEscrow));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(jobEscrow));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(incentiveTreasury));
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(incentiveManager));
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);

        // Distribute initial tokens
        token.transfer(cp1, INITIAL_TOKEN_SUPPLY);
        token.transfer(cp2, INITIAL_TOKEN_SUPPLY);
        token.transfer(cp3, INITIAL_TOKEN_SUPPLY);
        token.transfer(jobSubmitter, INITIAL_TOKEN_SUPPLY);
        token.transfer(address(incentiveTreasury), INITIAL_TOKEN_SUPPLY * 10);

        vm.stopPrank();
    }

    function testFullProtocolFlow() public {
        // Run through each phase of the protocol
        testPhase1_Onboarding();
        testPhase2_CommitmentSubmission();
        testPhase3_SecretReveal();
        testPhase4_LeaderElection();
        testPhase5_JobAssignment();
        testPhase6_JobExecution();
        testPhase7_RewardsAndPayments();
    }

    function testPhase1_Onboarding() public {
        // 1. Whitelist compute providers
        vm.startPrank(operator);
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);
        whitelistManager.addCP(cp3);
        vm.stopPrank();

        // 2. CPs stake tokens and register nodes
        for (uint256 i = 0; i < 3; i++) {
            address cp = address(uint160(3 + i)); // cp1, cp2, cp3
            vm.startPrank(cp);

            // Approve and stake tokens
            token.approve(address(nodeEscrow), STAKE_AMOUNT);
            nodeEscrow.deposit(STAKE_AMOUNT);

            // Register node
            uint256 nodeId = nodeManager.registerNode(COMPUTE_RATING);
            assertEq(nodeManager.getNodeOwner(nodeId), cp, "Node registration failed");

            vm.stopPrank();
        }
    }

    function testPhase2_CommitmentSubmission() public {
        // Submit commitments during COMMIT phase
        for (uint256 i = 0; i < 3; i++) {
            address cp = address(uint160(3 + i)); // cp1, cp2, cp3
            bytes32 commitment = keccak256(abi.encodePacked("secret", i + 1));

            vm.prank(cp);
            leaderManager.submitCommitment(i + 1, commitment);
        }
    }

    function testPhase3_SecretReveal() public {
        // Move to REVEAL phase
        vm.warp(block.timestamp + 10); // COMMIT_DURATION is 10 seconds

        // Reveal secrets
        for (uint256 i = 0; i < 3; i++) {
            address cp = address(uint160(3 + i));
            bytes memory secret = bytes(string(abi.encodePacked("secret", i + 1)));

            vm.prank(cp);
            leaderManager.revealSecret(i + 1, secret);
        }

        // Verify all nodes revealed
        uint256[] memory revealedNodes = leaderManager.getNodesWhoRevealed(epochManager.getCurrentEpoch());
        assertEq(revealedNodes.length, 3, "Not all nodes revealed");
    }

    function testPhase4_LeaderElection() public {
        // Move to ELECT phase
        vm.warp(block.timestamp + 10); // REVEAL_DURATION is 10 seconds

        // Elect leader
        uint256 leaderId = leaderManager.electLeader();
        assertTrue(leaderId > 0 && leaderId <= 3, "Invalid leader elected");

        // Verify leader was recorded
        uint256 currentLeader = leaderManager.getCurrentLeader();
        assertEq(leaderId, currentLeader, "Leader mismatch");
    }

    function testPhase5_JobAssignment() public {
        // Move to EXECUTE phase
        vm.warp(block.timestamp + 10); // ELECT_DURATION is 10 seconds

        // Submit job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob(MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();

        // Leader assigns job
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        vm.prank(leader);
        jobManager.startAssignmentRound();

        // Verify job assignment
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        assertTrue(assignedNode > 0, "Job not assigned");
    }

    function testPhase6_JobExecution() public {
        // Move to CONFIRM phase
        vm.warp(block.timestamp + 60); // EXECUTE_DURATION is 60 seconds

        // Get assigned node for first job
        uint256 jobId = 1;
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Node confirms and completes job
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId);
        jobManager.completeJob(jobId);
        vm.stopPrank();
    }

    function testPhase7_RewardsAndPayments() public {
        uint256 jobId = 1;
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNode);

        // Record balances before payment
        uint256 initialBalance = token.balanceOf(nodeOwner);

        // Process job payment
        jobManager.processPayment(jobId);

        // Verify payment
        uint256 afterPaymentBalance = token.balanceOf(nodeOwner);
        assertTrue(afterPaymentBalance > initialBalance, "Payment not processed");

        // Move to next epoch
        vm.warp(block.timestamp + 30); // CONFIRM_DURATION + DISPUTE_DURATION = 30 seconds

        // Process rewards
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        incentiveManager.processAll(currentEpoch - 1);

        // Verify rewards
        uint256 finalBalance = token.balanceOf(nodeOwner);
        assertTrue(finalBalance > afterPaymentBalance, "Rewards not distributed");
    }

    // Helper function to verify token balances
    function assertBalanceChange(uint256 before, uint256 afterq, string memory message) internal {
        if (afterq <= before) {
            emit log_named_uint("Before balance", before);
            emit log_named_uint("After balance", afterq);
            emit log_string(message);
            fail();
        }
    }
}