// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {LShared} from "./libraries/LShared.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract AccessManager is Initializable, IAccessManager {
    // State variables
    mapping(bytes32 => RoleData) private roles;
    mapping(address => mapping(bytes32 => bool)) private userRoles;

    /**
     * @notice Initializes the AccessManager contract
     */
    function initialize() external initializer {
        _grantRole(LShared.ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Grants a role to an account
     */
    function grantRole(bytes32 role, address account) external override {
        requireRole(LShared.ADMIN_ROLE, msg.sender);
        if (role != LShared.ADMIN_ROLE && role != LShared.OPERATOR_ROLE && role != LShared.CONTRACTS_ROLE) {
            revert InvalidRole(role);
        }

        _grantRole(role, account);
    }

    /**
     * @notice Revokes a role from an account
     */
    function revokeRole(bytes32 role, address account) external override {
        requireRole(LShared.ADMIN_ROLE, msg.sender);
        if (role == LShared.ADMIN_ROLE && roles[LShared.ADMIN_ROLE].memberCount == 1) {
            revert CannotRevokeAdmin();
        }

        _revokeRole(role, account);
    }

    /**
     * @notice Checks if an account has a specific role
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return roles[role].members[account];
    }

    /**
     * @notice Requires that an account has a specific role
     */
    function requireRole(bytes32 role, address account) public view override {
        if (!hasRole(LShared.ADMIN_ROLE, account) && !hasRole(role, account)) {
            revert RoleManagerUnauthorized(account);
        }
    }

    function getRoleAdmin(bytes32 role) external pure returns (bytes32) {
        if (role == LShared.ADMIN_ROLE) {
            return LShared.ADMIN_ROLE;
        } else if (role == LShared.OPERATOR_ROLE) {
            return LShared.ADMIN_ROLE;
        } else if (role == LShared.CONTRACTS_ROLE) {
            return LShared.ADMIN_ROLE;
        } else {
            revert InvalidRole(role);
        }
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        if (callerConfirmation != msg.sender) {
            revert MustConfirmRenounce(msg.sender);
        }
        _revokeRole(role, msg.sender);
    }

    // Internal functions

    function _grantRole(bytes32 role, address account) private {
        if (!roles[role].members[account]) {
            roles[role].members[account] = true;
            roles[role].memberCount++;
            userRoles[account][role] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (roles[role].members[account]) {
            roles[role].members[account] = false;
            roles[role].memberCount--;
            userRoles[account][role] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}