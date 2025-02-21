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
    INodeEscrow internal immutable stakeEscrow;

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
        stakeEscrow = INodeEscrow(_stakeEscrow);
    }

    /**
     * @notice Process all rewards and penalties for an epoch
     */
    function processAll(uint256 epoch) external {
        // Validate epoch
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
            stakeEscrow.applyReward(
                leader,
                LShared.LEADER_ASSIGNMENT_REWARD,
                "Leader assignment round completion"
            );
            leaderRewardClaimed[epoch] = true;
        }
        emit LeaderRewardApplied(epoch, leader, LShared.LEADER_ASSIGNMENT_REWARD);

        // Reward nodes that revealed secrets
        uint256[] memory revealedNodes = leaderManager.getNodesWhoRevealed(epoch);
        for (uint256 i = 0; i < revealedNodes.length; i++) {
            if (!nodeRewardsClaimed[epoch][revealedNodes[i]]) {
                address nodeOwner = nodeManager.getNodeOwner(revealedNodes[i]);
                stakeEscrow.applyReward(
                    nodeOwner,
                    LShared.SECRET_REVEAL_REWARD,
                    "Secret revelation reward"
                );
                nodeRewardsClaimed[epoch][revealedNodes[i]] = true;
            }
        }
        emit NodeRewardApplied(epoch, revealedNodes, LShared.SECRET_REVEAL_REWARD);

        // Reward disputer
        if (!disputerRewardClaimed[epoch]) {
            stakeEscrow.applyReward(
                msg.sender,
                LShared.DISPUTE_REWARD,
                "Dispute completion reward"
            );
            disputerRewardClaimed[epoch] = true;
        }
        emit DisputerRewardApplied(epoch, msg.sender, LShared.DISPUTE_REWARD);
    }

    function disputeAll(uint256 epoch) internal {
        // Penalize leader for missing assignments
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        if (!jobManager.wasAssignmentRoundStarted(epoch)) {
            stakeEscrow.applyPenalty(
                leader,
                LShared.MISSED_ASSIGNMENT_PENALTY,
                "Missed assignment round"
            );
            if (incrementPenalty(leader)) {
                slashCP(leader, "Exceeded maximum penalties");
            }
        }
        emit LeaderPenaltyApplied(epoch, leader, LShared.MISSED_ASSIGNMENT_PENALTY);

        // Penalize nodes that didn't confirm assigned jobs
        uint256[] memory unconfirmedJobs = jobManager.getUnconfirmedJobs(epoch);
        for (uint256 i = 0; i < unconfirmedJobs.length; i++) {
            address nodeOwner = nodeManager.getNodeOwner(jobManager.getAssignedNode(unconfirmedJobs[i]));
            stakeEscrow.applyPenalty(
                nodeOwner,
                LShared.MISSED_CONFIRMATION_PENALTY,
                "Missed job confirmation"
            );
            if (incrementPenalty(nodeOwner)) {
                slashCP(nodeOwner, "Exceeded maximum penalties");
            }
        }
        emit NodePenaltyApplied(epoch, unconfirmedJobs, LShared.MISSED_CONFIRMATION_PENALTY);
    }

    function validate(uint256 epoch) internal {
        if (processedEpochs[epoch]) {
            revert EpochAlreadyProcessed(epoch);
        }
        uint256 current_epoch = epochManager.getCurrentEpoch();
        if (epoch != current_epoch) {
            revert CanOnlyProcessCurrentEpoch(epoch, current_epoch);
        }
        processedEpochs[epoch] = true;
    }

    function slashCP(address cp, string memory reason) internal {
        stakeEscrow.applySlash(cp, reason);
    }

    function incrementPenalty(address cp) internal returns (bool shouldSlash) {
        penaltyCount[cp]++;
        return penaltyCount[cp] >= LShared.MAX_PENALTIES_BEFORE_SLASH;
    }
}