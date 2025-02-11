// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IAccessController {
    function isAuthorized(address account, bytes32 role) external view returns (bool);
    function checkRole(bytes32 role, address account) external view;
    function requireRole(bytes32 role) external view;
}