// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {IIncentiveManager} from "./interfaces/IIncentiveManager.sol";
import {IIncentiveTreasury} from "./interfaces/IIncentiveTreasury.sol";
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
    IIncentiveTreasury internal immutable treasury;

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
        address _stakeEscrow,
        address _treasury
    ) {
        epochManager = IEpochManager(_epochManager);
        leaderManager = ILeaderManager(_leaderManager);
        jobManager = IJobManager(_jobManager);
        nodeManager = INodeManager(_nodeManager);
        stakeEscrow = INodeEscrow(_stakeEscrow);
        treasury = IIncentiveTreasury(_treasury);
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
            treasury.distributeReward(
                leader,
                LShared.LEADER_ASSIGNMENT_REWARD,
                "Leader assignment round completion"
            );
            leaderRewardClaimed[epoch] = true;
        }

        // Reward nodes that revealed secrets
        uint256[] memory revealedNodes = leaderManager.getNodesWhoRevealed(epoch);
        for (uint256 i = 0; i < revealedNodes.length; i++) {
            if (!nodeRewardsClaimed[epoch][revealedNodes[i]]) {
                address nodeOwner = nodeManager.getNodeOwner(revealedNodes[i]);
                treasury.distributeReward(
                    nodeOwner,
                    LShared.SECRET_REVEAL_REWARD,
                    "Secret revelation reward"
                );
                nodeRewardsClaimed[epoch][revealedNodes[i]] = true;
            }
        }

        // Reward disputer
        if (!disputerRewardClaimed[epoch]) {
            treasury.distributeReward(
                msg.sender,
                LShared.DISPUTE_REWARD,
                "Dispute completion reward"
            );
            disputerRewardClaimed[epoch] = true;
        }
    }

    function disputeAll(uint256 epoch) internal {
        validate(epoch);

        // Penalize leader for missing assignments
        address leader = nodeManager.getNodeOwner(leaderManager.getCurrentLeader());
        if (!jobManager.wasAssignmentRoundStarted(epoch)) {
            treasury.applyPenalty(
                leader,
                LShared.MISSED_ASSIGNMENT_PENALTY,
                "Missed assignment round"
            );
            if (incrementPenalty(leader)) {
                slashCP(leader);
            }
        }

        // Penalize nodes that didn't confirm assigned jobs
        uint256[] memory unconfirmedJobs = jobManager.getUnconfirmedJobs(epoch);
        for (uint256 i = 0; i < unconfirmedJobs.length; i++) {
            address nodeOwner = nodeManager.getNodeOwner(jobManager.getAssignedNode(unconfirmedJobs[i]));
            treasury.applyPenalty(
                nodeOwner,
                LShared.MISSED_CONFIRMATION_PENALTY,
                "Missed job confirmation"
            );
            if (incrementPenalty(nodeOwner)) {
                slashCP(nodeOwner);
            }
        }
    }

    function validate(uint256 epoch) internal {
        require(!processedEpochs[epoch], "Epoch already processed");
        require(epoch < epochManager.getCurrentEpoch(), "Cannot process current epoch");
        processedEpochs[epoch] = true;
    }

    function slashCP(address cp) internal {
        uint256 totalStake = stakeEscrow.getBalance(cp);
        stakeEscrow.applyPenalty(cp, totalStake);
    }

    function incrementPenalty(address cp) internal returns (bool shouldSlash) {
        penaltyCount[cp]++;
        return penaltyCount[cp] >= LShared.MAX_PENALTIES_BEFORE_SLASH;
    }
}