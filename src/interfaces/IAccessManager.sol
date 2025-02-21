// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessControl} from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IAccessManager is IAccessControl {
    // Structs
    struct RoleData {
        mapping(address => bool) members;
        uint256 memberCount;
    }

    // Errors
    error RoleManagerUnauthorized(address account);
    error InvalidRole(bytes32 role);
    error CannotRevokeAdmin();
    error MustConfirmRenounce(address account);

    // Access management functions
    function requireRole(bytes32 role, address account) external view;
}