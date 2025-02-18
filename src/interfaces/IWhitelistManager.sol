// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWhitelistManager {
    // Events
    event CPAdded(address indexed cp, uint256 timestamp);
    event CPRemoved(address indexed cp, uint256 timestamp);

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