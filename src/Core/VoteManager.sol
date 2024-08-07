// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./storage/VoteManagerStorage.sol";
import "./StateManager.sol";
import "./StakeManager.sol";
import "./JobsManager.sol";
import "./interface/IStakeManager.sol";
import "./interface/IJobsManager.sol";
import "./ACL.sol";

/**
 * @title VoteManager
 * @dev Manages the voting process, including commit and reveal phases, for the Lumino Staking System.
 * This contract handles the core voting mechanics and result verification.
 */
contract VoteManager is Initializable, VoteManagerStorage, StateManager, ACL {
    IStakeManager public stakeManager;
    IJobsManager public jobsManager;

    /**
     * @dev Initializes the VoteManager contract.
     * @param stakeManagerAddress Address of the StakeManager contract
     * @param jobsManagerAddress Address of the JobsManager contract
     */
    function initialize(
        address stakeManagerAddress,
        address jobsManagerAddress
    ) external initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stakeManager = IStakeManager(stakeManagerAddress);
        jobsManager = IJobsManager(jobsManagerAddress);
    }

    /**
     * @dev Allows stakers to commit their votes for an epoch.
     * @param epoch The epoch for which the commitment is being made
     * @param commitment The hashed commitment (Merkle root + seed)
     */
    function commit(
        uint32 epoch,
        bytes32 commitment
    ) external checkEpochAndState(State.Commit, epoch, buffer) {
        require(commitment != bytes32(0), "Invalid commitment");

        uint32 stakerId = stakeManager.getStakerId(msg.sender);
        require(stakerId > 0, "Staker does not exist");
        require(!stakeManager.getStaker(stakerId).isSlashed, "Staker is slashed");
        require(commitments[stakerId].epoch != epoch, "Already committed for this epoch");

        uint256 stakerStake = stakeManager.getStake(stakerId);
        if (stakerStake >= minStake) {
            commitments[stakerId].epoch = epoch;
            commitments[stakerId].commitmentHash = commitment;
        }
    }

    /**
     * @dev Allows stakers to reveal their votes for an epoch.
     * @param epoch The epoch for which the reveal is being made
     * @param results Array of JobVerifier structs containing job results
     * @param signature The staker's signature for verification
     */
    function reveal(
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes memory signature
    ) external checkEpochAndState(State.Reveal, epoch, buffer) {
        uint32 stakerId = stakeManager.getStakerId(msg.sender);
        require(stakerId > 0, "Staker does not exist");
        require(commitments[stakerId].epoch == epoch, "Not committed in this epoch");
        require(!commitments[stakerId].revealed, "Already revealed");

        bytes32 seed = _verifySeedAndCommitment(stakerId, epoch, results, signature);

        _processResults(stakerId, epoch, results, seed);

        commitments[stakerId].revealed = true;
        epochLastRevealed[stakerId] = epoch;
    }

    /**
     * @dev Verifies the staker's seed and commitment.
     * @param stakerId The ID of the staker
     * @param epoch The current epoch
     * @param results Array of JobVerifier structs containing job results
     * @param signature The staker's signature
     * @return The verified seed
     */
    function _verifySeedAndCommitment(
        uint32 stakerId,
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes memory signature
    ) internal view returns (bytes32) {
        // Create a message hash for signature verification
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, epoch, block.chainid, "luminoprotocol")
        );

        // Verify the signature
        require(
            ECDSA.recover(
                MessageHashUtils.toEthSignedMessageHash(messageHash),
                signature
            ) == msg.sender,
            "Invalid signature"
        );

        // Generate the seed from the signature
        bytes32 secret = keccak256(signature);
        bytes32 seed = keccak256(abi.encode(salt, secret));

        // Verify the commitment
        bytes32 resultsHash = keccak256(abi.encode(results, seed));
        require(
            resultsHash == commitments[stakerId].commitmentHash,
            "Incorrect results or seed"
        );

        return seed;
    }

    /**
     * @dev Processes the revealed results for a staker.
     * @param stakerId The ID of the staker
     * @param epoch The current epoch
     * @param results Array of JobVerifier structs containing job results
     * @param seed The verified seed
     */
    function _processResults(
        uint32 stakerId,
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes32 seed
    ) internal {
        uint256[] memory activeJobs = jobsManager.getActiveJobs();
        for (uint16 i = 0; i < results.length; i++) {
            require(
                _isJobAllotedToStaker(seed, i, activeJobs.length, results[i].jobId),
                "Revealed job not allotted"
            );
            require(results[i].resultHash != bytes32(0), "Empty result for assigned job");

            assignedJobs[epoch][stakerId].push(
                Structs.AssignedJob(results[i].jobId, results[i].resultHash)
            );
        }
    }

    /**
     * @dev Checks if a job was allotted to a staker based on the seed.
     * @param seed The verified seed
     * @param index The index of the job in the results array
     * @param totalJobs The total number of active jobs
     * @param jobId The ID of the job to check
     * @return Boolean indicating if the job was allotted to the staker
     */
    function _isJobAllotedToStaker(
        bytes32 seed,
        uint16 index,
        uint256 totalJobs,
        uint256 jobId
    ) internal pure returns (bool) {
        return uint256(keccak256(abi.encodePacked(seed, index))) % totalJobs == jobId;
    }

    // for possible future upgrades
    uint256[50] private __gap;
}
