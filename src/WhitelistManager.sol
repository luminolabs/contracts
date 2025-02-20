// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IWhitelistManager} from "./interfaces/IWhitelistManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract WhitelistManager is IWhitelistManager {
    // Contracts
    IAccessManager private immutable accessManager;

    // State variables
    mapping(address => CPInfo) private cpInfo;
    address[] private whitelistedCPs;
    mapping(address => uint256) private cpIndex;

    // Errors
    error AlreadyWhitelisted(address cp);
    error CooldownActive(address cp, uint256 remainingTime);
    error NotWhitelisted(address cp);

    constructor(address _accessManager) {
        accessManager = IAccessManager(_accessManager);
    }

    /**
     * @notice Add a computing provider to the whitelist
     */
    function addCP(address cp) external {
        accessManager.requireRole(LShared.OPERATOR_ROLE, msg.sender);
        if (cpInfo[cp].isWhitelisted) revert AlreadyWhitelisted(cp);

        // Check cooldown if previously removed
        if (cpInfo[cp].lastStatusUpdate != 0) {
            uint256 timeElapsed = block.timestamp - cpInfo[cp].lastStatusUpdate;
            if (timeElapsed < LShared.WHITELIST_COOLDOWN) {
                revert CooldownActive(cp, LShared.WHITELIST_COOLDOWN - timeElapsed);
            }
        }

        // Update CP info
        cpInfo[cp] = CPInfo({
            isWhitelisted: true,
            whitelistedAt: block.timestamp,
            lastStatusUpdate: block.timestamp
        });

        // Add to whitelist array
        whitelistedCPs.push(cp);
        cpIndex[cp] = whitelistedCPs.length - 1;

        emit CPAdded(cp, block.timestamp);
    }

    /**
     * @notice Remove a computing provider from the whitelist
     */
    function removeCP(address cp) external {
        accessManager.requireRole(LShared.OPERATOR_ROLE, msg.sender);
        if (!cpInfo[cp].isWhitelisted) revert NotWhitelisted(cp);

        // Update CP info
        cpInfo[cp].isWhitelisted = false;
        cpInfo[cp].lastStatusUpdate = block.timestamp;

        // Remove from whitelist array using swap and pop
        uint256 index = cpIndex[cp];
        address lastCP = whitelistedCPs[whitelistedCPs.length - 1];

        whitelistedCPs[index] = lastCP;
        cpIndex[lastCP] = index;
        whitelistedCPs.pop();
        delete cpIndex[cp];

        emit CPRemoved(cp, block.timestamp);
    }

    /**
     * @notice Requires a computing provider is currently whitelisted
     */
    function requireWhitelisted(address cp) external view {
        if (!cpInfo[cp].isWhitelisted) {
            revert NotWhitelisted(cp);
        }
    }
}