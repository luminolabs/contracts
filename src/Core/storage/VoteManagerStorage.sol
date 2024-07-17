// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Constants.sol";

contract VoteManagerStorage is Constants {
    
    struct Commitment {
        uint32 epoch;
        bytes32 commitmentHash;
    }

    struct Job {
        uint256 jobId;
        address creator;
        address assignee;
        Status jobStatus;
        string jobDetailsInJSON;
    }
}