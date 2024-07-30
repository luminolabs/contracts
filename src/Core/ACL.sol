// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title ACL (Access Control List)
 * @dev Implements role-based access control for the Lumino Staking System.
 * This contract manages permissions and roles within the system.
 */
contract ACL is AccessControl {
    /**
     * @dev Constructor that sets up the initial admin role.
     * The deployer of the contract is granted the DEFAULT_ADMIN_ROLE,
     * allowing them to manage other roles in the system.
     */
    constructor() {
        // Grant the contract deployer the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Additional role definitions and role management functions can be added here
}