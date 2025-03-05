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

contract LeaderElectionE2ETest is Test {
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
    address public cp3 = address(5);

    // Node tracking
    uint256[] public nodeIds;
    mapping(address => bytes) public secrets;
    mapping(address => bytes32) public commitments;

    // Constants
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant COMPUTE_RATING = 10;
    uint256 public constant STAKE_AMOUNT = 1000 ether;

    // Events to track
    event CommitSubmitted(
        uint256 indexed epoch,
        uint256 indexed nodeId,
        address indexed owner
    );
    event SecretRevealed(
        uint256 indexed epoch,
        uint256 indexed nodeId,
        address indexed owner,
        bytes secret
    );
    event LeaderElected(
        uint256 indexed epoch,
        bytes32 randomValue,
        uint256 indexed leaderNodeId
    );

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

        // Initial token distribution
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(cp3, INITIAL_BALANCE);
        token.transfer(address(nodeEscrow), INITIAL_BALANCE * 10);

        vm.stopPrank();

        // Start at a clean epoch boundary
        vm.warp(0);
    }

    function testSuccessfulLeaderElection() public {
        // 1. Setup: Whitelist CPs and register nodes
        _whitelistAndRegisterNodes();

        // Verify nodes are properly registered
        for (uint256 i = 0; i < nodeIds.length; i++) {
            assertTrue(nodeIds[i] > 0, "Node registration failed");
        }

        // 2. Commit Phase
        _submitCommitments();

        // 3. Reveal Phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        _revealSecrets();

        // 4. Election Phase
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        uint256 leaderId = _electLeader();

        // 5. Verify Leader
        _verifyLeaderPermissions(leaderId);
    }

    // Helper Functions

    function _whitelistAndRegisterNodes() internal {
        vm.startPrank(operator);
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);
        whitelistManager.addCP(cp3);
        vm.stopPrank();

        address[3] memory cps = [cp1, cp2, cp3];
        for (uint256 i = 0; i < cps.length; i++) {
            vm.startPrank(cps[i]);

            // Generate unique secret and commitment
            bytes memory secret = bytes(
                string(abi.encodePacked("secret", vm.toString(i + 1)))
            );
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
        address[3] memory cps = [cp1, cp2, cp3];
        for (uint256 i = 0; i < nodeIds.length; i++) {
            vm.startPrank(cps[i]);

            vm.expectEmit(true, true, true, true);
            emit CommitSubmitted(
                epochManager.getCurrentEpoch(),
                nodeIds[i],
                cps[i]
            );

            leaderManager.submitCommitment(nodeIds[i], commitments[cps[i]]);
            vm.stopPrank();
        }
    }

    function _revealSecrets() internal {
        address[3] memory cps = [cp1, cp2, cp3];
        for (uint256 i = 0; i < nodeIds.length; i++) {
            vm.startPrank(cps[i]);

            vm.expectEmit(true, true, true, true);
            emit SecretRevealed(
                epochManager.getCurrentEpoch(),
                nodeIds[i],
                cps[i],
                secrets[cps[i]]
            );

            leaderManager.revealSecret(nodeIds[i], secrets[cps[i]]);
            vm.stopPrank();
        }
    }

    function _electLeader() internal returns (uint256) {
        uint256 currentEpoch = epochManager.getCurrentEpoch();

        // Start recording events
        vm.recordLogs();

        // Elect leader
        uint256 leaderId = leaderManager.electLeader();
        assertTrue(leaderId > 0, "Leader election failed");

        // Get the emitted events
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find and verify the LeaderElected event
        bool foundEvent = false;
        for (uint256 i = 0; i < entries.length; i++) {
            // The event signature is the first topic
            if (
                entries[i].topics[0] ==
                keccak256("LeaderElected(uint256,bytes32,uint256)")
            ) {
                foundEvent = true;
                // Verify epoch (first indexed parameter)
                assertEq(
                    uint256(entries[i].topics[1]),
                    currentEpoch,
                    "Wrong epoch in event"
                );
                // Verify leader ID (third indexed parameter)
                assertEq(
                    uint256(entries[i].topics[2]),
                    leaderId,
                    "Wrong leader ID in event"
                );
                break;
            }
        }
        assertTrue(foundEvent, "LeaderElected event not emitted");

        // Verify random value was generated
        bytes32 randomValue = leaderManager.getFinalRandomValue(currentEpoch);
        assertTrue(randomValue != bytes32(0), "Random value not generated");

        // Verify this is the current leader
        assertEq(
            leaderManager.getCurrentLeader(),
            leaderId,
            "Leader not set correctly"
        );

        return leaderId;
    }

    function _verifyLeaderPermissions(uint256 leaderId) internal {
        address leader = nodeManager.getNodeOwner(leaderId);
        
        // 1. Verify leader permissions in ELECT phase
        vm.startPrank(leader);
        leaderManager.validateLeader(leader);
        vm.stopPrank();

        // 2. Test non-leader permissions
        address nonLeader = (leader == cp1) ? cp2 : cp1;
        vm.startPrank(nonLeader);
        vm.expectRevert(abi.encodeWithSignature(
            "NotCurrentLeader(address,address)",
            nonLeader,
            leader
        ));
        leaderManager.validateLeader(nonLeader);
        vm.stopPrank();

        // 3. Verify permissions in EXECUTE phase (should still be valid)
        vm.warp(block.timestamp + LShared.ELECT_DURATION);
        vm.startPrank(leader);
        leaderManager.validateLeader(leader);
        vm.stopPrank();

        // 4. Move to next epoch and verify leader permissions from previous epoch are invalid
        vm.warp(block.timestamp + LShared.EXECUTE_DURATION + LShared.CONFIRM_DURATION + LShared.DISPUTE_DURATION); // Move to next epoch
        
        
        // Setup next epoch's leader election
        uint256 nextEpochLeaderId = _setupNextEpochLeader();
        address nextEpochLeader = nodeManager.getNodeOwner(nextEpochLeaderId);
        
        // Previous leader should not have validation privileges in new epoch if they are not the new leader
        if (leader != nextEpochLeader) {
            vm.startPrank(leader);
            vm.expectRevert(abi.encodeWithSignature(
                "NotCurrentLeader(address,address)",
                leader,
                nextEpochLeader
            ));
            leaderManager.validateLeader(leader);
            vm.stopPrank();
        }
    }

    function _setupNextEpochLeader() internal returns (uint256) {        
        // Submit commitments for cp1 and cp2
        vm.startPrank(cp1);
        bytes memory secret1 = bytes(string(abi.encodePacked("nextEpochSecret1")));
        bytes32 commitment1 = keccak256(secret1);
        leaderManager.submitCommitment(nodeIds[0], commitment1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        bytes memory secret2 = bytes(string(abi.encodePacked("nextEpochSecret2")));
        bytes32 commitment2 = keccak256(secret2);
        leaderManager.submitCommitment(nodeIds[1], commitment2);
        vm.stopPrank();
        
        // Move to reveal phase
        vm.warp(block.timestamp + LShared.COMMIT_DURATION);
        
        // Reveal secrets
        vm.startPrank(cp1);
        leaderManager.revealSecret(nodeIds[0], secret1);
        vm.stopPrank();
        
        vm.startPrank(cp2);
        leaderManager.revealSecret(nodeIds[1], secret2);
        vm.stopPrank();
        
        // Move to elect phase and elect leader
        vm.warp(block.timestamp + LShared.REVEAL_DURATION);
        uint256 nextLeaderId = leaderManager.electLeader();
        
        // Verify we have a leader for this epoch
        assert(nextLeaderId > 0);
        
        return nextLeaderId;
    }
}
