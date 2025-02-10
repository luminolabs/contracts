// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessController} from "../interfaces/IAccessController.sol";
import {Roles} from "../libraries/Roles.sol";

/**
 * @title AccessControlled
 * @dev Abstract contract providing role-based access control functionality
 */
abstract contract AccessControlled {
    IAccessController public immutable accessController;

    // Custom errors
    error Unauthorized(address caller);

    constructor(address _accessController) {
        accessController = IAccessController(_accessController);
    }

    modifier onlyRole(bytes32 role) {
        if (!accessController.isAuthorized(msg.sender, role)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyAdmin() {
        if (!accessController.isAuthorized(msg.sender, Roles.ADMIN_ROLE)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyOperator() {
        if (!accessController.isAuthorized(msg.sender, Roles.OPERATOR_ROLE)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyContracts() {
        if (!accessController.isAuthorized(msg.sender, Roles.CONTRACTS_ROLE)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    modifier onlyOperatorOrContracts() {
        if (!accessController.isAuthorized(msg.sender, Roles.OPERATOR_ROLE) &&
        !accessController.isAuthorized(msg.sender, Roles.CONTRACTS_ROLE)) {
            revert Unauthorized(msg.sender);
        }
        _;
    }
}