// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "./ACL.sol";
import "./storage/VoteManagerStorage.sol";
import "./StateManager.sol";
import "./StakeManager.sol";
import "./JobsManager.sol";
import "./interface/IStakeManager.sol";
import "./interface/IJobsManager.sol";
import "../Initializable.sol";

/** @title VoteManager
 * @notice VoteManager handles commit, reveal, voting,
 * snapshots and salt for the network
 */

contract VoteManager is Initializable, VoteManagerStorage, StateManager, ACL {
    // IStakeManager public stakeManager;
    // IERC20 public lumino;
    IStakeManager public stakeManager;
    IJobsManager public jobsManager;

    function initialize(
        address stakeManagerAddress,
        address jobsManagerAddress
        // address blockManagerAddress
    ) external initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        stakeManager = IStakeManager(stakeManagerAddress);
        jobsManager = IJobsManager(jobsManagerAddress);
        // blockManager = IBlockManager(blockManagerAddress);
    }

    /**
     * @notice Allows stakers to commit to a job by submitting a hash of their results instead of revealing them immediately.
     * @dev The commitment process involves the following steps:
     * // The staker constructs a Merkle tree of their results.
     * Commitment is created by hashing the Merkle root with a seed (hash of salt and staker's secret).
     * Job allocation is determined using the seed, allowing stakers to know their assignments at commit time.
     * Stakers should only perform assigned jobs, setting results for unassigned jobs to 0.
     * Before registering the commitment, the staker confirms the previous epoch's block if needed.
     * Block rewards and penalties are applied based on previous epoch activity and votes.
     *
     * @param epoch The epoch for which the commitment is being made
     * @param commitment The hashed commitment (Merkle root + seed)
     */
    function commit(
        uint32 epoch,
        bytes32 commitment
    ) external checkEpochAndState(State.Commit, epoch, buffer) {
        require(commitment != 0x0, "Invalid commitment");
        uint32 stakerId = stakeManager.getStakerId(msg.sender);
        require(
            !stakeManager.getStaker(stakerId).isSlashed,
            "staker is slashed"
        );
        require(stakerId > 0, "Staker does not exist");
        require(commitments[stakerId].epoch != epoch, "already commited");
        // Switch to call confirm block only when block in previous epoch has not been confirmed
        // and if previous epoch do have proposed blocks
        // if (!blockManager.isBlockConfirmed(epoch - 1)) {
        //     blockManager.confirmPreviousEpochBlock(stakerId);
        // }
        // stakeManager.givePenalties(epoch, stakerId);
        uint256 thisStakerStake = stakeManager.getStake(stakerId);
        if (thisStakerStake >= minStake) {
            commitments[stakerId].epoch = epoch;
            commitments[stakerId].commitmentHash = commitment;
        }
    }

    function reveal(
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes memory signature
    ) external initialized checkEpochAndState(State.Reveal, epoch, buffer) {
        uint32 stakerId = stakeManager.getStakerId(msg.sender);
        require(stakerId > 0, "Staker does not exist");
        require(
            commitments[stakerId].epoch == epoch,
            "Not committed in this epoch"
        );
        require(!commitments[stakerId].revealed, "Already revealed");
        // number of Jobs tobeAssigned or assigned
        // require(results.length == toAssign, "Incorrect number of job results");

        bytes32 seed = _verifySeedAndCommitment(
            stakerId,
            epoch,
            results,
            signature
        );

        _processResults(stakerId, epoch, results, seed);

        commitments[stakerId].revealed = true;
        epochLastRevealed[stakerId] = epoch;

    }

    function _verifySeedAndCommitment(
        uint32 stakerId,
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes memory signature
    ) internal view returns (bytes32) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, epoch, block.chainid, "luminoprotocol")
        );
        require(
            ECDSA.recover(
                MessageHashUtils.toEthSignedMessageHash(messageHash),
                signature
            ) == msg.sender,
            "Invalid signature"
        );

        bytes32 secret = keccak256(signature);
        bytes32 seed = keccak256(abi.encode(salt, secret));
        bytes32 resultsHash = keccak256(abi.encode(results, seed));
        require(
            resultsHash == commitments[stakerId].commitmentHash,
            "Incorrect results or seed"
        );

        return seed;
    }

    function _processResults(
        uint32 stakerId,
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes32 seed
    ) internal {
        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        for (uint16 i = 0; i < results.length; i++) {
            require(
                _isJobAllotedToStaker(
                    seed,
                    i,
                    activeJobs.length,
                    results[i].jobId
                ),
                "Revealed job not allotted"
            );
            require(
                results[i].resultHash != bytes32(0),
                "Empty result for assigned job"
            );
            assignedJob[epoch][stakerId].push(
                Structs.AssignedJob(results[i].jobId, results[i].resultHash)
            );
        }
    }

    function _isJobAllotedToStaker(
        bytes32 seed,
        uint16 index,
        uint256 totalJobs,
        uint256 jobId
    ) internal pure returns (bool) {
        return
            uint256(keccak256(abi.encodePacked(seed, index))) % totalJobs ==
            jobId;
    }


    // for possible future upgrades
    uint256[50] private __gap;
}
