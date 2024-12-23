// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Core/StakeManager.sol";
import "../src/Core/JobsManager.sol";
import "../src/Core/storage/Constants.sol";

contract StakeManagerTest is Test, Constants {
    StakeManager public stakeManager;
    JobsManager public jobsManager;
    address public admin;
    address public staker1;
    address public staker2;
    uint256 public constant MIN_STAKE = 10 ether;

    event NewStaker(uint32 indexed stakerId, address indexed stakerAddress);
    event StakeUpdated(uint32 indexed stakerId, uint256 newStake);

    function setUp() public {
        admin = address(this);
        staker1 = address(0x1);
        staker2 = address(0x2);

        // Deploy contracts
        stakeManager = new StakeManager();
        jobsManager = new JobsManager();
        
        // Initialize contracts
        stakeManager.initialize(address(jobsManager));
        jobsManager.initialize(5, address(stakeManager));

        // Fund test accounts
        vm.deal(staker1, 100 ether);
        vm.deal(staker2, 100 ether);
    }

    function testInitialization() public view {
        assertTrue(stakeManager.hasRole(stakeManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(stakeManager.numStakers(), 0);
    }

    function testFirstTimeStake() public {
        vm.startPrank(staker1);
        
        // Just make the stake call and verify the results
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        vm.stopPrank();

        assertEq(stakeManager.numStakers(), 1);
        assertEq(stakeManager.getStakerId(staker1), 1);
        
        Structs.Staker memory stakerInfo = stakeManager.getStaker(1);
        assertEq(stakerInfo._address, staker1);
        assertEq(stakerInfo.stake, MIN_STAKE);
        assertEq(stakerInfo.epochFirstStaked, 0);
        assertFalse(stakerInfo.isSlashed);
    }

    function testAdditionalStake() public {
        // Initial stake
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        uint256 additionalStake = 5 ether;
        
        // Add more stake
        vm.prank(staker1);
        stakeManager.stake{value: additionalStake}(0, additionalStake, "test-spec");

        Structs.Staker memory stakerInfo = stakeManager.getStaker(stakerId);
        assertEq(stakerInfo.stake, MIN_STAKE + additionalStake);
    }

    function testStakeWithInsufficientFunds() public {
        vm.prank(staker1);
        vm.expectRevert("Less than minimum safe LUMINO token amount");
        stakeManager.stake{value: 0.5 ether}(0, 0.5 ether, "test-spec");
    }

    function testUnstakeFlow() public {
        // Initial stake
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        uint256 unstakeAmount = 5 ether;

        // Unstake partial amount
        vm.prank(staker1);
        stakeManager.unstake(stakerId, unstakeAmount);

        // Check lock
        Structs.Lock memory lock = stakeManager.getLocks(staker1);
        assertEq(lock.amount, unstakeAmount);
        assertEq(lock.unlockAfter, uint32(block.timestamp / EPOCH_LENGTH) + unstakeLockPeriod);

        // Try to unstake again before withdrawal
        vm.prank(staker1);
        vm.expectRevert("Existing unstake lock");
        stakeManager.unstake(stakerId, 1 ether);
    }

    function testWithdrawFlow() public {
        // Initial stake
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        uint256 unstakeAmount = 5 ether;

        // Unstake
        vm.prank(staker1);
        stakeManager.unstake(stakerId, unstakeAmount);

        // Try to withdraw before lock period
        vm.prank(staker1);
        vm.expectRevert("Unlock period not reached");
        stakeManager.withdraw(stakerId);

        // Move forward past lock period
        vm.warp(block.timestamp + (unstakeLockPeriod + 1) * EPOCH_LENGTH);

        // Withdraw successfully
        uint256 balanceBefore = staker1.balance;
        vm.prank(staker1);
        stakeManager.withdraw(stakerId);
        uint256 balanceAfter = staker1.balance;

        assertEq(balanceAfter - balanceBefore, unstakeAmount);

        // Verify remaining stake
        Structs.Staker memory stakerInfo = stakeManager.getStaker(stakerId);
        assertEq(stakerInfo.stake, MIN_STAKE - unstakeAmount);
    }

    function testUnauthorizedUnstake() public {
        // Initial stake
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);

        // Try to unstake from different address
        vm.prank(staker2);
        vm.expectRevert("Can only unstake your own funds");
        stakeManager.unstake(stakerId, 1 ether);
    }

    function testExcessiveUnstake() public {
        // Initial stake
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);

        // Try to unstake more than staked
        vm.prank(staker1);
        vm.expectRevert("Unstake amount exceeds current stake");
        stakeManager.unstake(stakerId, MIN_STAKE + 1 ether);
    }

    function testInvalidStakerId() public {
        vm.prank(staker1);
        vm.expectRevert("Invalid staker ID");
        stakeManager.unstake(0, 1 ether);

        vm.prank(staker1);
        vm.expectRevert("No unstake request found");
        stakeManager.withdraw(1);
    }

    function testLocksAfterWithdraw() public {
        // Initial stake
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);

        // Unstake and withdraw
        vm.startPrank(staker1);
        stakeManager.unstake(stakerId, 1 ether);
        
        vm.warp(block.timestamp + (unstakeLockPeriod + 1) * EPOCH_LENGTH);
        stakeManager.withdraw(stakerId);
        vm.stopPrank();

        // Verify locks are reset
        Structs.Lock memory lock = stakeManager.getLocks(staker1);
        assertEq(lock.amount, 0);
        assertEq(lock.unlockAfter, 0);
    }

    // TODO: testSlashedStakerCannotStake, once we have the slashing function

    function testGetterFunctions() public {
        vm.prank(staker1);
        stakeManager.stake{value: MIN_STAKE}(0, MIN_STAKE, "test-spec");
        
        uint32 stakerId = stakeManager.getStakerId(staker1);
        
        assertEq(stakeManager.getNumStakers(), 1);
        assertEq(stakeManager.getStake(stakerId), MIN_STAKE);
        
        Structs.Staker memory stakerInfo = stakeManager.getStaker(stakerId);
        assertEq(stakerInfo._address, staker1);
        assertEq(stakerInfo.stake, MIN_STAKE);
    }
}