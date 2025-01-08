// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import "../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
// import "./ACL.sol";
// // import "../Initializable.sol";
// import "./storage/BlockStorage.sol";
// import "./StateManager.sol";
// import "./interface/IStakeManager.sol";
// import "./interface/IJobsManager.sol";
// import "../lib/Structs.sol";

// /**
//  * @title BlockManager
//  * @dev Manages block proposals, confirmations, and rewards in the Lumino Staking System.
//  * This contract handles the lifecycle of blocks within each epoch.
//  */
// contract BlockManager is Initializable, BlockStorage, StateManager, ACL {
//     // Interfaces to interact with other core contracts
//     IStakeManager public stakeManager;
//     IJobsManager public jobsManager;

//     /**
//      * @notice Emitted when a new block is proposed
//      * @param epoch The epoch in which the block was proposed
//      * @param blockId The ID of the proposed block
//      * @param proposer The address of the staker who proposed the block
//      */
//     event BlockProposed(uint32 indexed epoch, uint32 indexed blockId, address proposer);

//     /**
//      * @notice Emitted when a block is confirmed
//      * @param epoch The epoch in which the block was confirmed
//      * @param blockId The ID of the confirmed block
//      */
//     event BlockConfirmed(uint32 indexed epoch, uint32 indexed blockId);

//     /**
//      * @dev Initializes the BlockManager contract.
//      * @param _stakeManager Address of the StakeManager contract
//      * @param _jobsManager Address of the JobsManager contract
//      * @param _minStakeToPropose Minimum stake required to propose a block
//      */
//     function initialize(
//         address _stakeManager,
//         address _jobsManager,
//         uint256 _minStakeToPropose
//     ) external initializer {
//         // Set up connections to other contracts
//         _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
//         stakeManager = IStakeManager(_stakeManager);
//         jobsManager = IJobsManager(_jobsManager);

//         // Initialize the block index to be confirmed
//         blockIndexToBeConfirmed = -1;

//         // TODO: Set minStake here if it's a storage variable
//         minStake = _minStakeToPropose;
//     }

//     /**
//      * @dev Allows a staker to propose a new block for the current epoch.
//      * @param epoch Current epoch number
//      * @param _jobIds Array of job IDs included in the proposed block
//      */
//     function propose(uint32 epoch, uint256[] memory _jobIds)
//     external
//     checkEpochAndState(State.Confirm, epoch, buffer)
//     {
//         // Check if the maximum number of blocks for this epoch has been reached
//         // Eventually to be increased for stakers who are running backup nodes
//         require(numProposedBlocks < MAX_BLOCKS_PER_EPOCH_PER_STAKER, "Max blocks for epoch reached");

//         // Get the staker's ID and perform eligibility checks
//         uint32 stakerId = stakeManager.getStakerId(msg.sender);
//         require(stakerId != 0, "Not a registered staker");
//         require(stakeManager.getStake(stakerId) >= minStake, "Insufficient stake to propose");
//         require(epochLastProposed[stakerId] < epoch, "Already proposed in this epoch");

//         // Find the biggest stake among the jobs
//         uint256 biggestStake = 0;
//         for (uint256 i = 0; i < _jobIds.length; i++) {
//             // Ensure each job is in the Execution state
//             require(jobsManager.getJobStatus(i) == Constants.Status.Execution, "Invalid job status");

//             // Get the stake for this job and update biggestStake if necessary
//             uint256 jobStake = stakeManager.getStake(stakerId);
//             if (jobStake > biggestStake) {
//                 biggestStake = jobStake;
//             }
//         }

//         // Create a new block with the provided information
//         uint32 blockId = uint32(sortedProposedBlockIds[epoch].length + 1);
//         Structs.Block memory newBlock = Structs.Block({
//             valid: true,
//             proposerId: stakerId,
//             jobIds: _jobIds,
//             iteration: 0,
//             biggestStake: biggestStake
//         });

//         // Store the new block and update related data
//         proposedBlocks[epoch][blockId] = newBlock;
//         sortedProposedBlockIds[epoch].push(blockId);
//         numProposedBlocks++;
//         epochLastProposed[stakerId] = epoch;

//         // Emit an event to log the block proposal
//         emit BlockProposed(epoch, blockId, msg.sender);
//     }

//     /**
//      * @dev Confirms a block for the previous epoch.
//      * @param epoch Current epoch number
//      */
//     function confirmBlock(uint32 epoch)
//     external
//     checkEpochAndState(State.Assign, epoch + 1, buffer)
//     {
//         // Ensure there are blocks to confirm and no block has been confirmed yet
//         require(sortedProposedBlockIds[epoch].length > 0, "No blocks proposed in the previous epoch");
//         require(blockIndexToBeConfirmed == -1, "Block already confirmed for this epoch");

//         // Get the first proposed block (assuming it's the one to be confirmed)
//         uint32 blockIdToConfirm = sortedProposedBlockIds[epoch][0];
//         Structs.Block storage blockToConfirm = proposedBlocks[epoch][blockIdToConfirm];

//         // Ensure the block is valid
//         require(blockToConfirm.valid, "Invalid block");

//         // TODO: Add additional validation logic here if needed

//         // Store the confirmed block
//         blocks[epoch] = blockToConfirm;
//         blockIndexToBeConfirmed = 0;

//         // Process rewards for the confirmed block
//         _processRewards(epoch, blockIdToConfirm);

//         // Emit an event to log the block confirmation
//         emit BlockConfirmed(epoch, blockIdToConfirm);
//     }

//     /**
//      * @dev Internal function to process rewards for a confirmed block.
//      * @param epoch Epoch number of the confirmed block
//      * @param blockId ID of the confirmed block
//      */
//     function _processRewards(uint32 epoch, uint32 blockId) internal {
//         Structs.Block storage confirmedBlock = proposedBlocks[epoch][blockId];

//         // TODO: Implement actual reward logic
//         // This might involve calling a function on the stakeManager:
//         // stakeManager.rewardStaker(confirmedBlock.proposerId, calculateProposerReward());

//         // Reset the number of proposed blocks for the next epoch
//         numProposedBlocks = 0;
//     }

//     /**
//      * @dev Calculates the reward for a block proposer.
//      * @return The calculated reward amount
//      */
//     function calculateProposerReward() internal pure returns (uint256) {
//         // TODO: Implement actual reward calculation logic
//         // This is a placeholder returning a fixed amount
//         return 100 * 1e18; // Example: 100 tokens
//     }

//     /**
//      * @dev Calculates the reward for a specific job.
//      * @param jobId ID of the job
//      * @return The calculated reward amount for the job
//      */
//     function calculateJobReward(uint256 jobId) internal view returns (uint256) {
//         // TODO: Implement job-specific reward calculation logic
//         // This might depend on job complexity, duration, or other factors
//         return 50 * 1e18; // Example: 50 tokens per job
//     }

//     /**
//      * @dev Retrieves the confirmed block for a specific epoch.
//      * @param epoch The epoch number
//      * @return The confirmed Block struct for the specified epoch
//      */
//     function getConfirmedBlock(uint32 epoch) external view returns (Structs.Block memory) {
//         return blocks[epoch];
//     }

//     /**
//      * @dev Retrieves a proposed block for a specific epoch and block ID.
//      * @param epoch The epoch number
//      * @param blockId The block ID
//      * @return The proposed Block struct
//      */
//     function getProposedBlock(uint32 epoch, uint32 blockId) external view returns (Structs.Block memory) {
//         return proposedBlocks[epoch][blockId];
//     }

//     /**
//      * @dev Gets the number of proposed blocks for a specific epoch.
//      * @param epoch The epoch number
//      * @return The number of proposed blocks
//      */
//     function getNumProposedBlocks(uint32 epoch) external view returns (uint256) {
//         return sortedProposedBlockIds[epoch].length;
//     }
// }