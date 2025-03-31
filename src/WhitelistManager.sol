// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IAccessManager} from "./interfaces/IAccessManager.sol";
import {IWhitelistManager} from "./interfaces/IWhitelistManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract WhitelistManager is Initializable, IWhitelistManager {
    // Contracts
    IAccessManager private accessManager;

    // State variables
    mapping(address => CPInfo) private cpInfo;
    address[] private whitelistedCPs;
    mapping(address => uint256) private cpIndex;

    /**
     * @notice Initializes the WhitelistManager contract
     */
    function initialize(address _accessManager) external initializer {
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
     * @notice Add multiple computing providers to the whitelist
     * @param cps Array of CP addresses to whitelist
     */
    function addCPBatch(address[] calldata cps) external {
        accessManager.requireRole(LShared.OPERATOR_ROLE, msg.sender);
        
        for (uint256 i = 0; i < cps.length; i++) {
            address cp = cps[i];
            
            // Skip addresses that are already whitelisted
            if (cpInfo[cp].isWhitelisted) continue;
            
            // Check cooldown if previously removed
            if (cpInfo[cp].lastStatusUpdate != 0) {
                uint256 timeElapsed = block.timestamp - cpInfo[cp].lastStatusUpdate;
                if (timeElapsed < LShared.WHITELIST_COOLDOWN) {
                    // Skip addresses that are in cooldown
                    continue;
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
     * @notice Remove multiple computing providers from the whitelist
     * @param cps Array of CP addresses to remove from whitelist
     */
    function removeCPBatch(address[] calldata cps) external {
        accessManager.requireRole(LShared.OPERATOR_ROLE, msg.sender);
        
        for (uint256 i = 0; i < cps.length; i++) {
            address cp = cps[i];
            
            // Skip addresses that aren't whitelisted
            if (!cpInfo[cp].isWhitelisted) continue;
            
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
    }

    /**
     * @notice Requires a computing provider is currently whitelisted
     */
    function requireWhitelisted(address cp) external view {
        if (!cpInfo[cp].isWhitelisted) {
            revert NotWhitelisted(cp);
        }
    }
    
    /**
     * @notice Get all currently whitelisted CPs
     * @return Array of all whitelisted CP addresses
     */
    function getAllWhitelistedCPs() external view returns (address[] memory) {
        return whitelistedCPs;
    }
}