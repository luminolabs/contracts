// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/EpochManager.sol";
import "../src/LeaderManager.sol";
import "../src/NodeManager.sol";
import "../src/NodeEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/JobManager.sol";
import "../src/JobEscrow.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract EpochStateTransitionsE2ETest is Test {
    EpochManager public epochManager;
    LeaderManager public leaderManager;
    NodeManager public nodeManager;
    NodeEscrow public nodeEscrow;
    WhitelistManager public whitelistManager;
    AccessManager public accessManager;
    JobManager public jobManager;
    JobEscrow public jobEscrow;
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
    uint256 public constant JOB_DEPOSIT = 20 ether;
    string public constant MODEL_NAME = "llm_llama3_1_8b";

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
        token.transfer(address(nodeEscrow), INITIAL_BALANCE * 10);

        vm.stopPrank();

        // Start at a clean epoch boundary
        vm.warp(0);
        
        // Setup nodes
        _setupNodes();
    }

    function testCompleteEpochCycle() public {
        // 1. Verify and validate initial state (COMMIT)
        IEpochManager.State currentState;
        uint256 timeLeft;
        
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.COMMIT), "Initial state should be COMMIT");
        assertEq(timeLeft, LShared.COMMIT_DURATION, "Time left should be COMMIT_DURATION");
        
        // Validate state using contract function
        epochManager.validateEpochState(IEpochManager.State.COMMIT);
        
        // 2. Submit commitments during COMMIT phase
        _submitCommitments();
        
        // 3. Move to REVEAL state and validate
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.REVEAL), "State should be REVEAL");
        assertEq(timeLeft, LShared.REVEAL_DURATION, "Time left should be REVEAL_DURATION");
        
        epochManager.validateEpochState(IEpochManager.State.REVEAL);
        
        // 4. Reveal secrets during REVEAL phase
        _revealSecrets();
        
        // 5. Move to ELECT state and validate
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.ELECT), "State should be ELECT");
        assertEq(timeLeft, LShared.ELECT_DURATION, "Time left should be ELECT_DURATION");
        
        epochManager.validateEpochState(IEpochManager.State.ELECT);
        
        // 6. Elect leader during ELECT phase
        uint256 leaderId = _electLeader();
        address leaderAddress = nodeManager.getNodeOwner(leaderId);
        
        // 7. Move to EXECUTE state and validate
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.EXECUTE), "State should be EXECUTE");
        assertEq(timeLeft, LShared.EXECUTE_DURATION, "Time left should be EXECUTE_DURATION");
        
        epochManager.validateEpochState(IEpochManager.State.EXECUTE);
        
        // 8. Set up and assign jobs during EXECUTE phase
        _setupAndAssignJobs(leaderAddress);
        
        // 9. Move to CONFIRM state and validate
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION);
        
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.CONFIRM), "State should be CONFIRM");
        assertEq(timeLeft, LShared.CONFIRM_DURATION, "Time left should be CONFIRM_DURATION");
        
        epochManager.validateEpochState(IEpochManager.State.CONFIRM);
        
        // 10. Confirm assigned jobs during CONFIRM phase
        _confirmJobs();
        
        // 11. Move to DISPUTE state and validate
        vm.warp(block.timestamp + LShared.CONFIRM_DURATION);
        
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.DISPUTE), "State should be DISPUTE");
        assertEq(timeLeft, LShared.DISPUTE_DURATION, "Time left should be DISPUTE_DURATION");
        
        epochManager.validateEpochState(IEpochManager.State.DISPUTE);
        
        // 12. Validate cycle completion and transition to next epoch
        vm.warp(block.timestamp + LShared.DISPUTE_DURATION);
        
        // Should be back to COMMIT for the next epoch
        (currentState, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.COMMIT), "Should return to COMMIT state");
        assertEq(timeLeft, LShared.COMMIT_DURATION, "Time left should be COMMIT_DURATION");
        
        // Verify epoch number advanced
        assertEq(epochManager.getCurrentEpoch(), 2, "Epoch should have advanced");
    }

    function testInvalidStateAccess() public {
        // 1. Start in COMMIT phase
        (IEpochManager.State currentState, ) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.COMMIT), "Initial state should be COMMIT");
        
        // 2. Attempt to perform REVEAL phase action
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret1");
        bytes32 commitment = keccak256(secret);
        
        // First submit commitment (valid in COMMIT phase)
        leaderManager.submitCommitment(nodeIds[0], commitment);
        
        // Try to reveal secret (should fail, wrong phase)
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.REVEAL)));
        leaderManager.revealSecret(nodeIds[0], secret);
        vm.stopPrank();
        
        // 3. Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        (currentState, ) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.REVEAL), "State should be REVEAL");
        
        // 4. Attempt to perform COMMIT phase action
        vm.startPrank(cp2);
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.COMMIT)));
        leaderManager.submitCommitment(nodeIds[1], keccak256(bytes("secret2")));
        vm.stopPrank();
        
        // 5. Move to ELECT phase
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeIds[0], secret);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        (currentState, ) = epochManager.getEpochState();
        assertEq(uint256(currentState), uint256(IEpochManager.State.ELECT), "State should be ELECT");
        
        // 6. Attempt to perform EXECUTE phase action
        vm.startPrank(cp1);
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.EXECUTE)));
        jobManager.startAssignmentRound();
        vm.stopPrank();
    }

    function testPartialEpochParticipation() public {
        // 1. Submit commitment and reveal for cp1, but not for cp2
        vm.startPrank(cp1);
        bytes memory secret = bytes("secret1");
        bytes32 commitment = keccak256(secret);
        leaderManager.submitCommitment(nodeIds[0], commitment);
        vm.stopPrank();
        
        // 2. Transition to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeIds[0], secret);
        vm.stopPrank();
        
        // 3. Move to ELECT phase and elect leader (only cp1 participated)
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        uint256 leaderId = leaderManager.electLeader();
        address leaderAddress = nodeManager.getNodeOwner(leaderId);
        
        // Leader should be cp1 since it's the only participant
        assertEq(leaderAddress, cp1, "Leader should be cp1");
        
        // 4. Validate cp2 cannot participate late
        vm.startPrank(cp2);
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.COMMIT)));
        leaderManager.submitCommitment(nodeIds[1], keccak256(bytes("secret2")));
        vm.stopPrank();
    }

    function testCrossEpochInvalidOperations() public {
        // 1. Setup leader election for epoch 1
        _setupLeaderElection();
        uint256 epoch1Leader = leaderManager.getCurrentLeader();
        address leader1 = nodeManager.getNodeOwner(epoch1Leader);
        
        // 2. Complete epoch 1 and move to epoch 2
        vm.warp(LShared.EPOCH_DURATION);
        assertEq(epochManager.getCurrentEpoch(), 2, "Should be in epoch 2");
        
        // 3. Try to use epoch 1 leader permissions in epoch 2
        vm.startPrank(leader1);
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.EXECUTE)));
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 4. Setup new leader election for epoch 2
        _setupLeaderElection();
        uint256 epoch2Leader = leaderManager.getCurrentLeader();
        address leader2 = nodeManager.getNodeOwner(epoch2Leader);
        
        // 5. Verify leader permissions are properly assigned in epoch 2
        // Whether it's the same leader or a new one, they should have valid permissions in epoch 2
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        
        // 6. Verify current leader (epoch 2) has proper permissions
        vm.startPrank(leader2);
        // This should succeed because leader2 is the current epoch's leader
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // 7. Verify that if leader1 is not the current leader, they cannot use leader permissions
        if (leader1 != leader2) {
            vm.startPrank(leader1);
            vm.expectRevert(); // Will fail if leader1 is not the current leader
            jobManager.startAssignmentRound();
            vm.stopPrank();
        }
        
        // 8. Move to next epoch (epoch 3)
        vm.warp(LShared.EPOCH_DURATION * 2);
        assertEq(epochManager.getCurrentEpoch(), 3, "Should be in epoch 3");
        
        // 9. Verify epoch 2 leader no longer has permissions in epoch 3
        vm.startPrank(leader2);
        vm.expectRevert();
        jobManager.startAssignmentRound();
        vm.stopPrank();
    }
    
    // Helper Functions

    function _setupNodes() internal {
        vm.startPrank(operator);
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);
        vm.stopPrank();

        address[2] memory cps = [cp1, cp2];
        for (uint256 i = 0; i < cps.length; i++) {
            vm.startPrank(cps[i]);
            
            // Generate unique secret and commitment for later
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
    }

    function _submitCommitments() internal {
        address[2] memory cps = [cp1, cp2];
        for (uint256 i = 0; i < nodeIds.length; i++) {
            vm.startPrank(cps[i]);
            leaderManager.submitCommitment(nodeIds[i], commitments[cps[i]]);
            vm.stopPrank();
        }
    }

    function _revealSecrets() internal {
        address[2] memory cps = [cp1, cp2];
        for (uint256 i = 0; i < nodeIds.length; i++) {
            vm.startPrank(cps[i]);
            leaderManager.revealSecret(nodeIds[i], secrets[cps[i]]);
            vm.stopPrank();
        }
    }

    function _electLeader() internal returns (uint256) {
        return leaderManager.electLeader();
    }
    
    function _setupAndAssignJobs(address leader) internal {
        // Submit job
        vm.startPrank(jobSubmitter);
        token.approve(address(jobEscrow), JOB_DEPOSIT);
        jobEscrow.deposit(JOB_DEPOSIT);
        uint256 jobId = jobManager.submitJob("test job", MODEL_NAME, COMPUTE_RATING);
        vm.stopPrank();
        
        // Assign job
        vm.startPrank(leader);
        jobManager.startAssignmentRound();
        vm.stopPrank();
        
        // Verify job is assigned
        uint256 assignedNode = jobManager.getAssignedNode(jobId);
        assertTrue(assignedNode > 0, "Job should be assigned");
    }
    
    function _confirmJobs() internal {
        // Find assigned jobs and confirm them
        uint256 jobId = 1; // First job ID
        uint256 assignedNodeId = jobManager.getAssignedNode(jobId);
        address nodeOwner = nodeManager.getNodeOwner(assignedNodeId);
        
        vm.startPrank(nodeOwner);
        jobManager.confirmJob(jobId);
        vm.stopPrank();
    }
    
    function _setupLeaderElection() internal {
        // Submit commitments
        _submitCommitments();
        
        // Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        // Reveal secrets
        _revealSecrets();
        
        // Move to ELECT phase
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        // Elect leader
        _electLeader();
    }
}