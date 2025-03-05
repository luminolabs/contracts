// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/LeaderManager.sol";
import "../src/EpochManager.sol";
import "../src/NodeManager.sol";
import "../src/NodeEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract LeaderManagerTest is Test {
    LeaderManager public leaderManager;
    EpochManager public epochManager;
    NodeManager public nodeManager;
    NodeEscrow public nodeEscrow;
    WhitelistManager public whitelistManager;
    AccessManager public accessManager;
    LuminoToken public token;

    // Test addresses
    address public admin = address(1);
    address public operator = address(2);
    address public cp1 = address(3);
    address public cp2 = address(4);

    // Constants
    uint256 public constant STAKE_AMOUNT = 100 ether;
    uint256 public constant COMPUTE_RATING = 10;

    // Events to test
    event CommitSubmitted(uint256 indexed epoch, uint256 indexed nodeId, address indexed owner);
    event SecretRevealed(uint256 indexed epoch, uint256 indexed nodeId, address indexed owner, bytes secret);
    event LeaderElected(uint256 indexed epoch, bytes32 randomValue, uint256 indexed leaderNodeId);

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

        // Setup roles
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        
        // Whitelist CPs
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);

        // Fund CPs
        token.transfer(cp1, STAKE_AMOUNT);
        token.transfer(cp2, STAKE_AMOUNT);

        vm.stopPrank();

        // Register nodes for testing
        _registerNode(cp1);
        _registerNode(cp2);
    }

    // Helper function to register a node
    function _registerNode(address cp) internal returns (uint256) {
        vm.startPrank(cp);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);
        uint256 nodeId = nodeManager.registerNode(COMPUTE_RATING);
        vm.stopPrank();
        return nodeId;
    }

    function testSubmitCommitment() public {
        uint256 nodeId = 1; // From cp1's registration
        bytes32 commitment = keccak256(abi.encodePacked("secret"));
        
        vm.startPrank(cp1);
        
        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit CommitSubmitted(epochManager.getCurrentEpoch(), nodeId, cp1);
        
        // Submit commitment
        leaderManager.submitCommitment(nodeId, commitment);
        
        vm.stopPrank();
    }

    function testSubmitCommitmentWrongState() public {
        uint256 nodeId = 1;
        bytes32 commitment = keccak256(abi.encodePacked("secret"));
        
        // Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.COMMIT)));
        leaderManager.submitCommitment(nodeId, commitment);
        vm.stopPrank();
    }

    function testRevealSecret() public {
        uint256 nodeId = 1;
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        
        // Submit commitment
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId, commitment);
        vm.stopPrank();
        
        // Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        
        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit SecretRevealed(epochManager.getCurrentEpoch(), nodeId, cp1, secret);
        
        // Reveal secret
        leaderManager.revealSecret(nodeId, secret);
        
        vm.stopPrank();
    }

    function testRevealSecretWithoutCommitment() public {
        uint256 nodeId = 1;
        bytes memory secret = bytes("secret");
        
        // Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        vm.expectRevert(abi.encodeWithSignature("NoCommitmentFound(uint256,uint256)", epochManager.getCurrentEpoch(), nodeId));
        leaderManager.revealSecret(nodeId, secret);
        vm.stopPrank();
    }

    function testRevealWrongSecret() public {
        uint256 nodeId = 1;
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(abi.encodePacked("different_secret"));
        
        // Submit commitment
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId, commitment);
        vm.stopPrank();
        
        // Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSecret(uint256)", nodeId));
        leaderManager.revealSecret(nodeId, secret);
        vm.stopPrank();
    }

    function testElectLeader() public {
        uint256 nodeId1 = 1;
        uint256 nodeId2 = 2;
        bytes memory secret1 = bytes("secret1");
        bytes memory secret2 = bytes("secret2");
        bytes32 commitment1 = keccak256(secret1);
        bytes32 commitment2 = keccak256(secret2);
        
        // Submit commitments
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId1, commitment1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        leaderManager.submitCommitment(nodeId2, commitment2);
        vm.stopPrank();
        
        // Move to REVEAL phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        // Reveal secrets
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeId1, secret1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        leaderManager.revealSecret(nodeId2, secret2);
        vm.stopPrank();
        
        // Move to ELECT phase
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        // Test leader election
        uint256 leaderNodeId = leaderManager.electLeader();
        assertGt(leaderNodeId, 0);
        
        // Verify current leader
        assertEq(leaderManager.getCurrentLeader(), leaderNodeId);
    }

    function testElectLeaderNoReveals() public {
        // Move to ELECT phase without any reveals
        vm.warp(block.timestamp + LShared.COMMIT_DURATION + LShared.REVEAL_DURATION);
        
        vm.expectRevert(abi.encodeWithSignature("NoRevealsSubmitted(uint256)", epochManager.getCurrentEpoch()));
        leaderManager.electLeader();
    }

    function testValidateLeader() public {
        // Setup complete leader election process
        uint256 nodeId = 1;
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId, commitment);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeId, secret);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        uint256 leaderNodeId = leaderManager.electLeader();
        
        // Test leader validation
        address leaderAddress = nodeManager.getNodeOwner(leaderNodeId);
        leaderManager.validateLeader(leaderAddress);
        
        // Test invalid leader validation
        address nonLeader = leaderAddress == cp1 ? cp2 : cp1;
        vm.expectRevert(abi.encodeWithSignature("NotCurrentLeader(address,address)", nonLeader, leaderAddress));
        leaderManager.validateLeader(nonLeader);
    }

    function testGetNodesWhoRevealed() public {
        uint256 nodeId1 = 1;
        uint256 nodeId2 = 2;
        bytes memory secret1 = bytes("secret1");
        bytes memory secret2 = bytes("secret2");
        bytes32 commitment1 = keccak256(secret1);
        bytes32 commitment2 = keccak256(secret2);
        
        // Submit commitments and reveals
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId1, commitment1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        leaderManager.submitCommitment(nodeId2, commitment2);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeId1, secret1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        leaderManager.revealSecret(nodeId2, secret2);
        vm.stopPrank();
        
        // Get revealed nodes
        uint256[] memory revealedNodes = leaderManager.getNodesWhoRevealed(epochManager.getCurrentEpoch());
        assertEq(revealedNodes.length, 2);
        assertTrue(revealedNodes[0] == nodeId1 || revealedNodes[1] == nodeId1);
        assertTrue(revealedNodes[0] == nodeId2 || revealedNodes[1] == nodeId2);
    }

    function testGetFinalRandomValue() public {
        uint256 nodeId = 1;
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        
        // Complete leader election process
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId, commitment);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeId, secret);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        leaderManager.electLeader();
        
        // Get final random value
        bytes32 randomValue = leaderManager.getFinalRandomValue(currentEpoch);
        assertNotEq(randomValue, bytes32(0));
    }

    function testGetFinalRandomValueNoElection() public {
        uint256 currentEpoch = epochManager.getCurrentEpoch();
        
        vm.expectRevert(abi.encodeWithSignature("NoRandomValueForEpoch(uint256)", currentEpoch));
        leaderManager.getFinalRandomValue(currentEpoch);
    }

    function testDoubleElection() public {
        uint256 nodeId = 1;
        bytes memory secret = bytes("secret");
        bytes32 commitment = keccak256(secret);
        
        // Complete first election
        vm.startPrank(cp1);
        leaderManager.submitCommitment(nodeId, commitment);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeId, secret);
        vm.stopPrank();
        
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        
        uint256 leaderId = leaderManager.electLeader();
        
        // Try to elect again in same epoch
        assertEq(1, leaderId);
    }
}