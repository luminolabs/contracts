// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Constants {
    enum State {
        Commit,
        Reveal,
        Propose,
        Buffer
    }

    enum Status {
        Create,
        Execution,
        ProofCreation,
        Completed
    }

    //  total number of states
    uint8 public constant NUM_STATES = 3;
    //  length of epoch in seconds
    uint16 public constant EPOCH_LENGTH = 1200;
    // minimum amount of stake required to become a staker
    uint256 public minStake = 20000 * (10 ** 18);
    // minimum amount of stake required to become a staker
    uint256 public minSafeLumToken = 10000 * (10 ** 18);
    uint8 public buffer = 5;
    // the number of epochs for which the stake is locked for calling unstake()
    uint16 public unstakeLockPeriod = 1;

}
