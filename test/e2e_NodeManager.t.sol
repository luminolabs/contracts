// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/NodeManager.sol";
import "../src/NodeEscrow.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract NodeLifecycleE2ETest is Test {
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
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant COMPUTE_RATING_1 = 10;
    uint256 public constant COMPUTE_RATING_2 = 20;
    uint256 public constant STAKE_AMOUNT = 3000 ether;
    uint256 public constant LOCK_PERIOD = 1 days;

    // Events to track
    event CPAdded(address indexed cp, uint256 timestamp);
    event NodeRegistered(address indexed cp, uint256 nodeId, uint256 computeRating);
    event Deposited(address indexed user, uint256 amount, uint256 newBalance, string escrowName);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 unlockTime, string escrowName);
    event Withdrawn(address indexed user, uint256 amount, uint256 remainingBalance, string escrowName);
    event NodeUnregistered(address indexed cp, uint256 nodeId);
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
        
        // Initial token distribution
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        token.transfer(address(nodeEscrow), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testNodeRegistrationFlow() public {
        // 1. Whitelist CP
        vm.startPrank(operator);
        vm.expectEmit(true, false, false, true);
        emit CPAdded(cp1, block.timestamp);
        whitelistManager.addCP(cp1);
        vm.stopPrank();

        // 2. Deposit stake
        vm.startPrank(cp1);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        
        vm.expectEmit(true, false, false, true);
        emit Deposited(cp1, STAKE_AMOUNT, STAKE_AMOUNT, "stake");
        nodeEscrow.deposit(STAKE_AMOUNT);
        
        // Verify balance
        assertEq(nodeEscrow.getBalance(cp1), STAKE_AMOUNT, "Stake deposit failed");

        // 3. Register first node
        uint256 requiredStake1 = COMPUTE_RATING_1 * LShared.STAKE_PER_RATING;
        
        vm.expectEmit(true, false, false, true);
        emit NodeRegistered(cp1, 1, COMPUTE_RATING_1);
        uint256 nodeId1 = nodeManager.registerNode(COMPUTE_RATING_1);
        
        // Verify node registration
        INodeManager.NodeInfo memory nodeInfo1 = nodeManager.getNodeInfo(nodeId1);
        assertEq(nodeInfo1.cp, cp1, "Node owner incorrect");
        assertEq(nodeInfo1.nodeId, nodeId1, "Node ID incorrect");
        assertEq(nodeInfo1.computeRating, COMPUTE_RATING_1, "Compute rating incorrect");
        
        // 4. Register second node with different rating
        uint256 requiredStake2 = COMPUTE_RATING_2 * LShared.STAKE_PER_RATING;
        
        vm.expectEmit(true, false, false, true);
        emit NodeRegistered(cp1, 2, COMPUTE_RATING_2);
        uint256 nodeId2 = nodeManager.registerNode(COMPUTE_RATING_2);
        
        // Verify second node
        INodeManager.NodeInfo memory nodeInfo2 = nodeManager.getNodeInfo(nodeId2);
        assertEq(nodeInfo2.cp, cp1, "Node owner incorrect");
        assertEq(nodeInfo2.nodeId, nodeId2, "Node ID incorrect");
        assertEq(nodeInfo2.computeRating, COMPUTE_RATING_2, "Compute rating incorrect");
        
        // 5. Verify stake requirements updated
        uint256 totalRequiredStake = requiredStake1 + requiredStake2;
        assertEq(nodeManager.getStakeRequirement(cp1), totalRequiredStake, "Stake requirement incorrect");
        
        // 6. Verify nodes are in the correct pools
        uint256[] memory pool1Nodes = nodeManager.getNodesInPool(COMPUTE_RATING_1);
        uint256[] memory pool2Nodes = nodeManager.getNodesInPool(COMPUTE_RATING_2);
        
        assertEq(pool1Nodes.length, 1, "Pool 1 should have 1 node");
        assertEq(pool2Nodes.length, 1, "Pool 2 should have 1 node");
        assertEq(pool1Nodes[0], nodeId1, "Node 1 should be in pool 1");
        assertEq(pool2Nodes[0], nodeId2, "Node 2 should be in pool 2");

        vm.stopPrank();
    }

    function testNodeExitFlow() public {
        // 1. First set up node registration
        _setupRegisteredNode();
        
        uint256 nodeId = 1;
        uint256 remainingStake = STAKE_AMOUNT - (COMPUTE_RATING_1 * LShared.STAKE_PER_RATING);
        
        vm.startPrank(cp1);
        
        // 2. Unregister node
        vm.expectEmit(true, false, false, true);
        emit NodeUnregistered(cp1, nodeId);
        nodeManager.unregisterNode(nodeId);
        
        // Verify node is removed from pool
        uint256[] memory poolNodes = nodeManager.getNodesInPool(COMPUTE_RATING_1);
        assertEq(poolNodes.length, 0, "Node should be removed from pool");
        
        // Verify stake requirement is updated
        assertEq(nodeManager.getStakeRequirement(cp1), 0, "Stake requirement should be zero");
        
        // 3. Request withdrawal
        vm.expectEmit(true, false, false, true);
        emit WithdrawRequested(cp1, remainingStake, block.timestamp + LOCK_PERIOD, "stake");
        nodeEscrow.requestWithdraw(remainingStake);
        
        // 4. Try to withdraw before lock period
        // vm.expectRevert(abi.encodeWithSignature(
        //     "LockPeriodActive(address,uint256)",
        //     cp1,
        //     LOCK_PERIOD - 100
        // ));
        // console.log("CP 1 : ", cp1);
        // console.log("LOCK PERIOD : ", LOCK_PERIOD);
        // nodeEscrow.withdraw();
        
        // 5. Wait for lock period to expire
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        
        // 6. Complete withdrawal
        uint256 balanceBefore = token.balanceOf(cp1);
        
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(cp1, remainingStake, 0, "stake");
        nodeEscrow.withdraw();
        
        // Verify escrow balance
        assertEq(nodeEscrow.getBalance(cp1), 0, "Escrow balance should be zero");
        
        // Verify tokens received
        assertEq(
            token.balanceOf(cp1) - balanceBefore,
            remainingStake,
            "Tokens not correctly withdrawn"
        );
        
        vm.stopPrank();
    }

    function testPartialWithdrawalFlow() public {
        // 1. First set up node registration
        _setupRegisteredNode();
        
        uint256 nodeId = 1;
        uint256 stakeRequirement = COMPUTE_RATING_1 * LShared.STAKE_PER_RATING;
        uint256 excessStake = STAKE_AMOUNT - stakeRequirement;
        
        vm.startPrank(cp1);
        
        // 2. Request partial withdrawal (only excess stake)
        vm.expectEmit(true, false, false, true);
        emit WithdrawRequested(cp1, excessStake, block.timestamp + LOCK_PERIOD, "stake");
        nodeEscrow.requestWithdraw(excessStake);
        
        // 3. Wait for lock period to expire
        vm.warp(block.timestamp + LOCK_PERIOD + 1);
        
        // 4. Complete partial withdrawal
        uint256 balanceBefore = token.balanceOf(cp1);
        
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(cp1, excessStake, stakeRequirement, "stake");
        nodeEscrow.withdraw();
        
        // Verify escrow balance matches stake requirement
        assertEq(nodeEscrow.getBalance(cp1), stakeRequirement, "Escrow balance should match stake requirement");
        
        // Verify tokens received
        assertEq(
            token.balanceOf(cp1) - balanceBefore,
            excessStake,
            "Tokens not correctly withdrawn"
        );
        
        // 5. Verify node is still active
        INodeManager.NodeInfo memory nodeInfo = nodeManager.getNodeInfo(nodeId);
        assertEq(nodeInfo.cp, cp1, "Node should still be owned by CP");
        assertEq(nodeInfo.computeRating, COMPUTE_RATING_1, "Compute rating should be unchanged");
        
        vm.stopPrank();
    }

    function testInsufficientStakeRegistration() public {
        // 1. Whitelist CP
        vm.startPrank(operator);
        whitelistManager.addCP(cp1);
        vm.stopPrank();

        // 2. Deposit insufficient stake
        uint256 requiredStake = COMPUTE_RATING_1 * LShared.STAKE_PER_RATING;
        uint256 insufficientStake = requiredStake - 1;
        
        vm.startPrank(cp1);
        token.approve(address(nodeEscrow), insufficientStake);
        nodeEscrow.deposit(insufficientStake);
        
        // 3. Attempt node registration
        vm.expectRevert(abi.encodeWithSignature(
            "InsufficientBalance(address,uint256,uint256)",
            cp1,
            requiredStake,
            insufficientStake
        ));
        nodeManager.registerNode(COMPUTE_RATING_1);
        
        vm.stopPrank();
    }

    function testNonWhitelistedRegistration() public {
        // 1. Deposit stake but don't whitelist
        vm.startPrank(cp2);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);
        
        // 2. Attempt node registration
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", cp2));
        nodeManager.registerNode(COMPUTE_RATING_1);
        
        vm.stopPrank();
    }

    function testUnauthorizedNodeUnregistration() public {
        // 1. First set up node registration
        _setupRegisteredNode();
        
        uint256 nodeId = 1;
        
        // 2. Attempt unregistration from unauthorized account
        vm.startPrank(cp2);
        vm.expectRevert(abi.encodeWithSignature(
            "InvalidNodeOwner(uint256,address)",
            nodeId,
            cp2
        ));
        nodeManager.unregisterNode(nodeId);
        
        vm.stopPrank();
    }

    // Helper function to setup a registered node for testing
    function _setupRegisteredNode() internal {
        // Whitelist CP
        vm.startPrank(operator);
        whitelistManager.addCP(cp1);
        vm.stopPrank();
        
        // Deposit stake and register node
        vm.startPrank(cp1);
        token.approve(address(nodeEscrow), STAKE_AMOUNT);
        nodeEscrow.deposit(STAKE_AMOUNT);
        nodeManager.registerNode(COMPUTE_RATING_1);
        vm.stopPrank();
    }
}