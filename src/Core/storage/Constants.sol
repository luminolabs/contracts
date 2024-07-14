// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Constants {
    enum State {
        Commit,
        Reveal,
        Propose,
        Buffer
    }

    // total number of states
    uint8 public constant NUM_STATES = 3;

    uint16 public constant EPOCH_LENGTH = 1200;
}