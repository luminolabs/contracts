// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/WhitelistManager.sol";
import "../src/AccessManager.sol";
import "../src/libraries/LShared.sol";

contract WhitelistManagerTest is Test {
    WhitelistManager public whitelistManager;
    AccessManager public accessManager;
    
    // Test addresses
    address public admin = address(1);
    address public operator = address(2);
    address public computingProvider1 = address(3);
    address public computingProvider2 = address(4);
    
    // Events to test
    event CPAdded(address indexed cp, uint256 timestamp);
    event CPRemoved(address indexed cp, uint256 timestamp);

    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);
        accessManager = new AccessManager();
        accessManager.initialize();
        whitelistManager = new WhitelistManager();
        whitelistManager.initialize(address(accessManager));
        
        // Setup roles
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();
    }

    function testInitialState() public {
        // Verify initial state
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", computingProvider1));
        whitelistManager.requireWhitelisted(computingProvider1);
    }

    function testAddCP() public {
        vm.startPrank(operator);
        
        // Test event emission
        vm.expectEmit(true, false, false, true);
        emit CPAdded(computingProvider1, block.timestamp);
        
        whitelistManager.addCP(computingProvider1);
        
        // Verify CP is whitelisted
        whitelistManager.requireWhitelisted(computingProvider1);
        vm.stopPrank();
    }

    function testAddCPOnlyOperator() public {
        // Test that non-operators cannot add CPs
        vm.startPrank(computingProvider1);
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", computingProvider1));
        whitelistManager.addCP(computingProvider2);
        vm.stopPrank();
    }

    function testCannotAddWhitelistedCP() public {
        vm.startPrank(operator);
        
        // First addition should succeed
        whitelistManager.addCP(computingProvider1);
        
        // Second addition should fail
        vm.expectRevert(abi.encodeWithSignature("AlreadyWhitelisted(address)", computingProvider1));
        whitelistManager.addCP(computingProvider1);
        
        vm.stopPrank();
    }

    function testRemoveCP() public {
        vm.startPrank(operator);
        
        // First add a CP
        whitelistManager.addCP(computingProvider1);
        
        // Test event emission for removal
        vm.expectEmit(true, false, false, true);
        emit CPRemoved(computingProvider1, block.timestamp);
        
        whitelistManager.removeCP(computingProvider1);
        
        // Verify CP is no longer whitelisted
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", computingProvider1));
        whitelistManager.requireWhitelisted(computingProvider1);
        
        vm.stopPrank();
    }

    function testRemoveCPOnlyOperator() public {
        vm.startPrank(operator);
        whitelistManager.addCP(computingProvider1);
        vm.stopPrank();

        // Test that non-operators cannot remove CPs
        vm.startPrank(computingProvider2);
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", computingProvider2));
        whitelistManager.removeCP(computingProvider1);
        vm.stopPrank();
    }

    function testCannotRemoveNonWhitelistedCP() public {
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", computingProvider1));
        whitelistManager.removeCP(computingProvider1);
        vm.stopPrank();
    }

    function testWhitelistCooldown() public {
        vm.startPrank(operator);
        
        // Add and remove a CP
        whitelistManager.addCP(computingProvider1);
        whitelistManager.removeCP(computingProvider1);
        
        // Try to add again immediately
        vm.expectRevert(abi.encodeWithSignature(
            "CooldownActive(address,uint256)",
            computingProvider1,
            LShared.WHITELIST_COOLDOWN
        ));
        whitelistManager.addCP(computingProvider1);
        
        // Warp time forward past cooldown
        vm.warp(block.timestamp + LShared.WHITELIST_COOLDOWN + 1);
        
        // Should succeed now
        whitelistManager.addCP(computingProvider1);
        
        vm.stopPrank();
    }

    function testMultipleCPManagement() public {
        vm.startPrank(operator);
        
        // Add multiple CPs
        whitelistManager.addCP(computingProvider1);
        whitelistManager.addCP(computingProvider2);
        
        // Verify both are whitelisted
        whitelistManager.requireWhitelisted(computingProvider1);
        whitelistManager.requireWhitelisted(computingProvider2);
        
        // Remove one CP
        whitelistManager.removeCP(computingProvider1);
        
        // Verify states
        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", computingProvider1));
        whitelistManager.requireWhitelisted(computingProvider1);
        whitelistManager.requireWhitelisted(computingProvider2);
        
        vm.stopPrank();
    }
}