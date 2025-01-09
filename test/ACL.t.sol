// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/ACL.sol";

contract ACLTest is Test {
    ACL public acl;
    address public admin;
    address public user1;
    address public user2;

    // Example role for testing
    bytes32 public constant TEST_ROLE = keccak256("TEST_ROLE");

    function setUp() public {
        admin = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        acl = new ACL();
    }

    function testInitialize() public {
        acl.initialize(admin);
        
        // Verify admin has DEFAULT_ADMIN_ROLE
        assertTrue(acl.hasRole(acl.DEFAULT_ADMIN_ROLE(), admin));
        
        // Verify initialization can't be called twice
        bytes memory expectedRevertMessage = abi.encodeWithSignature(
            "InvalidInitialization()"
        );
        vm.expectRevert(expectedRevertMessage);
        acl.initialize(user1);
    }

    function testRoleManagement() public {
        acl.initialize(admin);

        // Grant role
        acl.grantRole(TEST_ROLE, user1);
        assertTrue(acl.hasRole(TEST_ROLE, user1));

        // Revoke role
        acl.revokeRole(TEST_ROLE, user1);
        assertFalse(acl.hasRole(TEST_ROLE, user1));

        // Test role admin
        assertTrue(acl.getRoleAdmin(TEST_ROLE) == acl.DEFAULT_ADMIN_ROLE());
    }

    function testUnauthorizedAccess() public {
        acl.initialize(admin);

        // Try to grant role from non-admin account
        vm.startPrank(user1);
        
        bytes memory expectedRevertMessage = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            user1,
            acl.DEFAULT_ADMIN_ROLE()
        );
        vm.expectRevert(expectedRevertMessage);
        acl.grantRole(TEST_ROLE, user2);

        // Try to revoke role from non-admin account
        vm.expectRevert(expectedRevertMessage);
        acl.revokeRole(TEST_ROLE, user2);
        
        vm.stopPrank();
    }

    function testRenounceRole() public {
        acl.initialize(admin);
        
        // Grant role to user1
        acl.grantRole(TEST_ROLE, user1);
        assertTrue(acl.hasRole(TEST_ROLE, user1));

        // User1 renounces their role
        vm.prank(user1);
        acl.renounceRole(TEST_ROLE, user1);
        assertFalse(acl.hasRole(TEST_ROLE, user1));

        // Try to renounce role for another account (should fail)
        vm.prank(user1);
        bytes memory expectedRevertMessage = abi.encodeWithSignature(
            "AccessControlBadConfirmation()"
        );
        vm.expectRevert(expectedRevertMessage);
        acl.renounceRole(TEST_ROLE, user2);
    }
}