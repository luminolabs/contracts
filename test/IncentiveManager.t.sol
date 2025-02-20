// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Test.sol";
// import "../src/IncentiveManager.sol";
// import "../src/libraries/LShared.sol";

// // Mock contracts
// contract MockEpochManager {
//     uint256 private currentEpoch = 1;

//     function getCurrentEpoch() external view returns (uint256) {
//         return currentEpoch;
//     }

//     function setCurrentEpoch(uint256 _epoch) external {
//         currentEpoch = _epoch;
//     }
// }

// contract MockLeaderManager {
//     uint256 private currentLeader;
//     mapping(uint256 => uint256[]) private revealedNodes;
//     bool private assignmentRoundStarted;

//     function setCurrentLeader(uint256 _leader) external {
//         currentLeader = _leader;
//     }

//     function getCurrentLeader() external view returns (uint256) {
//         return currentLeader;
//     }

//     function setNodesWhoRevealed(uint256 epoch, uint256[] calldata nodes) external {
//         delete revealedNodes[epoch];
//         for(uint256 i = 0; i < nodes.length; i++) {
//             revealedNodes[epoch].push(nodes[i]);
//         }
//     }

//     function getNodesWhoRevealed(uint256 epoch) external view returns (uint256[] memory) {
//         return revealedNodes[epoch];
//     }
// }

// contract MockJobManager {
//     mapping(uint256 => bool) private roundStarted;
//     mapping(uint256 => uint256[]) private unconfirmedJobs;
//     mapping(uint256 => uint256) private assignedNodes;

//     function setAssignmentRoundStarted(uint256 epoch, bool started) external {
//         roundStarted[epoch] = started;
//     }

//     function wasAssignmentRoundStarted(uint256 epoch) external view returns (bool) {
//         return roundStarted[epoch];
//     }

//     function setUnconfirmedJobs(uint256 epoch, uint256[] calldata jobs) external {
//         delete unconfirmedJobs[epoch];
//         for(uint256 i = 0; i < jobs.length; i++) {
//             unconfirmedJobs[epoch].push(jobs[i]);
//         }
//     }

//     function getUnconfirmedJobs(uint256 epoch) external view returns (uint256[] memory) {
//         return unconfirmedJobs[epoch];
//     }

//     function setAssignedNode(uint256 jobId, uint256 nodeId) external {
//         assignedNodes[jobId] = nodeId;
//     }

//     function getAssignedNode(uint256 jobId) external view returns (uint256) {
//         return assignedNodes[jobId];
//     }
// }

// contract MockNodeManager {
//     mapping(uint256 => address) private nodeOwners;

//     function setNodeOwner(uint256 nodeId, address owner) external {
//         nodeOwners[nodeId] = owner;
//     }

//     function getNodeOwner(uint256 nodeId) external view returns (address) {
//         return nodeOwners[nodeId];
//     }
// }

// contract MockNodeEscrow {
//     mapping(address => uint256) private balances;

//     function setBalance(address user, uint256 balance) external {
//         balances[user] = balance;
//     }

//     function getBalance(address user) external view returns (uint256) {
//         return balances[user];
//     }

//     function applyPenalty(address cp, uint256 amount) external {
//         balances[cp] -= amount;
//     }
// }

// contract MockIncentiveTreasury {
//     event RewardDistributed(address indexed recipient, uint256 amount, string reason);
//     event PenaltyApplied(address indexed offender, uint256 amount, string reason);

//     function distributeReward(address recipient, uint256 amount, string calldata reason) external {
//         emit RewardDistributed(recipient, amount, reason);
//     }

//     function applyPenalty(address offender, uint256 amount, string calldata reason) external {
//         emit PenaltyApplied(offender, amount, reason);
//     }
// }

// contract IncentiveManagerTest is Test {
//     IncentiveManager public incentiveManager;
//     MockEpochManager public epochManager;
//     MockLeaderManager public leaderManager;
//     MockJobManager public jobManager;
//     MockNodeManager public nodeManager;
//     MockNodeEscrow public nodeEscrow;
//     MockIncentiveTreasury public treasury;

//     // Test addresses
//     address public leader = address(1);
//     address public node1 = address(2);
//     address public node2 = address(3);
    
//     function setUp() public {
//         // Deploy mock contracts
//         epochManager = new MockEpochManager();
//         leaderManager = new MockLeaderManager();
//         jobManager = new MockJobManager();
//         nodeManager = new MockNodeManager();
//         nodeEscrow = new MockNodeEscrow();
//         treasury = new MockIncentiveTreasury();

//         // Deploy IncentiveManager
//         incentiveManager = new IncentiveManager(
//             address(epochManager),
//             address(leaderManager),
//             address(jobManager),
//             address(nodeManager),
//             address(nodeEscrow),
//             address(treasury)
//         );

//         // Set up initial state
//         epochManager.setCurrentEpoch(2); // Allow processing of epoch 1
//     }

//     function testProcessAllBasicSuccess() public {
//         // Setup epoch 1 state
//         leaderManager.setCurrentLeader(1);
//         nodeManager.setNodeOwner(1, leader);
//         jobManager.setAssignmentRoundStarted(1, true);

//         uint256[] memory revealedNodes = new uint256[](2);
//         revealedNodes[0] = 1;
//         revealedNodes[1] = 2;
//         leaderManager.setNodesWhoRevealed(1, revealedNodes);

//         nodeManager.setNodeOwner(1, node1);
//         nodeManager.setNodeOwner(2, node2);

//         // Process rewards and penalties
//         incentiveManager.processAll(1);

//         // Verify cannot process same epoch again
//         vm.expectRevert("Epoch already processed");
//         incentiveManager.processAll(1);
//     }

//     function testLeaderRewards() public {
//         // Setup
//         leaderManager.setCurrentLeader(1);
//         nodeManager.setNodeOwner(1, leader);
//         jobManager.setAssignmentRoundStarted(1, true);

//         // Expect leader reward event
//         vm.expectEmit(true, false, false, true);
//         emit RewardDistributed(leader, LShared.LEADER_ASSIGNMENT_REWARD, "Leader assignment round completion");

//         incentiveManager.processAll(1);
//     }

//     function testLeaderPenalties() public {
//         // Setup leader who missed assignment round
//         leaderManager.setCurrentLeader(1);
//         nodeManager.setNodeOwner(1, leader);
//         jobManager.setAssignmentRoundStarted(1, false);
//         nodeEscrow.setBalance(leader, LShared.MISSED_ASSIGNMENT_PENALTY * 2);

//         // Expect penalty event
//         vm.expectEmit(true, false, false, true);
//         emit PenaltyApplied(leader, LShared.MISSED_ASSIGNMENT_PENALTY, "Missed assignment round");

//         incentiveManager.processAll(1);
//     }

//     function testNodeRevealRewards() public {
//         // Setup nodes who revealed
//         uint256[] memory revealedNodes = new uint256[](2);
//         revealedNodes[0] = 1;
//         revealedNodes[1] = 2;
//         leaderManager.setNodesWhoRevealed(1, revealedNodes);

//         nodeManager.setNodeOwner(1, node1);
//         nodeManager.setNodeOwner(2, node2);

//         // Expect reward events for both nodes
//         vm.expectEmit(true, false, false, true);
//         emit RewardDistributed(node1, LShared.SECRET_REVEAL_REWARD, "Secret revelation reward");
//         vm.expectEmit(true, false, false, true);
//         emit RewardDistributed(node2, LShared.SECRET_REVEAL_REWARD, "Secret revelation reward");

//         incentiveManager.processAll(1);
//     }

//     function testMissedConfirmationPenalties() public {
//         // Setup unconfirmed jobs
//         uint256[] memory unconfirmedJobs = new uint256[](2);
//         unconfirmedJobs[0] = 1;
//         unconfirmedJobs[1] = 2;
//         jobManager.setUnconfirmedJobs(1, unconfirmedJobs);

//         // Setup job assignments
//         jobManager.setAssignedNode(1, 1); // Job 1 assigned to Node 1
//         jobManager.setAssignedNode(2, 2); // Job 2 assigned to Node 2
//         nodeManager.setNodeOwner(1, node1);
//         nodeManager.setNodeOwner(2, node2);

//         // Set balances for penalties
//         nodeEscrow.setBalance(node1, LShared.MISSED_CONFIRMATION_PENALTY * 2);
//         nodeEscrow.setBalance(node2, LShared.MISSED_CONFIRMATION_PENALTY * 2);

//         // Expect penalty events
//         vm.expectEmit(true, false, false, true);
//         emit PenaltyApplied(node1, LShared.MISSED_CONFIRMATION_PENALTY, "Missed job confirmation");
//         vm.expectEmit(true, false, false, true);
//         emit PenaltyApplied(node2, LShared.MISSED_CONFIRMATION_PENALTY, "Missed job confirmation");

//         incentiveManager.processAll(1);
//     }

//     function testSlashingAfterMaxPenalties() public {
//         // Setup node with many penalties
//         leaderManager.setCurrentLeader(1);
//         nodeManager.setNodeOwner(1, leader);
//         jobManager.setAssignmentRoundStarted(1, false);
//         nodeEscrow.setBalance(leader, 1000 ether);

//         // Apply penalties until slashing
//         for(uint256 i = 1; i <= LShared.MAX_PENALTIES_BEFORE_SLASH; i++) {
//             incentiveManager.processAll(i);
//             epochManager.setCurrentEpoch(i + 2); // Allow processing next epoch
//         }

//         // Verify leader was slashed (all stake taken)
//         assertEq(nodeEscrow.getBalance(leader), 0);
//     }

//     function testCannotProcessCurrentEpoch() public {
//         uint256 currentEpoch = epochManager.getCurrentEpoch();
//         vm.expectRevert("Cannot process current epoch");
//         incentiveManager.processAll(currentEpoch);
//     }

//     function testCannotProcessFutureEpoch() public {
//         uint256 currentEpoch = epochManager.getCurrentEpoch();
//         vm.expectRevert("Cannot process current epoch");
//         incentiveManager.processAll(currentEpoch + 1);
//     }

//     function testDisputerReward() public {
//         // Setup basic state
//         leaderManager.setCurrentLeader(1);
//         nodeManager.setNodeOwner(1, leader);

//         // Expect disputer reward
//         vm.expectEmit(true, false, false, true);
//         emit RewardDistributed(address(this), LShared.DISPUTE_REWARD, "Dispute completion reward");

//         incentiveManager.processAll(1);
//     }
// }