// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "./interfaces/IRoleManager.sol";
import "./interfaces/IAccessController.sol";

/**
 * @title RoleManager
 * @dev Manages role-based access control (RBAC) for the system.
 * This contract handles role assignments, revocations, and role checks
 * for three core system roles: ADMIN_ROLE, OPERATOR_ROLE, and CONTRACTS_ROLE.
 *
 * Key features:
 * - Admins implicitly have all other roles
 * - Roles can only be granted/revoked by admins
 * - System can be paused/unpaused by admins
 * - Users can renounce their own roles
 * - Prevents removal of last admin
 *
 * The contract inherits from OpenZeppelin's Pausable contract to enable
 * emergency pause functionality.
 */
contract RoleManager is IRoleManager, Pausable {
    // Core role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONTRACTS_ROLE = keccak256("CONTRACTS_ROLE");

    // Role storage
    mapping(bytes32 => RoleData) private roles;
    mapping(address => mapping(bytes32 => bool)) private userRoles;

    /**
     * @dev Structure to track role membership and count
     * @param members Mapping of addresses to their role membership status
     * @param memberCount Total number of addresses with this role
     */
    struct RoleData {
        mapping(address => bool) members;
        uint256 memberCount;
    }

    // Custom errors
    error RoleManagerUnauthorized(address account);
    error InvalidRole(bytes32 role);
    error InvalidAddress(address account);
    error CannotRevokeAdmin();

    // Events
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @dev Modifier to restrict function access to admin role holders
     */
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            revert RoleManagerUnauthorized(msg.sender);
        }
        _;
    }

    /**
     * @dev Constructor sets up initial admin role
     * The deploying address is automatically granted admin role
     */
    constructor() {
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Checks if an account has a specific role
     * Admin role holders implicitly have all other roles
     * @param role The role identifier to check
     * @param account The address to check the role for
     * @return bool True if the account has the role or is an admin
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        if (role == ADMIN_ROLE) {
            return roles[ADMIN_ROLE].members[account];
        }
        // Admins implicitly have all roles
        return roles[ADMIN_ROLE].members[account] || roles[role].members[account];
    }

    /**
     * @dev Grants a role to an account. Only callable by admins when not paused.
     * @param role The role to grant (must be one of the core system roles)
     * @param account The address to grant the role to (must not be zero address)
     */
    function grantRole(bytes32 role, address account) external override onlyAdmin whenNotPaused {
        if (account == address(0)) revert InvalidAddress(account);
        if (role != ADMIN_ROLE && role != OPERATOR_ROLE && role != CONTRACTS_ROLE) {
            revert InvalidRole(role);
        }

        _grantRole(role, account);
    }

    /**
     * @dev Revokes a role from an account. Only callable by admins when not paused.
     * Cannot revoke the last admin role to ensure system operability.
     * @param role The role to revoke
     * @param account The address to revoke the role from
     */
    function revokeRole(bytes32 role, address account) external override onlyAdmin whenNotPaused {
        if (role == ADMIN_ROLE && roles[ADMIN_ROLE].memberCount == 1) {
            revert CannotRevokeAdmin();
        }

        _revokeRole(role, account);
    }

    /**
     * @dev Returns the admin role that controls `role`.
     * In this implementation, ADMIN_ROLE manages all other roles.
     * @param role The role to query (unused in this implementation)
     * @return bytes32 Always returns ADMIN_ROLE
     */
    function getRoleAdmin(bytes32) external pure override returns (bytes32) {
        return ADMIN_ROLE;
    }

    /**
     * @dev Setting role admin is not supported in this implementation
     * @param role The role to set admin for
     * @param adminRole The new admin role
     */
    function setRoleAdmin(bytes32, bytes32) external pure override {
        revert("RoleManager: Operation not supported");
    }

    /**
     * @dev Returns the number of members that have `role`
     * @param role The role to query
     * @return uint256 The number of accounts that have this role
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return roles[role].memberCount;
    }

    /**
     * @dev Allows users to renounce their own roles.
     * Cannot renounce admin role if last admin.
     */
    function renounceRole(bytes32 role) external whenNotPaused {
        if (role == ADMIN_ROLE && roles[ADMIN_ROLE].memberCount == 1) {
            revert CannotRevokeAdmin();
        }
        _revokeRole(role, msg.sender);
    }

    /**
     * @dev Internal function to set up a new role assignment
     * @param role The role to assign
     * @param account The account to receive the role
     */
    function _setupRole(bytes32 role, address account) private {
        roles[role].members[account] = true;
        roles[role].memberCount++;
        userRoles[account][role] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    /**
     * @dev Internal function to grant a role
     * @param role The role to grant
     * @param account The account to receive the role
     */
    function _grantRole(bytes32 role, address account) private {
        if (!roles[role].members[account]) {
            roles[role].members[account] = true;
            roles[role].memberCount++;
            userRoles[account][role] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /**
     * @dev Internal function to revoke a role
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function _revokeRole(bytes32 role, address account) private {
        if (roles[role].members[account]) {
            roles[role].members[account] = false;
            roles[role].memberCount--;
            userRoles[account][role] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    /**
     * @dev Pauses all role management operations.
     * Only callable by admin.
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @dev Unpauses role management operations.
     * Only callable by admin.
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
}