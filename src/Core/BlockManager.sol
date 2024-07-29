// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./ACL.sol";
import "../Initializable.sol";
import "./storage/BlockStorage.sol";
import "./StateManager.sol";
import "./interface/IStakeManager.sol";
import "./interface/IJobsManager.sol";
import "./interface/IVoteManager.sol";
import "../lib/Structs.sol";

contract BlockManager is Initializable, BlockStorage, StateManager, ACL {
    IStakeManager public stakeManager;
    IJobsManager public jobsManager;
    IVoteManager public voteManager;

    event BlockProposed(
        uint32 indexed epoch,
        uint32 indexed blockId,
        address proposer
    );
    event BlockConfirmed(uint32 indexed epoch, uint32 indexed blockId);

    function initialize(
        address _stakeManager,
        address _jobsManager,
        address _voteManager,
        uint256 _minStakeToPropose
    ) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stakeManager = IStakeManager(_stakeManager);
        jobsManager = IJobsManager(_jobsManager);
        voteManager = IVoteManager(_voteManager);
        blockIndexToBeConfirmed = -1;
    }

    // refine the logic while functional testing
    // for now it is flawed
    function propose(
        uint32 epoch,
        uint256[] memory _jobIds
    ) external checkEpochAndState(State.Propose, epoch, buffer) {
        require(
            numProposedBlocks < MAX_BLOCKS_PER_EPOCH_PER_STAKER,
            "Max blocks for epoch reached"
        );

        uint32 stakerId = stakeManager.getStakerId(msg.sender);
        require(stakerId != 0, "Not a registered staker");
        require(
            stakeManager.getStake(stakerId) >= minStake,
            "Insufficient stake to propose"
        );
        require(
            epochLastProposed[stakerId] < epoch,
            "Already proposed in this epoch"
        );

        uint256 biggestStake = 0;
        for (uint256 i = 0; i < _jobIds.length; i++) {
            require(
                jobsManager.getJobStatus(i) == Constants.Status.Execution,
                "Invalid job status"
            );
            uint256 jobStake = stakeManager.getStake(stakerId);
            if (jobStake > biggestStake) {
                biggestStake = jobStake;
            }
        }

        uint32 blockId = uint32(sortedProposedBlockIds[epoch].length + 1);
        Structs.Block memory newBlock = Structs.Block({
            valid: true,
            proposerId: stakerId,
            jobIds: _jobIds,
            iteration: 0,
            biggestStake: biggestStake
        });

        proposedBlocks[epoch][blockId] = newBlock;
        sortedProposedBlockIds[epoch].push(blockId);
        numProposedBlocks++;
        epochLastProposed[stakerId] = epoch;

        emit BlockProposed(epoch, blockId, msg.sender);
    }

    function confirmBlock(
        uint32 epoch
    ) external checkEpochAndState(State.Commit, epoch + 1, buffer) {
        require(
            sortedProposedBlockIds[epoch].length > 0,
            "No blocks proposed in the previous epoch"
        );
        require(
            blockIndexToBeConfirmed == -1,
            "Block already confirmed for this epoch"
        );

        uint32 blockIdToConfirm = sortedProposedBlockIds[epoch][0];
        Structs.Block storage blockToConfirm = proposedBlocks[epoch][
            blockIdToConfirm
        ];

        require(blockToConfirm.valid, "Invalid block");

        // Additional validation logic can be added here

        blocks[epoch] = blockToConfirm;
        blockIndexToBeConfirmed = 0;

        // Process rewards for the confirmed block
        _processRewards(epoch, blockIdToConfirm);

        emit BlockConfirmed(epoch, blockIdToConfirm);
    }

    // to be implmented while functional testing
    function _processRewards(uint32 epoch, uint32 blockId) internal {
        Structs.Block storage confirmedBlock = proposedBlocks[epoch][blockId];

        // Reward the block proposer
        // stakeManager.rewardStaker(confirmedBlock.proposerId, calculateProposerReward());
        // Reset numProposedBlocks for the next epoch
        numProposedBlocks = 0;
    }

    function calculateProposerReward() internal pure returns (uint256) {
        return 100 * 1e18;
    }

    function calculateJobReward(uint256 jobId) internal view returns (uint256) {
        // Implement your job reward calculation logic
        // This would depend on job complexity, duration, etc.
        return 50 * 1e18; // Example: 50 tokens per job
    }

    function getConfirmedBlock(
        uint32 epoch
    ) external view returns (Structs.Block memory) {
        return blocks[epoch];
    }

    function getProposedBlock(
        uint32 epoch,
        uint32 blockId
    ) external view returns (Structs.Block memory) {
        return proposedBlocks[epoch][blockId];
    }

    function getNumProposedBlocks(
        uint32 epoch
    ) external view returns (uint256) {
        return sortedProposedBlockIds[epoch].length;
    }
}
