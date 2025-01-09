// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Core/StateManager.sol";
import "../src/Core/storage/Constants.sol";

contract StateManagerTest is Test, Constants, StateManager {
    StateManager public stateManager;
    uint8 public constant BUFFER = 5;

    function setUp() public {
        stateManager = new StateManager();
    }

    function testGetEpoch() public {
        // Test at epoch 0
        assertEq(stateManager.getEpoch(), 0);

        // Test at epoch 1
        vm.warp(EPOCH_LENGTH);
        assertEq(stateManager.getEpoch(), 1);

        // Test at epoch 5
        vm.warp(5 * EPOCH_LENGTH);
        assertEq(stateManager.getEpoch(), 5);

        // Test at a specific timestamp
        uint256 timestamp = 1703347200; // Some specific timestamp
        vm.warp(timestamp);
        assertEq(stateManager.getEpoch(), timestamp / EPOCH_LENGTH);
    }

    function testAssignState() public {
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        
        // Test middle of Assign state
        uint256 assignTime = stateLength / 2;
        vm.warp(assignTime);
        assertEq(uint8(stateManager.getState(BUFFER)), uint8(State.Assign));
    }

    function testUpdateState() public {
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        
        // Test middle of Update state
        uint256 updateTime = stateLength + (stateLength / 2);
        vm.warp(updateTime);
        assertEq(uint8(stateManager.getState(BUFFER)), uint8(State.Update));
    }

    function testConfirmState() public {
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        
        // Test middle of Confirm state
        uint256 confirmTime = 2 * stateLength + (stateLength / 2);
        vm.warp(confirmTime);
        assertEq(uint8(stateManager.getState(BUFFER)), uint8(State.Confirm));
    }

    function testBufferState() public {
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        
        // Test at the start buffer
        vm.warp(2); // Just after epoch start
        assertEq(uint8(stateManager.getState(BUFFER)), uint8(State.Buffer));

        // Test at the end buffer of first state
        vm.warp(stateLength - 2);
        assertEq(uint8(stateManager.getState(BUFFER)), uint8(State.Buffer));

        // Test at the buffer between states
        vm.warp(stateLength + 2);
        assertEq(uint8(stateManager.getState(BUFFER)), uint8(State.Buffer));
    }

    function testStateModifier() public {
        function(State, uint8) external returns (bool) fn = this.dummyStateFunction;
        
        // Test happy path
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        uint256 assignTime = stateLength / 2;
        vm.warp(assignTime);
        assertTrue(fn(State.Assign, BUFFER));

        // Test incorrect state
        vm.expectRevert("Incorrect state");
        fn(State.Update, BUFFER);
    }

    function testEpochModifier() public {
        function(uint32) external returns (bool) fn = this.dummyEpochFunction;
        
        // Test happy path
        assertTrue(fn(0));

        // Test incorrect epoch
        vm.warp(EPOCH_LENGTH); // Move to epoch 1
        vm.expectRevert("Incorrect epoch");
        fn(0);
    }

    function testEpochAndStateModifier() public {
        function(State, uint32, uint8) external returns (bool) fn = this.dummyEpochAndStateFunction;
        
        // Test happy path
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        uint256 assignTime = stateLength / 2;
        vm.warp(assignTime);
        assertTrue(fn(State.Assign, 0, BUFFER));

        // Test incorrect epoch
        vm.warp(EPOCH_LENGTH); // Move to epoch 1
        vm.expectRevert("Incorrect epoch");
        fn(State.Assign, 0, BUFFER);

        // Test incorrect state
        vm.warp(assignTime);
        vm.expectRevert("Incorrect state");
        fn(State.Update, 0, BUFFER);
    }

    // Dummy functions to test modifiers
    function dummyStateFunction(State state, uint8 buffer) external view checkState(state, buffer) returns (bool) {
        return true;
    }

    function dummyEpochFunction(uint32 epoch) external view checkEpoch(epoch) returns (bool) {
        return true;
    }

    function dummyEpochAndStateFunction(State state, uint32 epoch, uint8 buffer) 
        external 
        view 
        checkEpochAndState(state, epoch, buffer) 
        returns (bool) 
    {
        return true;
    }

    function testStateTransitions() public {
        uint256 stateLength = EPOCH_LENGTH / NUM_STATES;
        
        // Test each state in sequence
        for (uint8 i = 0; i < NUM_STATES; i++) {
            // Start of state (plus buffer to avoid being in buffer state)
            uint256 stateStart = i * stateLength;
            vm.warp(stateStart + BUFFER + 1);
            
            State currentState = stateManager.getState(BUFFER);
            console.log("Testing state transition. Expected:", i, "Got:", uint(currentState));
            assertEq(uint(currentState), uint(i), string(abi.encodePacked("State should be ", vm.toString(i))));

            // Middle of state
            vm.warp(stateStart + (stateLength / 2));
            assertEq(uint(stateManager.getState(BUFFER)), uint(i), "Middle of state should match");

            // Just before buffer (should still be in current state)
            vm.warp(stateStart + stateLength - BUFFER - 1);
            assertEq(uint(stateManager.getState(BUFFER)), uint(i), "Before buffer should match");

            // In buffer period
            vm.warp(stateStart + stateLength - (BUFFER / 2));
            assertEq(uint(stateManager.getState(BUFFER)), uint(State.Buffer), "Should be in buffer state");
        }
    }
}