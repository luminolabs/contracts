// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "./interfaces/IWhitelistManager.sol";
import "./interfaces/IAccessController.sol";

/**
 * @title WhitelistManager
 * @dev Contract for managing a whitelist of computing providers (CPs) in the system.
 * Whitelisted CPs are allowed to participate in network operations like staking and running nodes.
 * The contract implements access control and pausable functionality for emergency situations.
 *
 * Key features:
 * - Add/remove CPs from whitelist with operator/admin privileges
 * - Track CP status and history
 * - Enforce cooldown periods between status changes
 * - Emergency pause functionality
 */
contract WhitelistManager is IWhitelistManager, Pausable {
    /// @dev Reference to the access control contract
    IAccessController public immutable accessController;

    /// @dev Mapping of CP addresses to their detailed information
    mapping(address => CPInfo) private cpInfo;

    /// @dev Array containing all currently whitelisted CP addresses
    address[] private whitelistedCPs;

    /// @dev Mapping of CP addresses to their index in the whitelistedCPs array
    mapping(address => uint256) private cpIndex;

    /// @dev Required waiting period (7 days) before a removed CP can be re-whitelisted
    uint256 public constant WHITELIST_COOLDOWN = 7 days;

    // Custom errors for more gas-efficient error handling
    /// @dev Thrown when attempting to use address(0)
    error ZeroAddress();
    /// @dev Thrown when trying to whitelist an already whitelisted CP
    error AlreadyWhitelisted(address cp);
    /// @dev Thrown when trying to operate on a non-whitelisted CP
    error NotWhitelisted(address cp);
    /// @dev Thrown when trying to re-whitelist a CP before cooldown period ends
    error CooldownActive(address cp, uint256 remainingTime);
    /// @dev Thrown when querying info for a CP that was never whitelisted
    error NeverWhitelisted(address cp);

    /**
     * @dev Contract constructor
     * @param _accessController Address of the AccessController contract
     */
    constructor(address _accessController) {
        accessController = IAccessController(_accessController);
    }

    /**
     * @dev Modifier that allows only OPERATOR_ROLE or ADMIN_ROLE to execute a function
     */
    modifier onlyOperator() {
        accessController.requireRole(keccak256("OPERATOR_ROLE"));
        _;
    }

    /**
     * @dev Modifier that allows only ADMIN_ROLE to execute a function
     */
    modifier onlyAdmin() {
        accessController.requireRole(keccak256("ADMIN_ROLE"));
        _;
    }

    /**
     * @dev Add a computing provider to the whitelist
     * @param cp Address of the computing provider to whitelist
     * @notice Only callable by operators when contract is not paused
     * @notice Enforces a cooldown period for previously removed CPs
     *
     * Requirements:
     * - CP address must not be zero
     * - CP must not already be whitelisted
     * - If previously removed, cooldown period must have elapsed
     *
     * Emits a {CPAdded} event
     */
    function addCP(address cp) external onlyOperator whenNotPaused {
        if (cp == address(0)) revert ZeroAddress();
        if (cpInfo[cp].isWhitelisted) revert AlreadyWhitelisted(cp);

        // Check cooldown if previously removed
        if (cpInfo[cp].lastStatusUpdate != 0) {
            uint256 timeElapsed = block.timestamp - cpInfo[cp].lastStatusUpdate;
            if (timeElapsed < WHITELIST_COOLDOWN) {
                revert CooldownActive(cp, WHITELIST_COOLDOWN - timeElapsed);
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
     * @dev Remove a computing provider from the whitelist
     * @param cp Address of the computing provider to remove
     * @notice Only callable by operators when contract is not paused
     *
     * Requirements:
     * - CP must be currently whitelisted
     *
     * Effects:
     * - CP is removed from whitelist
     * - Updates CP's status and timestamp
     * - Maintains O(1) removal from whitelistedCPs array
     *
     * Emits a {CPRemoved} event
     */
    function removeCP(address cp) external onlyOperator whenNotPaused {
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
     * @dev Check if a computing provider is currently whitelisted
     * @param cp Address to check
     * @return bool True if CP is whitelisted, false otherwise
     */
    function isWhitelisted(address cp) external view returns (bool) {
        return cpInfo[cp].isWhitelisted;
    }

    /**
     * @dev Get detailed information about a computing provider
     * @param cp Address to query
     * @return CPInfo Struct containing whitelist status and timestamps
     */
    function getCPInfo(address cp) external view returns (CPInfo memory) {
        return cpInfo[cp];
    }

    /**
     * @dev Get list of all currently whitelisted computing providers
     * @return address[] Array of whitelisted CP addresses
     */
    function getWhitelistedCPs() external view returns (address[] memory) {
        return whitelistedCPs;
    }

    /**
     * @dev Pause all whitelist operations
     * @notice Only callable by admin
     * @notice Used in emergency situations
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @dev Resume all whitelist operations
     * @notice Only callable by admin
     * @notice Used to resume operations after emergency is resolved
     */
    function unpause() external onlyAdmin {
        _unpause();
    }
}