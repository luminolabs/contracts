// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/StakeManager.sol";
import "../src/Core/JobsManager.sol";
import "../src/Core/storage/Constants.sol";

contract StakeManagerTest is Test, Constants {
    StakeManager public stakeManager;
    JobsManager public jobsManager;
    address public admin;
    address public staker1;
    address public staker2;

    function setUp() public {
        admin = address(this);
        staker1 = address(0x1);
        staker2 = address(0x2);

        // Deploy JobManager first
        jobsManager = new JobsManager();
        jobsManager.initialize(5, address(0)); // Initialize with a dummy jobs manager address first

        stakeManager = new StakeManager();
        stakeManager.initialize(address(jobsManager));

        // Fund stakers with some ETH for testing
        vm.deal(staker1, 100 ether);
        vm.deal(staker2, 100 ether);
    }

    function testInitialization() public view {
        assertEq(stakeManager.numStakers(), 0);
        assertTrue(stakeManager.hasRole(stakeManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testStake() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256 stakeAmount = 10 ether;

        vm.prank(staker1);
        stakeManager.stake{value: stakeAmount}(currentEpoch, stakeAmount, "test-spec");

        assertEq(stakeManager.numStakers(), 1);
        assertEq(stakeManager.getStakerId(staker1), 1);
        
        Structs.Staker memory stakerInfo = stakeManager.getStaker(1);
        assertEq(stakerInfo.stake, stakeAmount);
        assertEq(stakerInfo._address, staker1);
        assertEq(stakerInfo.epochFirstStaked, currentEpoch);
    }

    function testStakeInsufficientAmount() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256 stakeAmount = 0.5 ether; // Less than minSafeLumToken

        vm.prank(staker1);
        vm.expectRevert("Less than minimum safe LUMINO token amount");
        stakeManager.stake{value: stakeAmount}(currentEpoch, stakeAmount, "test-spec");
    }

    function testUnstake() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256 stakeAmount = 10 ether;

        vm.startPrank(staker1);
        stakeManager.stake{value: stakeAmount}(currentEpoch, stakeAmount, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        stakeManager.unstake(stakerId, 5 ether);
        vm.stopPrank();

        Structs.Lock memory lock = stakeManager.getLocks(staker1);
        assertEq(lock.amount, 5 ether);
        assertEq(lock.unlockAfter, currentEpoch + stakeManager.unstakeLockPeriod());
    }

    function testWithdraw() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256 stakeAmount = 10 ether;

        vm.startPrank(staker1);
        stakeManager.stake{value: stakeAmount}(currentEpoch, stakeAmount, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        stakeManager.unstake(stakerId, 5 ether);

        // Advance time to after the unlock period
        vm.warp(block.timestamp + (stakeManager.unstakeLockPeriod() + 1) * EPOCH_LENGTH);

        uint256 balanceBefore = address(staker1).balance;
        stakeManager.withdraw(stakerId);
        uint256 balanceAfter = address(staker1).balance;

        assertEq(balanceAfter - balanceBefore, 5 ether);
        vm.stopPrank();
    }

    function testWithdrawBeforeUnlock() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256 stakeAmount = 10 ether;

        vm.startPrank(staker1);
        stakeManager.stake{value: stakeAmount}(currentEpoch, stakeAmount, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        stakeManager.unstake(stakerId, 5 ether);

        vm.expectRevert("Unlock period not reached");
        stakeManager.withdraw(stakerId);
        vm.stopPrank();
    }

    // Add more tests here for edge cases and other functions
}