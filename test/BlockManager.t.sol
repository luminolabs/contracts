// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "../src/Core/JobsManager.sol";
// import "../src/Core/BlockManager.sol";
// import "../src/Core/storage/Constants.sol";

// contract BlockManagerTest is Test {
//     BlockManager public blockManager;
//     address public admin;
//     address public staker1;
//     address public staker2;

//     function setUp() public {
//         admin = address(this);
//         staker1 = address(0x1);
//         staker2 = address(0x2);

//         mockStakeManager = new MockStakeManager();
//         mockJobsManager = new MockJobsManager();

//         blockManager = new BlockManager();
//         blockManager.initialize(address(mockStakeManager), address(mockJobsManager), 10 ether);
//     }

//     function testInitialization() public {
//         assertEq(address(blockManager.stakeManager()), address(mockStakeManager));
//         assertEq(address(blockManager.jobsManager()), address(mockJobsManager));
//         assertEq(blockManager.minStake(), 10 ether);
//     }

//     function testPropose() public {
//         // Set up mock data and expectations
//         uint32 currentEpoch = uint32(block.timestamp / blockManager.EPOCH_LENGTH());
//         uint256[] memory jobIds = new uint256[](1);
//         jobIds[0] = 1;

//         mockStakeManager.setStakerId(staker1, 1);
//         mockStakeManager.setStake(1, 20 ether);
//         mockJobsManager.setJobStatus(1, BlockManager.Status.Execution);

//         vm.prank(staker1);
//         blockManager.propose(currentEpoch, jobIds);

//         assertEq(blockManager.numProposedBlocks(), 1);
//         assertEq(blockManager.sortedProposedBlockIds(currentEpoch).length, 1);
//     }

//     function testProposeInsufficientStake() public {
//         uint32 currentEpoch = uint32(block.timestamp / blockManager.EPOCH_LENGTH());
//         uint256[] memory jobIds = new uint256[](1);
//         jobIds[0] = 1;

//         mockStakeManager.setStakerId(staker1, 1);
//         mockStakeManager.setStake(1, 5 ether);

//         vm.prank(staker1);
//         vm.expectRevert("Insufficient stake to propose");
//         blockManager.propose(currentEpoch, jobIds);
//     }

//     // Add more tests here...
// }