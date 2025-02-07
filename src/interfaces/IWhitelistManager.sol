// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWhitelistManager {
    event CPAdded(address indexed cp, uint256 timestamp);
    event CPRemoved(address indexed cp, uint256 timestamp);
    event CPStatusUpdated(address indexed cp, bool status);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    struct CPInfo {
        bool isWhitelisted;
        uint256 whitelistedAt;
        uint256 lastStatusUpdate;
    }

    function addCP(address cp) external;
    function removeCP(address cp) external;
    function isWhitelisted(address cp) external view returns (bool);
    function getCPInfo(address cp) external view returns (CPInfo memory);
    function getWhitelistedCPs() external view returns (address[] memory);
}