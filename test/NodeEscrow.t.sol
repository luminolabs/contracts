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

    // Events to test
    event Deposited(address indexed user, uint256 amount, uint256 newBalance, string escrowName);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 unlockTime, string escrowName);
    event WithdrawCancelled(address indexed user, uint256 amount, string escrowName);
    event Withdrawn(address indexed user, uint256 amount, uint256 remainingBalance, string escrowName);
    event PenaltyApplied(address indexed cp, uint256 amount, uint256 newBalance);

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        token = new LuminoToken();
        accessManager = new AccessManager();
        nodeEscrow = new NodeEscrow(address(accessManager), address(token));

        // Setup roles
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        accessManager.grantRole(LShared.CONTRACTS_ROLE, contractRole);

        // Fund CPs with tokens
        token.transfer(cp1, INITIAL_BALANCE);
        token.transfer(cp2, INITIAL_BALANCE);

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

    function testCancelWithdraw() public {
        // Setup: deposit and request withdrawal
        vm.startPrank(cp1);
        uint256 amount = 1 ether;
        token.approve(address(nodeEscrow), amount);
        nodeEscrow.deposit(amount);
        nodeEscrow.requestWithdraw(amount);
        
        // Test event emission for cancellation
        vm.expectEmit(true, false, false, true);
        emit WithdrawCancelled(cp1, amount, "stake");
        
        // Cancel withdrawal
        nodeEscrow.cancelWithdraw();
        
        vm.stopPrank();
    }

    function testWithdraw() public {
        // Setup: deposit and request withdrawal
        vm.startPrank(cp1);
        uint256 amount = 1 ether;
        token.approve(address(nodeEscrow), amount);
        vm.stopPrank();
        
        // Record initial balances
        uint256 initialCp1Balance = token.balanceOf(cp1);
        uint256 initialContractBalance = token.balanceOf(address(nodeEscrow));

        console.log("Initial CP balance : ", initialCp1Balance);
        console.log("Initial contract balance : ", initialContractBalance);

        vm.startPrank(cp1);
        
        // Make deposit
        nodeEscrow.deposit(amount);
        
        // Verify post-deposit state
        assertEq(nodeEscrow.getBalance(cp1), amount);
        assertEq(token.balanceOf(cp1), initialCp1Balance - amount);
        assertEq(token.balanceOf(address(nodeEscrow)), initialContractBalance + amount);
        console.log("token balance of contract : ", token.balanceOf(address(nodeEscrow)));
        
        // Request withdrawal
        nodeEscrow.requestWithdraw(amount);
        
        // Move time forward past lock period
        vm.warp(block.timestamp + 1 days + 1);
        
        // Execute withdrawal
        nodeEscrow.withdraw();
        
        // Verify final state
        assertEq(nodeEscrow.getBalance(cp1), 0);
        assertEq(token.balanceOf(cp1), initialCp1Balance); // Should be back to initial balance
        assertEq(token.balanceOf(address(nodeEscrow)), initialContractBalance); // Should be back to initial balance
        
        vm.stopPrank();
    }

    function testWithdrawBeforeLockPeriod() public {
        // Setup: deposit and request withdrawal
        vm.startPrank(cp1);
        uint256 amount = 1 ether;
        token.approve(address(nodeEscrow), amount);
        nodeEscrow.deposit(amount);
        nodeEscrow.requestWithdraw(amount);
        
        // Attempt withdrawal before lock period ends
        vm.expectRevert(abi.encodeWithSignature("LockPeriodActive(address,uint256)", cp1, 1 days));
        nodeEscrow.withdraw();
        
        vm.stopPrank();
    }

    function testApplyPenalty() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = 1 ether;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Apply penalty from contract role
        vm.startPrank(contractRole);
        uint256 penaltyAmount = 0.5 ether;
        
        // Test event emission for penalty
        vm.expectEmit(true, false, false, true);
        emit PenaltyApplied(cp1, penaltyAmount, depositAmount - penaltyAmount);
        
        nodeEscrow.applyPenalty(cp1, penaltyAmount);
        
        // Verify reduced balance
        assertEq(nodeEscrow.getBalance(cp1), depositAmount - penaltyAmount);
        
        vm.stopPrank();
    }

    function testPenaltyExceedingBalance() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = 1 ether;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Try to apply penalty larger than balance
        vm.startPrank(contractRole);
        uint256 penaltyAmount = 2 ether;
        
        vm.expectRevert(abi.encodeWithSignature(
            "InsufficientBalance(address,uint256,uint256)",
            cp1,
            penaltyAmount,
            depositAmount
        ));
        nodeEscrow.applyPenalty(cp1, penaltyAmount);
        
        vm.stopPrank();
    }

    function testUnauthorizedPenalty() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = 1 ether;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Try to apply penalty from unauthorized address
        vm.startPrank(cp2);
        uint256 penaltyAmount = 0.5 ether;
        
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", cp2));
        nodeEscrow.applyPenalty(cp1, penaltyAmount);
        
        vm.stopPrank();
    }

    function testMultipleDepositsAndWithdraws() public {
        // First, ensure cp1 has approved enough tokens
        vm.startPrank(cp1);
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 2 ether;
        token.approve(address(nodeEscrow), deposit1 + deposit2);
        vm.stopPrank();

        // Record initial balances
        uint256 initialCp1Balance = token.balanceOf(cp1);
        uint256 initialContractBalance = token.balanceOf(address(nodeEscrow));

        vm.startPrank(cp1);
        
        // Make multiple deposits
        nodeEscrow.deposit(deposit1);
        nodeEscrow.deposit(deposit2);
        
        // Verify total escrow balance
        assertEq(nodeEscrow.getBalance(cp1), deposit1 + deposit2);
        
        // Verify token transfers occurred correctly
        assertEq(token.balanceOf(cp1), initialCp1Balance - (deposit1 + deposit2));
        assertEq(token.balanceOf(address(nodeEscrow)), initialContractBalance + deposit1 + deposit2);
        
        // Request partial withdrawal
        uint256 withdrawAmount = 1.5 ether;
        nodeEscrow.requestWithdraw(withdrawAmount);
        
        // Move time forward
        vm.warp(block.timestamp + 1 days + 1);
        
        // Execute withdrawal
        nodeEscrow.withdraw();
        
        // Verify remaining balances
        assertEq(nodeEscrow.getBalance(cp1), deposit1 + deposit2 - withdrawAmount);
        assertEq(token.balanceOf(cp1), initialCp1Balance - (deposit1 + deposit2) + withdrawAmount);
        assertEq(token.balanceOf(address(nodeEscrow)), initialContractBalance + deposit1 + deposit2 - withdrawAmount);
        
        vm.stopPrank();
    }

    function testRequireBalance() public {
        // Setup: deposit some tokens
        vm.startPrank(cp1);
        uint256 depositAmount = 1 ether;
        token.approve(address(nodeEscrow), depositAmount);
        nodeEscrow.deposit(depositAmount);
        vm.stopPrank();
        
        // Test successful balance requirement
        nodeEscrow.requireBalance(cp1, depositAmount);
        
        // Test failed balance requirement
        vm.expectRevert(abi.encodeWithSignature(
            "InsufficientBalance(address,uint256,uint256)",
            cp1,
            depositAmount + 1,
            depositAmount
        ));
        nodeEscrow.requireBalance(cp1, depositAmount + 1);
    }
}