// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/AccessManager.sol";
import "../src/libraries/LShared.sol";

contract AccessManagerTest is Test {
    AccessManager public accessManager;
    
    // Test addresses
    address public admin = address(1);
    address public operator = address(2);
    address public contractAddr = address(3);
    address public unauthorized = address(4);
    
    // Events to test
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function setUp() public {
        vm.startPrank(admin);
        accessManager = new AccessManager();
        vm.stopPrank();
    }

    function testInitialState() public view {
        // Admin role should be granted to deployer
        assertTrue(accessManager.hasRole(LShared.ADMIN_ROLE, admin));
        
        // Other roles should not be granted
        assertFalse(accessManager.hasRole(LShared.OPERATOR_ROLE, admin));
        assertFalse(accessManager.hasRole(LShared.CONTRACTS_ROLE, admin));
    }

    function testGrantRole() public {
        vm.startPrank(admin);
        
        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(LShared.OPERATOR_ROLE, operator, admin);
        
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        
        // Verify role was granted
        assertTrue(accessManager.hasRole(LShared.OPERATOR_ROLE, operator));
        
        vm.stopPrank();
    }

    function testGrantRoleOnlyAdmin() public {
        // Test that non-admins cannot grant roles
        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", unauthorized));
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();
    }

    function testGrantInvalidRole() public {
        vm.startPrank(admin);
        bytes32 invalidRole = keccak256("INVALID_ROLE");
        vm.expectRevert(abi.encodeWithSignature("InvalidRole(bytes32)", invalidRole));
        accessManager.grantRole(invalidRole, operator);
        vm.stopPrank();
    }

    function testRevokeRole() public {
        vm.startPrank(admin);
        
        // First grant a role
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        
        // Test event emission for revocation
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(LShared.OPERATOR_ROLE, operator, admin);
        
        accessManager.revokeRole(LShared.OPERATOR_ROLE, operator);
        
        // Verify role was revoked
        assertFalse(accessManager.hasRole(LShared.OPERATOR_ROLE, operator));
        
        vm.stopPrank();
    }

    function testRevokeRoleOnlyAdmin() public {
        vm.startPrank(admin);
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();

        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", unauthorized));
        accessManager.revokeRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();
    }

    function testCannotRevokeLastAdmin() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("CannotRevokeAdmin()"));
        accessManager.revokeRole(LShared.ADMIN_ROLE, admin);
        vm.stopPrank();
    }

    function testRevokeAdminWithMultipleAdmins() public {
        vm.startPrank(admin);
        
        // Add another admin
        address newAdmin = address(5);
        accessManager.grantRole(LShared.ADMIN_ROLE, newAdmin);
        
        // Now we can revoke the original admin
        accessManager.revokeRole(LShared.ADMIN_ROLE, admin);
        
        // Verify roles
        assertFalse(accessManager.hasRole(LShared.ADMIN_ROLE, admin));
        assertTrue(accessManager.hasRole(LShared.ADMIN_ROLE, newAdmin));
        
        vm.stopPrank();
    }

    function testRequireRole() public {
        vm.startPrank(admin);
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();

        // Should not revert for valid role
        accessManager.requireRole(LShared.OPERATOR_ROLE, operator);

        // Should revert for invalid role
        vm.expectRevert(abi.encodeWithSignature("RoleManagerUnauthorized(address)", unauthorized));
        accessManager.requireRole(LShared.OPERATOR_ROLE, unauthorized);
    }

    function testGetRoleAdmin() public {
        // All roles should return ADMIN_ROLE as their admin role
        assertEq(accessManager.getRoleAdmin(LShared.ADMIN_ROLE), LShared.ADMIN_ROLE);
        assertEq(accessManager.getRoleAdmin(LShared.OPERATOR_ROLE), LShared.ADMIN_ROLE);
        assertEq(accessManager.getRoleAdmin(LShared.CONTRACTS_ROLE), LShared.ADMIN_ROLE);

        // Invalid role should revert
        bytes32 invalidRole = keccak256("INVALID_ROLE");
        vm.expectRevert(abi.encodeWithSignature("InvalidRole(bytes32)", invalidRole));
        accessManager.getRoleAdmin(invalidRole);
    }

    function testRenounceRole() public {
        vm.startPrank(admin);
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();

        vm.startPrank(operator);
        // Test event emission
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(LShared.OPERATOR_ROLE, operator, operator);
        
        accessManager.renounceRole(LShared.OPERATOR_ROLE, operator);
        
        // Verify role was renounced
        assertFalse(accessManager.hasRole(LShared.OPERATOR_ROLE, operator));
        vm.stopPrank();
    }

    function testRenounceRoleInvalidCaller() public {
        vm.startPrank(admin);
        accessManager.grantRole(LShared.OPERATOR_ROLE, operator);
        vm.stopPrank();

        vm.startPrank(operator);
        // Should revert when trying to renounce for different address
        vm.expectRevert("Must confirm renounce");
        accessManager.renounceRole(LShared.OPERATOR_ROLE, admin);
        vm.stopPrank();
    }
}