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

        vm.warp(1200);
        // Set block.timestamp to the start of the Commit state
        uint256 commitTime = block.timestamp - (block.timestamp % EPOCH_LENGTH) + 0 * (EPOCH_LENGTH / NUM_STATES) + buffer + 1;
        console.log(block.timestamp);
        console.log(commitTime);
        vm.warp(commitTime);

        State state = stateManager.getState(buffer);
        emit log_uint(uint8(state));
        assertEq(uint8(state), uint8(State.Commit));
    }

    function testRevealState() public {
        uint8 buffer = 5;

        // Set block.timestamp to the start of the Reveal state
        uint256 revealTime = block.timestamp - (block.timestamp % EPOCH_LENGTH) + 1 * (EPOCH_LENGTH / NUM_STATES) + buffer + 1;
        vm.warp(revealTime);

        State state = stateManager.getState(buffer);
        emit log_uint(uint8(state));
        assertEq(uint8(state), uint8(State.Reveal));
    }

    function testProposeState() public {
        uint8 buffer = 5;

        // Set block.timestamp to the start of the Propose state
        uint256 proposeTime = block.timestamp - (block.timestamp % EPOCH_LENGTH) + 2 * (EPOCH_LENGTH / NUM_STATES) + buffer + 1;
        vm.warp(proposeTime);

        State state = stateManager.getState(buffer);
        emit log_uint(uint8(state));
        assertEq(uint8(state), uint8(State.Propose));
    }

    function testBufferState() public {
        uint8 buffer = 5;

        // Set block.timestamp to the Buffer period at the end of the Commit state
        uint256 bufferTime = block.timestamp - (block.timestamp % EPOCH_LENGTH) + (EPOCH_LENGTH / NUM_STATES) + buffer - 1;
        vm.warp(bufferTime);

        State state = stateManager.getState(buffer);
        emit log_uint(uint8(state));
        assertEq(uint8(state), uint8(State.Buffer));
    }

    function testNonBufferState() public {
        uint8 buffer = 5;

        // Set block.timestamp to a time outside the buffer period
        uint256 nonBufferTime = block.timestamp - (block.timestamp % EPOCH_LENGTH) + buffer + 1;
        vm.warp(nonBufferTime);

        State state = stateManager.getState(buffer);
        emit log_uint(uint8(state));
        assert(state != State.Buffer);
    }
}