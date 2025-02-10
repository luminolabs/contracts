// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Roles {
    /// @notice Core system role for administrative access
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Core system role for operator access
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Core system role for contract-to-contract access
    bytes32 public constant CONTRACTS_ROLE = keccak256("CONTRACTS_ROLE");
}