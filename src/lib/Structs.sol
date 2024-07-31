// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Structs {
    struct Staker {
        bool isSlashed;
        address _address;
        // address tokenAddress;
        uint32 id;
        uint32 age;
        uint32 epochFirstStaked;
        uint32 epochLastPenalized;
        uint256 stake;
        uint256 stakerReward;
        string machineSpecInJSON;
    }

    struct Lock {
        uint256 amount;
        uint256 unlockAfter;
    }

    struct Commitment {
        uint32 epoch;
        bytes32 commitmentHash;
        bool revealed;
    }
    
    struct Job {
        uint256 jobId;
        address creator;
        address assignee;
        uint32 creationEpoch;
        uint32 executionEpoch;
        uint32 completionEpoch;
        string jobDetailsInJSON;
    }
    struct JobVerifier {
        uint256 jobId;
        bytes32 resultHash;
    }
    //tbd
    struct AssignedJob {
        uint256 jobId;
        bytes32 resultHash;
    }

    struct MerkleTree {
        // better name for this
        Structs.AssignedJob[] values;
        bytes32[][] proofs;
        bytes32 root;
    }

    struct Block {
        bool valid;
        uint32 proposerId;
        // some fields TBD
        uint256[] jobIds;
        uint256 iteration;
        uint256 biggestStake;
    }
}
