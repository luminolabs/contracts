// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/NodeEscrow.sol";
import "../src/AccessManager.sol";
import "../src/LuminoToken.sol";
import "../src/libraries/LShared.sol";

contract NodeEscrowTest is Test {
    NodeEscrow public nodeEscrow;
    AccessManager public accessManager;
    LuminoToken public token;

    // Test addresses
    address public admin = address(1);
    address public operator = address(2);
    address public cp1 = address(3);
    address public cp2 = address(4);
    address public contractRole = address(5);

    // Constants
    uint256 public constant MIN_DEPOSIT = 0.1 ether;
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant PENALTY_AMOUNT = 50 ether;
    uint256 public constant REWARD_AMOUNT = 25 ether;

    // Events to test
    event Deposited(address indexed user, uint256 amount, uint256 newBalance, string escrowName);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 unlockTime, string escrowName);
    event WithdrawCancelled(address indexed user, uint256 amount, string escrowName);
    event Withdrawn(address indexed user, uint256 amount, uint256 remainingBalance, string escrowName);
    event PenaltyApplied(address indexed cp, uint256 amount, uint256 newBalance, string reason);
    event SlashApplied(address indexed cp, uint256 newBalance, string reason);
    event RewardApplied(address indexed cp, uint256 amount, uint256 newBalance, string reason);

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        token = new LuminoToken();
        token.initialize();
        accessManager = new AccessManager();
        accessManager.initialize();
        nodeEscrow = new NodeEscrow();
        nodeEscrow.initialize(address(accessManager), address(token));

        // Setup roles
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        accessManager.grantRole(LShared.CONTRACTS_ROLE, contractRole);

        // Fund CPs and escrow contract with tokens
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);
        // Fund escrow contract for rewards
        token.transfer(address(nodeEscrow), INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(cp1);
        
        uint256 depositAmount = 1 ether;
        token.approve(address(nodeEscrow), depositAmount);

        // Test event emission
        vm.expectEmit(true, false, false, true);
        emit Deposited(cp1, depositAmount, depositAmount, "stake");
        
        // Make deposit
        nodeEscrow.deposit(depositAmount);
        
        // Verify balance
        assertEq(nodeEscrow.getBalance(cp1), depositAmount);
        
        vm.stopPrank();
    }

    function testBelowMinimumDeposit() public {
        vm.startPrank(cp1);
        
        uint256 smallDeposit = MIN_DEPOSIT - 1;
        token.approve(address(nodeEscrow), smallDeposit);
        
        // Attempt deposit below minimum
        vm.expectRevert(abi.encodeWithSignature("BelowMinimumDeposit(uint256,uint256)", smallDeposit, MIN_DEPOSIT));
        nodeEscrow.deposit(smallDeposit);
        
        vm.stopPrank();
    }

    function testWithdrawRequest() public {
        // First make a deposit
        vm.startPrank(cp1);
        uint256 depositAmount = 1 ether;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        
        // Test event emission for withdraw request
        vm.expectEmit(true, false, false, true);
        emit WithdrawRequested(cp1, depositAmount, block.timestamp + 1 days, "stake");
        
        // Request withdrawal
        nodeEscrow.requestWithdraw(depositAmount);
        
        vm.stopPrank();
    }

    function testApplyPenalty() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2; // Ensure enough balance for penalty
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        string memory reason = "Missed assignment round";
        
        // Apply penalty from contract role
        vm.startPrank(contractRole);
        
        // Test event emission for penalty
        vm.expectEmit(true, false, false, true);
        emit PenaltyApplied(cp1, PENALTY_AMOUNT, depositAmount - PENALTY_AMOUNT, reason);
        
        nodeEscrow.applyPenalty(cp1, PENALTY_AMOUNT, reason);
        
        // Verify reduced balance
        assertEq(nodeEscrow.getBalance(cp1), depositAmount - PENALTY_AMOUNT);
        
        vm.stopPrank();
    }

    function testApplySlash() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        string memory reason = "Exceeded maximum penalties";
        
        // Apply slash from contract role
        vm.startPrank(contractRole);
        
        // Test event emission for slash
        vm.expectEmit(true, false, false, true);
        emit SlashApplied(cp1, 0, reason);
        
        nodeEscrow.applySlash(cp1, reason);
        
        // Verify balance is zeroed
        assertEq(nodeEscrow.getBalance(cp1), 0);
        
        vm.stopPrank();
    }

    function testApplyReward() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        string memory reason = "Secret revelation reward";
        
        // Apply reward from contract role
        vm.startPrank(contractRole);
        
        // Test event emission for reward
        vm.expectEmit(true, false, false, true);
        emit RewardApplied(cp1, REWARD_AMOUNT, depositAmount + REWARD_AMOUNT, reason);
        
        nodeEscrow.applyReward(cp1, REWARD_AMOUNT, reason);
        
        // Verify increased balance
        assertEq(nodeEscrow.getBalance(cp1), depositAmount + REWARD_AMOUNT);
        
        vm.stopPrank();
    }

    function testPenaltyExceedingBalance() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 4; // Small deposit
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Try to apply penalty larger than balance
        vm.startPrank(contractRole);
        uint256 penaltyAmount = depositAmount * 2; // Penalty larger than deposit
        
        // Apply penalty - should reduce to available balance
        nodeEscrow.applyPenalty(cp1, penaltyAmount, "Large penalty");
        
        // Balance should be 0, not negative
        assertEq(nodeEscrow.getBalance(cp1), 0);
        
        vm.stopPrank();
    }

    function testUnauthorizedPenalty() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Try to apply penalty from unauthorized address
        vm.startPrank(cp2);
        
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", cp2));
        nodeEscrow.applyPenalty(cp1, PENALTY_AMOUNT, "Unauthorized penalty");
        
        vm.stopPrank();
    }

    function testUnauthorizedSlash() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Try to apply slash from unauthorized address
        vm.startPrank(cp2);
        
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", cp2));
        nodeEscrow.applySlash(cp1, "Unauthorized slash");
        
        vm.stopPrank();
    }

    function testUnauthorizedReward() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Try to apply reward from unauthorized address
        vm.startPrank(cp2);
        
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", cp2));
        nodeEscrow.applyReward(cp1, REWARD_AMOUNT, "Unauthorized reward");
        
        vm.stopPrank();
    }

    function testCombinedRewardsPenalties() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(contractRole);
        
        // Apply rewards and penalties in sequence
        nodeEscrow.applyReward(cp1, REWARD_AMOUNT, "First reward");
        uint256 balanceAfterReward = nodeEscrow.getBalance(cp1);
        assertEq(balanceAfterReward, depositAmount + REWARD_AMOUNT);
        
        nodeEscrow.applyPenalty(cp1, PENALTY_AMOUNT, "First penalty");
        uint256 balanceAfterPenalty = nodeEscrow.getBalance(cp1);
        assertEq(balanceAfterPenalty, balanceAfterReward - PENALTY_AMOUNT);
        
        // Apply slash to zero the balance
        nodeEscrow.applySlash(cp1, "Final slash");
        assertEq(nodeEscrow.getBalance(cp1), 0);
        
        vm.stopPrank();
    }

    function testWithdrawAfterRewardsAndPenalties() public {
        // Setup: deposit
        vm.startPrank(cp1);
        uint256 depositAmount = INITIAL_BALANCE / 2;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);

        // Switch to contract role for rewards/penalties
        vm.stopPrank();
        vm.startPrank(contractRole);
        nodeEscrow.applyReward(cp1, REWARD_AMOUNT, "Test reward");
        nodeEscrow.applyPenalty(cp1, PENALTY_AMOUNT, "Test penalty");
        vm.stopPrank();

        // Calculate expected final balance
        uint256 expectedBalance = depositAmount + REWARD_AMOUNT - PENALTY_AMOUNT;
        assertEq(nodeEscrow.getBalance(cp1), expectedBalance);

        // Request withdrawal
        vm.startPrank(cp1);
        nodeEscrow.requestWithdraw(expectedBalance);
        
        // Move time forward past lock period
        vm.warp(block.timestamp + 1 days + 1);
        
        // Withdraw funds
        nodeEscrow.withdraw();
        
        // Verify final state
        assertEq(nodeEscrow.getBalance(cp1), 0);
        vm.stopPrank();
    }
}