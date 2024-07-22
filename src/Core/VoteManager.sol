// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./ACL.sol";
import "./storage/VoteManagerStorage.sol";
import "./StateManager.sol";
import "./StakeManager.sol";
import "./interface/IStakeManager.sol";
import "../Initializable.sol";

/** @title VoteManager
 * @notice VoteManager handles commit, reveal, voting,
 * snapshots and salt for the network
 */

contract VoteManager is Initializable, VoteManagerStorage, StateManager, ACL {
    // IStakeManager public stakeManager;
    // IERC20 public lumino;
    IStakeManager public stakeManager;

    function initialize(
        address stakeManagerAddress,
        address blockManagerAddress
    ) external initializer hasRole(DEFAULT_ADMIN_ROLE, msg.sender) {
        stakeManager = IStakeManager(stakeManagerAddress);
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

    /**
     * @notice staker reveal the jobs that they had committed to the protocol in the commit state.
     * Stakers would only reveal the jobs they have been allocated
     * @dev stakers would need to submit their commitments/votes in accordance of how they were assigned to the staker.
     * for example, if they are assigned the following job ids: [2,5,4], they would to send their reveal votes in the same order only
     * // The votes of other ids dont matter but they should not be passed in the values.
     * So staker would have to pass the proof path of the assigned values of the merkle tree, root of the merkle tree and
     * the values being revealed into a struct in the Structs.MerkleTree format.
     * @param epoch epoch when the revealed their votes
     * @param tree the merkle tree struct of the staker
     * @param signature staker's signature on the messageHash which calculates
     * the secret using which seed would be calculated and thereby checking for collection allocation
     */
    function reveal(
        uint32 epoch,
        Structs.MerkleTree memory tree,
        bytes memory signature
    ) external initialized checkEpochAndState(State.Reveal, epoch, buffer) {
        uint32 stakerId = stakeManager.getStakerId(msg.sender);
        
    }
}