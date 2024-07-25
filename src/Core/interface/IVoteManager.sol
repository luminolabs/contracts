// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

interface IVoteManager {

    // Functions
    function initialize(
        address stakeManagerAddress,
        address jobsManagerAddress,
        address blockManagerAddress
    ) external;

    function commit(uint32 epoch, bytes32 commitment) external;

    function reveal(
        uint32 epoch,
        Structs.JobVerifier[] memory results,
        bytes memory signature
    ) external;

    // View functions
    function getCommitment(uint32 stakerId) external view returns (Structs.Commitment memory);

    function getEpochLastRevealed(uint32 stakerId) external view returns (uint32);

    function getSalt() external view returns (bytes32);

    function getAssignedJobs(uint32 epoch, uint32 stakerId) external view returns (Structs.AssignedJob[] memory);

    // function hasCommitted(uint32 epoch, uint32 stakerId) external view returns (bool);
    
    // function hasRevealed(uint32 epoch, uint32 stakerId) external view returns (bool);
}