// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Core/StateManager.sol";
import "../src/Core/storage/Constants.sol";

contract StateManagerTest is Constants, Test {
    StateManager stateManager;

    function setUp() public {
        stateManager = new StateManager();
    }

    function testCommitState() public {
        uint8 buffer = 5;
        // Set block.timestamp to be in the Assign state window
        uint256 assignTime = (EPOCH_LENGTH / NUM_STATES) / 2; // Middle of Assign state
        vm.warp(assignTime);
        
        State state = stateManager.getState(buffer);
        assertEq(uint8(state), uint8(State.Assign));
    }

    function testRevealState() public {
        uint8 buffer = 5;
        // Set block.timestamp to be in the Update state window
        uint256 updateTime = (EPOCH_LENGTH / NUM_STATES) + (EPOCH_LENGTH / NUM_STATES / 2); // Middle of Update state
        vm.warp(updateTime);
        
        State state = stateManager.getState(buffer);
        assertEq(uint8(state), uint8(State.Update));
    }

    function testProposeState() public {
        uint8 buffer = 5;
        // Set block.timestamp to be in the Confirm state window
        uint256 confirmTime = 2 * (EPOCH_LENGTH / NUM_STATES) + (EPOCH_LENGTH / NUM_STATES / 2); // Middle of Confirm state
        vm.warp(confirmTime);
        
        State state = stateManager.getState(buffer);
        assertEq(uint8(state), uint8(State.Confirm));
    }

    function testBufferState() public {
        uint8 buffer = 5;
        // Set block.timestamp to be in the buffer period
        uint256 bufferTime = (EPOCH_LENGTH / NUM_STATES) - 2; // Just before state transition
        vm.warp(bufferTime);
        
        State state = stateManager.getState(buffer);
        assertEq(uint8(state), uint8(State.Buffer));
    }

    function testNonBufferState() public {
        uint8 buffer = 5;
        // Set block.timestamp to be clearly in a non-buffer period
        uint256 nonBufferTime = (EPOCH_LENGTH / NUM_STATES) / 2; // Middle of first state
        vm.warp(nonBufferTime);
        
        State state = stateManager.getState(buffer);
        assertTrue(state != State.Buffer);
    }
}