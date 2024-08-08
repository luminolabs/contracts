// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Core/BlockManager.sol";
import "../src/Core/storage/Constants.sol";
import "../src/Core/interface/IStakeManager.sol";
import "../src/Core/interface/IJobsManager.sol";

contract MockStakeManager is IStakeManager {
    mapping(address => uint32) public stakerIds;
    mapping(uint32 => uint256) public stakes;

    function getStakerId(address _address) external view returns (uint32) {
        return stakerIds[_address];
    }

    function getStaker(uint32 _id) external pure returns (Structs.Staker memory) {
        revert("Not implemented");
    }

    function getNumStakers() external pure returns (uint32) {
        return 1;
    }

    function getStake(uint32 stakerId) external view returns (uint256) {
        return stakes[stakerId];
    }

    // Mock functions for testing
    function setStakerId(address _address, uint32 _id) external {
        stakerIds[_address] = _id;
    }

    function setStake(uint32 _id, uint256 _stake) external {
        stakes[_id] = _stake;
    }
}

contract MockJobsManager is IJobsManager {
    mapping(uint256 => Constants.Status) public jobStatuses;

    function initialize(uint8 _jobsPerStaker) external {}
    function createJob(string memory _jobDetailsInJSON) external {}
    function updateJobStatus(uint256 _jobId, Constants.Status _newStatus) external {}
    function getActiveJobs() external pure returns (uint256[] memory) {
        revert("Not implemented");
    }
    function getJobDetails(uint256 _jobId) external pure returns (Structs.Job memory) {
        revert("Not implemented");
    }
    function getJobStatus(uint256 _jobId) external view returns (Constants.Status) {
        return jobStatuses[_jobId];
    }
    function getJobsForStaker(bytes32 _seed, uint32 _stakerId) external pure returns (uint256[] memory) {
        revert("Not implemented");
    }
    function jobsPerStaker() external pure returns (uint8) {
        return 5;
    }
    function jobIdCounter() external pure returns (uint256) {
        return 1;
    }

    // Mock function for testing
    function setJobStatus(uint256 _jobId, Constants.Status _status) external {
        jobStatuses[_jobId] = _status;
    }
}

contract BlockManagerTest is Test, Constants {
    BlockManager public blockManager;
    MockStakeManager public mockStakeManager;
    MockJobsManager public mockJobsManager;
    address public admin;
    address public staker1;
    address public staker2;

    function setUp() public {
        admin = address(this);
        staker1 = address(0x1);
        staker2 = address(0x2);

        mockStakeManager = new MockStakeManager();
        mockJobsManager = new MockJobsManager();

        blockManager = new BlockManager();
        blockManager.initialize(address(mockStakeManager), address(mockJobsManager), 10 ether);

        // Set up mock data
        mockStakeManager.setStakerId(staker1, 1);
        mockStakeManager.setStake(1, 20 ether);
        mockJobsManager.setJobStatus(1, Status.Execution);
    }

    function testInitialization() public {
        assertTrue(blockManager.hasRole(blockManager.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(address(blockManager.stakeManager()), address(mockStakeManager));
        assertEq(address(blockManager.jobsManager()), address(mockJobsManager));
    }

    function testPropose() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256[] memory jobIds = new uint256[](1);
        jobIds[0] = 1;

        vm.prank(staker1);
        blockManager.propose(currentEpoch, jobIds);

        assertEq(blockManager.numProposedBlocks(), 1);
        assertEq(blockManager.sortedProposedBlockIds(currentEpoch).length, 1);
    }

    function testProposeInvalidStaker() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256[] memory jobIds = new uint256[](1);
        jobIds[0] = 1;

        vm.prank(staker2);
        vm.expectRevert("Not a registered staker");
        blockManager.propose(currentEpoch, jobIds);
    }

    function testProposeInsufficientStake() public {
        mockStakeManager.setStake(1, 5 ether); // Set stake below minimum

        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256[] memory jobIds = new uint256[](1);
        jobIds[0] = 1;

        vm.prank(staker1);
        vm.expectRevert("Insufficient stake to propose");
        blockManager.propose(currentEpoch, jobIds);
    }

    function testConfirmBlock() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);
        uint256[] memory jobIds = new uint256[](1);
        jobIds[0] = 1;

        vm.prank(staker1);
        blockManager.propose(currentEpoch, jobIds);

        // Move to the next epoch
        vm.warp(block.timestamp + EPOCH_LENGTH);

        blockManager.confirmBlock(currentEpoch);

        Structs.Block memory confirmedBlock = blockManager.getConfirmedBlock(currentEpoch);
        assertEq(confirmedBlock.proposerId, 1);
        assertEq(confirmedBlock.jobIds.length, 1);
        assertEq(confirmedBlock.jobIds[0], 1);
    }

    function testConfirmBlockNoProposals() public {
        uint32 currentEpoch = uint32(block.timestamp / EPOCH_LENGTH);

        // Move to the next epoch
        vm.warp(block.timestamp + EPOCH_LENGTH);

        vm.expectRevert("No blocks proposed in the previous epoch");
        blockManager.confirmBlock(currentEpoch);
    }

    // Add more tests here for edge cases and other functions
}