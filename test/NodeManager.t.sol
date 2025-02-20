// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/NodeManager.sol";
import "../src/NodeEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract NodeManagerTest is Test {
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

    // Events to test
    event NodeRegistered(address indexed cp, uint256 nodeId, uint256 computeRating);
    event NodeUnregistered(address indexed cp, uint256 nodeId);
    event NodeUpdated(uint256 indexed nodeId, uint256 newComputeRating);
    event StakeValidated(address indexed cp, uint256 computeRating, bool isValid);
    event StakeRequirementUpdated(address indexed cp, uint256 newRequirement);

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        token = new LuminoToken();
        accessManager = new AccessManager();
        nodeEscrow = new NodeEscrow(address(accessManager), address(token));
        whitelistManager = new WhitelistManager(address(accessManager));
        nodeManager = new NodeManager(
            address(nodeEscrow),
            address(whitelistManager),
            address(accessManager)
        );

        // Setup roles
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        accessManager.grantRole(LShared.CONTRACTS_ROLE, address(nodeManager));
        
        // Whitelist CPs
        whitelistManager.addCP(cp1);
        whitelistManager.addCP(cp2);

        // Fund CPs with tokens
        token.transfer(cp1, 1000 * 10**18);
        token.transfer(cp2, 1000 * 10**18);

        vm.stopPrank();
    }

    function testRegisterNode() public {
        uint256 computeRating = 10;
        uint256 requiredStake = computeRating * LShared.STAKE_PER_RATING;

        vm.startPrank(cp1);
        
        // Approve tokens for staking
        token.approve(address(nodeEscrow), requiredStake);
        
        // Deposit stake
        nodeEscrow.deposit(requiredStake);

        // Test event emission
        vm.expectEmit(true, false, false, true);
        emit NodeRegistered(cp1, 1, computeRating);
        
        // Register node
        uint256 nodeId = nodeManager.registerNode(computeRating);
        
        // Verify node info
        INodeManager.NodeInfo memory nodeInfo = nodeManager.getNodeInfo(nodeId);
        assertEq(nodeInfo.cp, cp1);
        assertEq(nodeInfo.nodeId, nodeId);
        assertEq(nodeInfo.computeRating, computeRating);
        
        vm.stopPrank();
    }

    function testRegisterMultipleNodes() public {
        uint256 computeRating1 = 10;
        uint256 computeRating2 = 20;
        uint256 totalRequiredStake = (computeRating1 + computeRating2) * LShared.STAKE_PER_RATING;

        vm.startPrank(cp1);
        
        // Approve and deposit stake
        token.approve(address(nodeEscrow), totalRequiredStake);
        nodeEscrow.deposit(totalRequiredStake);

        // Register first node
        uint256 nodeId1 = nodeManager.registerNode(computeRating1);
        
        // Register second node
        uint256 nodeId2 = nodeManager.registerNode(computeRating2);
        
        // Verify nodes are in the same pool
        uint256[] memory nodesInPool10 = nodeManager.getNodesInPool(computeRating1);
        uint256[] memory nodesInPool20 = nodeManager.getNodesInPool(computeRating2);
        
        assertEq(nodesInPool10.length, 1);
        assertEq(nodesInPool20.length, 1);
        assertEq(nodesInPool10[0], nodeId1);
        assertEq(nodesInPool20[0], nodeId2);
        
        vm.stopPrank();
    }

    function testUnregisterNode() public {
        vm.startPrank(cp1);
        
        // First register a node
        uint256 computeRating = 10;
        uint256 requiredStake = computeRating * LShared.STAKE_PER_RATING;
        
        token.approve(address(nodeEscrow), requiredStake);
        nodeEscrow.deposit(requiredStake);
        uint256 nodeId = nodeManager.registerNode(computeRating);
        
        // Test event emission for unregistration
        vm.expectEmit(true, false, false, true);
        emit NodeUnregistered(cp1, nodeId);
        
        // Unregister node
        nodeManager.unregisterNode(nodeId);
        
        // Verify node is removed from pool
        uint256[] memory nodesInPool = nodeManager.getNodesInPool(computeRating);
        assertEq(nodesInPool.length, 0);
        
        vm.stopPrank();
    }

    function testNodeOwnerValidation() public {
        vm.startPrank(cp1);
        
        // Register a node
        uint256 computeRating = 10;
        uint256 requiredStake = computeRating * LShared.STAKE_PER_RATING;
        
        token.approve(address(nodeEscrow), requiredStake);
        nodeEscrow.deposit(requiredStake);
        uint256 nodeId = nodeManager.registerNode(computeRating);
        
        vm.stopPrank();
        
        // Try to unregister from different address
        vm.startPrank(cp2);
        vm.expectRevert(abi.encodeWithSignature("InvalidNodeOwner(uint256,address)", nodeId, cp2));
        nodeManager.unregisterNode(nodeId);
        vm.stopPrank();
    }

    function testInsufficientStake() public {
        uint256 computeRating = 10;
        uint256 insufficientStake = (computeRating * LShared.STAKE_PER_RATING) - 1;

        vm.startPrank(cp1);
        
        // Deposit insufficient stake
        token.approve(address(nodeEscrow), insufficientStake);
        nodeEscrow.deposit(insufficientStake);
        
        // Try to register node
        vm.expectRevert(abi.encodeWithSignature(
            "InsufficientBalance(address,uint256,uint256)", 
            cp1,
            computeRating * LShared.STAKE_PER_RATING,
            insufficientStake
        ));
        nodeManager.registerNode(computeRating);
        
        vm.stopPrank();
    }

    function testGetNodesInPool() public {
        vm.startPrank(cp1);
        
        // Register multiple nodes with different compute ratings
        uint256 rating1 = 10;
        uint256 rating2 = 20;
        uint256 totalStake = (rating1 + rating2) * LShared.STAKE_PER_RATING;
        
        token.approve(address(nodeEscrow), totalStake);
        nodeEscrow.deposit(totalStake);
        
        uint256 nodeId1 = nodeManager.registerNode(rating1);
        uint256 nodeId2 = nodeManager.registerNode(rating2);
        
        // Check nodes in each pool
        uint256[] memory pool10 = nodeManager.getNodesInPool(rating1);
        uint256[] memory pool20 = nodeManager.getNodesInPool(rating2);
        
        assertEq(pool10.length, 1);
        assertEq(pool20.length, 1);
        assertEq(pool10[0], nodeId1);
        assertEq(pool20[0], nodeId2);
        
        vm.stopPrank();
    }

    function testGetStakeRequirement() public {
        vm.startPrank(cp1);
        
        // Initially should be 0
        assertEq(nodeManager.getStakeRequirement(cp1), 0);
        
        // Register a node
        uint256 computeRating = 10;
        uint256 requiredStake = computeRating * LShared.STAKE_PER_RATING;
        
        token.approve(address(nodeEscrow), requiredStake);
        nodeEscrow.deposit(requiredStake);
        nodeManager.registerNode(computeRating);
        
        // Check updated requirement
        assertEq(nodeManager.getStakeRequirement(cp1), requiredStake);
        
        // Register another node
        uint256 computeRating2 = 20;
        uint256 additionalStake = computeRating2 * LShared.STAKE_PER_RATING;
        
        token.approve(address(nodeEscrow), additionalStake);
        nodeEscrow.deposit(additionalStake);
        nodeManager.registerNode(computeRating2);
        
        // Check final requirement
        assertEq(nodeManager.getStakeRequirement(cp1), requiredStake + additionalStake);
        
        vm.stopPrank();
    }

    function testWhitelistRequirement() public {
        uint256 computeRating = 10;
        uint256 requiredStake = computeRating * LShared.STAKE_PER_RATING;

        // Use non-whitelisted address
        address nonWhitelistedCP = address(5);
        vm.startPrank(admin);
        token.transfer(nonWhitelistedCP, requiredStake);
        vm.stopPrank();

        vm.startPrank(nonWhitelistedCP);
        
        token.approve(address(nodeEscrow), requiredStake);
        nodeEscrow.deposit(requiredStake);
        
        // Try to register node
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", nonWhitelistedCP));
        nodeManager.registerNode(computeRating);
        
        vm.stopPrank();
    }
}