// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/Whitelist.sol";

contract WhitelistTest is Test {
    Whitelist public whitelist;
    address public admin;
    address public user1;
    address public user2;
    address public user3;

    event WhitelistedAddressAdded(address indexed addr);
    event WhitelistedAddressRemoved(address indexed addr);
    event BatchWhitelistAdded(address[] addrs);
    event BatchWhitelistRemoved(address[] addrs);

    function setUp() public {
        // Setup accounts
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy contract
        whitelist = new Whitelist();
    }

    // Test initialization
    function test_InitialState() public view {
        assertTrue(whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(whitelist.isWhitelisted(user1));
        assertFalse(whitelist.isWhitelisted(user2));
        assertFalse(whitelist.isWhitelisted(user3));
    }

    // Test single address whitelisting
    function test_AddAddressToWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit WhitelistedAddressAdded(user1);
        
        bool success = whitelist.addAddressToWhitelist(user1);
        assertTrue(success);
        assertTrue(whitelist.isWhitelisted(user1));
    }

    // Test adding already whitelisted address
    function test_AddExistingAddressToWhitelist() public {
        whitelist.addAddressToWhitelist(user1);
        bool success = whitelist.addAddressToWhitelist(user1);
        assertFalse(success);
        assertTrue(whitelist.isWhitelisted(user1));
    }

    // Test removing address from whitelist
    function test_RemoveAddressFromWhitelist() public {
        whitelist.addAddressToWhitelist(user1);
        
        vm.expectEmit(true, false, false, true);
        emit WhitelistedAddressRemoved(user1);
        
        bool success = whitelist.removeAddressFromWhitelist(user1);
        assertTrue(success);
        assertFalse(whitelist.isWhitelisted(user1));
    }

    // Test batch address whitelisting
    function test_AddAddressesToWhitelist() public {
        address[] memory addrs = new address[](3);
        addrs[0] = user1;
        addrs[1] = user2;
        addrs[2] = user3;

        vm.expectEmit(false, false, false, true);
        emit BatchWhitelistAdded(addrs);
        
        bool success = whitelist.addAddressesToWhitelist(addrs);
        assertTrue(success);
        assertTrue(whitelist.isWhitelisted(user1));
        assertTrue(whitelist.isWhitelisted(user2));
        assertTrue(whitelist.isWhitelisted(user3));
    }

    // Test batch address removal
    function test_RemoveAddressesFromWhitelist() public {
        // First add addresses
        address[] memory addrs = new address[](3);
        addrs[0] = user1;
        addrs[1] = user2;
        addrs[2] = user3;
        whitelist.addAddressesToWhitelist(addrs);

        vm.expectEmit(false, false, false, true);
        emit BatchWhitelistRemoved(addrs);
        
        bool success = whitelist.removeAddressesFromWhitelist(addrs);
        assertTrue(success);
        assertFalse(whitelist.isWhitelisted(user1));
        assertFalse(whitelist.isWhitelisted(user2));
        assertFalse(whitelist.isWhitelisted(user3));
    }

    // Test access control
    function test_OnlyAdminCanAddAddress() public {
        vm.startPrank(user1);
        vm.expectRevert("Only Admin can add addresses to whitelist");
        whitelist.addAddressToWhitelist(user2);
        vm.stopPrank();
    }

    function test_OnlyAdminCanRemoveAddress() public {
        whitelist.addAddressToWhitelist(user1);
        
        vm.startPrank(user2);
        vm.expectRevert("Only Admin can add addresses to whitelist");
        whitelist.removeAddressFromWhitelist(user1);
        vm.stopPrank();
    }

    // Test edge cases
    function test_AddZeroAddress() public {
        vm.expectRevert("Invalid address provided");
        whitelist.addAddressToWhitelist(address(0));
    }

    function test_EmptyBatchAdd() public {
        address[] memory emptyAddrs = new address[](0);
        vm.expectRevert("Empty array provided");
        whitelist.addAddressesToWhitelist(emptyAddrs);
    }

    function test_BatchSizeLimit() public {
        // Create array larger than MAX_BATCH_SIZE
        address[] memory largeAddrs = new address[](101);
        for(uint i = 0; i < 101; i++) {
            largeAddrs[i] = address(uint160(i + 1));
        }
        
        vm.expectRevert("Batch size exceeds limit");
        whitelist.addAddressesToWhitelist(largeAddrs);
    }
}

// Helper contract to test onlyWhitelisted modifier
contract MockProtectedContract {
    Whitelist public whitelist;
    bool public functionCalled;

    constructor(address _whitelist) {
        whitelist = Whitelist(_whitelist);
        functionCalled = false;
    }

    function protectedFunction() public {
        require(whitelist.isWhitelisted(msg.sender), "Caller is not whitelisted");
        functionCalled = true;
    }
}