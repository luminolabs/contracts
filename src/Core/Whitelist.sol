// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ACL.sol";

/**
 * @title Whitelist
 * @dev An implementation of a whitelist system with essential features and security measures
 * @notice This contract provides a robust whitelisting mechanism with batch operations and safety checks
 */
contract Whitelist is ACL {
    
    constructor () {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Mapping to track whitelisted addresses
     * @notice true if address is whitelisted, false otherwise
     */
    mapping(address => bool) public whitelist;
    
    /**
     * @dev Maximum batch size for adding/removing addresses
     * @notice This prevents out-of-gas errors in batch operations
     */
    uint256 public constant MAX_BATCH_SIZE = 100;
    
    // Events
    /**
     * @dev Emitted when a single address is added to the whitelist
     * @param addr The address that was added
     */
    event WhitelistedAddressAdded(address indexed addr);
    
    /**
     * @dev Emitted when a single address is removed from the whitelist
     * @param addr The address that was removed
     */
    event WhitelistedAddressRemoved(address indexed addr);
    
    /**
     * @dev Emitted when multiple addresses are added in a batch
     * @param addrs Array of addresses that were added
     */
    event BatchWhitelistAdded(address[] addrs);
    
    /**
     * @dev Emitted when multiple addresses are removed in a batch
     * @param addrs Array of addresses that were removed
     */
    event BatchWhitelistRemoved(address[] addrs);

    /**
     * @dev Modifier to restrict function access to whitelisted addresses only
     * @notice Throws if called by any account that's not whitelisted
     */
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Caller is not whitelisted");
        _;
    }

    /**
     * @dev Checks if an address is valid for whitelisting
     * @param addr Address to validate
     * @return true if address is valid, false otherwise
     */
    function isValidAddress(address addr) internal pure returns (bool) {
        return addr != address(0);
    }

    /**
     * @dev Add a single address to the whitelist
     * @param addr Address to be added to the whitelist
     * @return success True if the address was added, false if it was already whitelisted
     */
    function addAddressToWhitelist(address addr)  
        public 
        returns(bool success) 
    {
        require(isValidAddress(addr), "Invalid address provided");
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only Admin can add addresses to whitelist");
        
        // Only add if not already whitelisted
        if (!whitelist[addr]) {
            whitelist[addr] = true;
            emit WhitelistedAddressAdded(addr);
            return true;
        }
        return false;
    }

    /**
     * @dev Add multiple addresses to the whitelist
     * @param addrs Array of addresses to be added to the whitelist
     * @return success True if at least one address was added
     */
    function addAddressesToWhitelist(address[] calldata addrs) 
        public 
        returns(bool success) 
    {
        require(addrs.length > 0, "Empty array provided");
        require(addrs.length <= MAX_BATCH_SIZE, "Batch size exceeds limit");
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only Admin can add addresses to whitelist");

        bool anySuccess = false;
        
        // Process all addresses in the batch
        for (uint256 i = 0; i < addrs.length; i++) {
            require(isValidAddress(addrs[i]), "Invalid address in batch");
            
            if (!whitelist[addrs[i]]) {
                whitelist[addrs[i]] = true;
                anySuccess = true;
            }
        }
        
        // Emit batch event if any address was added
        if (anySuccess) {
            emit BatchWhitelistAdded(addrs);
        }
        
        return anySuccess;
    }

    /**
     * @dev Remove a single address from the whitelist
     * @param addr Address to be removed from the whitelist
     * @return success True if the address was removed, false if it wasn't whitelisted
     */
    function removeAddressFromWhitelist(address addr) 
        public 
        returns(bool success) 
    {
        require(isValidAddress(addr), "Invalid address provided");
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only Admin can add addresses to whitelist");
        
        // Only remove if currently whitelisted
        if (whitelist[addr]) {
            whitelist[addr] = false;
            emit WhitelistedAddressRemoved(addr);
            return true;
        }
        return false;
    }

    /**
     * @dev Remove multiple addresses from the whitelist
     * @param addrs Array of addresses to be removed from the whitelist
     * @return success True if at least one address was removed
     */
    function removeAddressesFromWhitelist(address[] calldata addrs) 
        public 
        returns(bool success) 
    {
        require(addrs.length > 0, "Empty array provided");
        require(addrs.length <= MAX_BATCH_SIZE, "Batch size exceeds limit");
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only Admin can add addresses to whitelist");
        bool anySuccess = false;
        
        // Process all addresses in the batch
        for (uint256 i = 0; i < addrs.length; i++) {
            require(isValidAddress(addrs[i]), "Invalid address in batch");
            
            if (whitelist[addrs[i]]) {
                whitelist[addrs[i]] = false;
                anySuccess = true;
            }
        }
        
        // Emit batch event if any address was removed
        if (anySuccess) {
            emit BatchWhitelistRemoved(addrs);
        }
        
        return anySuccess;
    }

    /**
     * @dev Check if an address is whitelisted
     * @param addr Address to check
     * @return bool True if the address is whitelisted
     */
    function isWhitelisted(address addr) 
        public 
        view 
        returns (bool) 
    {
        return whitelist[addr];
    }
}