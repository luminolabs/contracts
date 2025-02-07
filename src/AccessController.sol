// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IAccessController.sol";
import "./interfaces/IRoleManager.sol";
import "./interfaces/IWhitelistManager.sol";

/**
 * @title AccessController
 * @notice Manages access control and authorization across the system
 * @dev This contract serves as the central access control mechanism, working in conjunction
 * with RoleManager and WhitelistManager to enforce permissions throughout the protocol
 */
contract AccessController is IAccessController {
    /// @notice Reference to the role management contract
    IRoleManager public immutable roleManager;

    /// @notice Reference to the whitelist management contract
    IWhitelistManager public immutable whitelistManager;

    /// @notice Core system role for administrative access
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Core system role for operator access
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Core system role for contract-to-contract access
    bytes32 public constant CONTRACTS_ROLE = keccak256("CONTRACTS_ROLE");

    /// @notice Thrown when an account attempts an action without proper authorization
    error UnauthorizedAccess(address account, bytes32 role);

    /// @notice Thrown when an account lacks necessary permissions
    error AccountNotAuthorized(address account);

    /// @notice Thrown when an account is missing a required role
    error MissingRequiredRole(address account, bytes32 role);

    /**
     * @notice Initializes the AccessController with required dependencies
     * @param _roleManager Address of the RoleManager contract
     * @param _whitelistManager Address of the WhitelistManager contract
     */
    constructor(address _roleManager, address _whitelistManager) {
        roleManager = IRoleManager(_roleManager);
        whitelistManager = IWhitelistManager(_whitelistManager);
    }

    /**
     * @notice Checks if an account has the required role
     * @dev Admins implicitly have access to all roles
     * @param account Address to check
     * @param role Role to verify
     * @return bool True if account has role or is an admin
     */
    function isAuthorized(
        address account,
        bytes32 role
    ) public view override returns (bool) {
        // Admin role has access to everything
        if (roleManager.hasRole(ADMIN_ROLE, account)) {
            return true;
        }

        // Check specific role
        return roleManager.hasRole(role, account);
    }

    /**
     * @notice Verifies an account has the required role
     * @dev Reverts with UnauthorizedAccess if verification fails
     * @param role Role to check
     * @param account Address to verify
     */
    function checkRole(bytes32 role, address account) external view override {
        if (!isAuthorized(account, role)) {
            revert UnauthorizedAccess(account, role);
        }
    }

    /**
     * @notice Requires msg.sender to have specified role
     * @dev Reverts with MissingRequiredRole if requirement not met
     * @param role Role required
     */
    function requireRole(bytes32 role) external view override {
        if (!isAuthorized(msg.sender, role)) {
            revert MissingRequiredRole(msg.sender, role);
        }
    }

    /**
     * @notice Checks if account has any of the core system roles
     * @param account Address to check
     * @return bool True if account has any role
     */
    function hasAnyRole(address account) external view returns (bool) {
        return roleManager.hasRole(ADMIN_ROLE, account) ||
        roleManager.hasRole(OPERATOR_ROLE, account) ||
            roleManager.hasRole(CONTRACTS_ROLE, account);
    }

    /**
     * @notice Helper to check contract access
     * @dev Verifies if a contract address has the CONTRACTS_ROLE
     * @param contractAddress Address of contract to verify
     */
    function requireContractRole(address contractAddress) external view {
        if (!roleManager.hasRole(CONTRACTS_ROLE, contractAddress)) {
            revert UnauthorizedAccess(contractAddress, CONTRACTS_ROLE);
        }
    }
}