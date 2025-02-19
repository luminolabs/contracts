// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/EpochManager.sol";
import "../src/libraries/LShared.sol";

contract EpochManagerTest is Test {
    EpochManager public epochManager;
    
    // Constants from LShared for easier reference
    uint256 constant COMMIT_DURATION = 10;
    uint256 constant REVEAL_DURATION = 10;
    uint256 constant ELECT_DURATION = 10;
    uint256 constant EXECUTE_DURATION = 60;
    uint256 constant CONFIRM_DURATION = 20;
    uint256 constant DISPUTE_DURATION = 10;
    uint256 constant EPOCH_DURATION = COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + 
                                    EXECUTE_DURATION + CONFIRM_DURATION + DISPUTE_DURATION;

    function setUp() public {
        epochManager = new EpochManager();
        // Start at a clean epoch boundary
        vm.warp(EPOCH_DURATION);
    }

    function testGetCurrentEpoch() public {
        // At EPOCH_DURATION, we should be at epoch 2 (epochs start at 1)
        assertEq(epochManager.getCurrentEpoch(), 2);
        
        // Move forward one epoch
        vm.warp(EPOCH_DURATION * 2);
        assertEq(epochManager.getCurrentEpoch(), 3);
        
        // Test partial epoch
        vm.warp((EPOCH_DURATION * 5) / 2);
        assertEq(epochManager.getCurrentEpoch(), 3);
    }

    function testEpochStateCommit() public {
        // Test start of epoch (COMMIT state)
        vm.warp(EPOCH_DURATION); // Start of epoch 2
        (IEpochManager.State state, uint256 timeLeft) = epochManager.getEpochState();
        
        assertEq(uint256(state), uint256(IEpochManager.State.COMMIT));
        assertEq(timeLeft, COMMIT_DURATION);
        
        // Test middle of COMMIT
        vm.warp(EPOCH_DURATION + 5);
        (state, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.COMMIT));
        assertEq(timeLeft, COMMIT_DURATION - 5);
        
        // Validate state
        epochManager.validateEpochState(IEpochManager.State.COMMIT);
    }

    function testEpochStateReveal() public {
        // Move to REVEAL state
        vm.warp(EPOCH_DURATION + COMMIT_DURATION);
        (IEpochManager.State state, uint256 timeLeft) = epochManager.getEpochState();
        
        assertEq(uint256(state), uint256(IEpochManager.State.REVEAL));
        assertEq(timeLeft, REVEAL_DURATION);
        
        // Test middle of REVEAL
        vm.warp(EPOCH_DURATION + COMMIT_DURATION + 5);
        (state, timeLeft) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.REVEAL));
        assertEq(timeLeft, REVEAL_DURATION - 5);
        
        // Validate state
        epochManager.validateEpochState(IEpochManager.State.REVEAL);
    }

    function testEpochStateElect() public {
        // Move to ELECT state
        vm.warp(EPOCH_DURATION + COMMIT_DURATION + REVEAL_DURATION);
        (IEpochManager.State state, uint256 timeLeft) = epochManager.getEpochState();
        
        assertEq(uint256(state), uint256(IEpochManager.State.ELECT));
        assertEq(timeLeft, ELECT_DURATION);
        
        // Validate state
        epochManager.validateEpochState(IEpochManager.State.ELECT);
    }

    function testEpochStateExecute() public {
        // Move to EXECUTE state
        vm.warp(EPOCH_DURATION + COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION);
        (IEpochManager.State state, uint256 timeLeft) = epochManager.getEpochState();
        
        assertEq(uint256(state), uint256(IEpochManager.State.EXECUTE));
        assertEq(timeLeft, EXECUTE_DURATION);
        
        // Validate state
        epochManager.validateEpochState(IEpochManager.State.EXECUTE);
    }

    function testEpochStateConfirm() public {
        // Move to CONFIRM state
        vm.warp(EPOCH_DURATION + COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION);
        (IEpochManager.State state, uint256 timeLeft) = epochManager.getEpochState();
        
        assertEq(uint256(state), uint256(IEpochManager.State.CONFIRM));
        assertEq(timeLeft, CONFIRM_DURATION);
        
        // Validate state
        epochManager.validateEpochState(IEpochManager.State.CONFIRM);
    }

    function testEpochStateDispute() public {
        // Move to DISPUTE state
        vm.warp(EPOCH_DURATION + COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + 
                EXECUTE_DURATION + CONFIRM_DURATION);
        (IEpochManager.State state, uint256 timeLeft) = epochManager.getEpochState();
        
        assertEq(uint256(state), uint256(IEpochManager.State.DISPUTE));
        assertEq(timeLeft, DISPUTE_DURATION);
        
        // Validate state
        epochManager.validateEpochState(IEpochManager.State.DISPUTE);
    }

    function testFullEpochCycle() public {
        uint256 startTime = EPOCH_DURATION; // Start of epoch 2
        vm.warp(startTime);
        
        // Test each state transition
        (IEpochManager.State state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.COMMIT));
        
        vm.warp(startTime + COMMIT_DURATION);
        (state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.REVEAL));
        
        vm.warp(startTime + COMMIT_DURATION + REVEAL_DURATION);
        (state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.ELECT));
        
        vm.warp(startTime + COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION);
        (state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.EXECUTE));
        
        vm.warp(startTime + COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + EXECUTE_DURATION);
        (state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.CONFIRM));
        
        vm.warp(startTime + COMMIT_DURATION + REVEAL_DURATION + ELECT_DURATION + 
                EXECUTE_DURATION + CONFIRM_DURATION);
        (state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.DISPUTE));
        
        // Move to next epoch
        vm.warp(startTime + EPOCH_DURATION);
        (state,) = epochManager.getEpochState();
        assertEq(uint256(state), uint256(IEpochManager.State.COMMIT));
    }

    function testInvalidStateValidation() public {
        vm.warp(EPOCH_DURATION); // Start at COMMIT state
        
        // Try to validate REVEAL state during COMMIT
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.REVEAL)));
        epochManager.validateEpochState(IEpochManager.State.REVEAL);
        
        // Try to validate ELECT state during COMMIT
        vm.expectRevert(abi.encodeWithSignature("InvalidState(uint8)", uint8(IEpochManager.State.ELECT)));
        epochManager.validateEpochState(IEpochManager.State.ELECT);
    }
}