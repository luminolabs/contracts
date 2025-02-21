// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {IIncentiveManager} from "./interfaces/IIncentiveManager.sol";
import {IJobManager} from "./interfaces/IJobManager.sol";
import {ILeaderManager} from "./interfaces/ILeaderManager.sol";
import {INodeEscrow} from "./interfaces/INodeEscrow.sol";
import {INodeManager} from "./interfaces/INodeManager.sol";
import {LShared} from "./libraries/LShared.sol";

contract IncentiveManager is IIncentiveManager {
    // Contracts
    IEpochManager internal immutable epochManager;
    ILeaderManager internal immutable leaderManager;
    IJobManager internal immutable jobManager;
    INodeManager internal immutable nodeManager;
    INodeEscrow internal immutable nodeEscrow;

    // State variables
    mapping(address => uint256) public penaltyCount;
    mapping(uint256 => bool) public processedEpochs;
    mapping(uint256 => mapping(uint256 => bool)) private nodeRewardsClaimed;
    mapping(uint256 => bool) private leaderRewardClaimed;
    mapping(uint256 => bool) private disputerRewardClaimed;

    constructor(
        address _epochManager,
        address _leaderManager,
        address _jobManager,
        address _nodeManager,
        address _stakeEscrow
    ) {
        epochManager = IEpochManager(_epochManager);
        leaderManager = ILeaderManager(_leaderManager);
        jobManager = IJobManager(_jobManager);
        nodeManager = INodeManager(_nodeManager);
        nodeEscrow = INodeEscrow(_stakeEscrow);
    }

    /**
     * @notice Process all rewards and penalties for an epoch
     */
    function processAll() external {
        uint256 epoch = epochManager.getCurrentEpoch();

        // Validate that epoch hasn't been processed yet
        validate(epoch);
        // Dispute first so that disputer can be rewarded
        disputeAll(epoch);
        // Then reward all
        rewardAll(epoch);
    }

    // Internal functions

    function rewardAll(uint256 epoch) internal {
        // Reward leader for assignments
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        if (!leaderRewardClaimed[epoch] && jobManager.wasAssignmentRoundStarted(epoch)) {
            nodeEscrow.applyReward(
                leader,
                LShared.LEADER_REWARD,
                "Leader assignment round completion"
            );
            leaderRewardClaimed[epoch] = true;
            emit LeaderRewardApplied(epoch, leader, LShared.LEADER_REWARD);
        }

        // Reward nodes that revealed secrets
        uint256[] memory revealedNodes = leaderManager.getNodesWhoRevealed(epoch);
        for (uint256 i = 0; i < revealedNodes.length; i++) {
            if (!nodeRewardsClaimed[epoch][revealedNodes[i]]) {
                address nodeOwner = nodeManager.getNodeOwner(revealedNodes[i]);
                nodeEscrow.applyReward(
                    nodeOwner,
                    LShared.JOB_AVAILABILITY_REWARD,
                    "Job availability reward"
                );
                nodeRewardsClaimed[epoch][revealedNodes[i]] = true;
                emit JobAvailabilityRewardApplied(epoch, revealedNodes[i], LShared.JOB_AVAILABILITY_REWARD);
            }
        }

        // Reward disputer
        if (!disputerRewardClaimed[epoch]) {
            nodeEscrow.applyReward(
                msg.sender,
                LShared.DISPUTER_REWARD,
                "Disputer reward"
            );
            disputerRewardClaimed[epoch] = true;
            emit DisputerRewardApplied(epoch, msg.sender, LShared.DISPUTER_REWARD);
        }
    }

    function disputeAll(uint256 epoch) internal {
        // Penalize leader for missing assignments
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        if (!jobManager.wasAssignmentRoundStarted(epoch)) {
            nodeEscrow.applyPenalty(
                leader,
                LShared.LEADER_NOT_EXECUTED_PENALTY,
                "Leader didn't execute assignments"
            );
            if (incrementPenalty(leader)) {
                slashCP(leader, "Exceeded maximum penalties");
            }
            emit LeaderNotExecutedPenaltyApplied(epoch, leader, LShared.LEADER_NOT_EXECUTED_PENALTY);
        }

        // Penalize nodes that didn't confirm assigned jobs
        uint256[] memory unconfirmedJobs = jobManager.getUnconfirmedJobs(epoch);
        for (uint256 i = 0; i < unconfirmedJobs.length; i++) {
            address nodeOwner = nodeManager.getNodeOwner(jobManager.getAssignedNode(unconfirmedJobs[i]));
            nodeEscrow.applyPenalty(
                nodeOwner,
                LShared.JOB_NOT_CONFIRMED_PENALTY,
                "Node didn't confirm job"
            );
            if (incrementPenalty(nodeOwner)) {
                slashCP(nodeOwner, "Exceeded maximum penalties");
            }
            emit JobNotConfirmedPenaltyApplied(epoch, unconfirmedJobs[i], LShared.JOB_NOT_CONFIRMED_PENALTY);
        }
    }

    function validate(uint256 epoch) internal {
        if (processedEpochs[epoch]) {
            revert EpochAlreadyProcessed(epoch);
        }
        processedEpochs[epoch] = true;
    }

    function slashCP(address cp, string memory reason) internal {
        nodeEscrow.applySlash(cp, reason);
    }

    function incrementPenalty(address cp) internal returns (bool shouldSlash) {
        penaltyCount[cp]++;
        return penaltyCount[cp] >= LShared.MAX_PENALTIES_BEFORE_SLASH;
    }
}