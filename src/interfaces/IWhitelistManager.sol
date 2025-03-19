// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWhitelistManager {
    // Events
    event CPAdded(address indexed cp, uint256 timestamp);
    event CPRemoved(address indexed cp, uint256 timestamp);

    // Errors
    error AlreadyWhitelisted(address cp);
    error CooldownActive(address cp, uint256 remainingTime);
    error NotWhitelisted(address cp);

    // Structs
    struct CPInfo {
        bool isWhitelisted;
        uint256 whitelistedAt;
        uint256 lastStatusUpdate;
    }

    // Whitelist management functions
    function addCP(address cp) external;
    function removeCP(address cp) external;
    function requireWhitelisted(address cp) external view;
}