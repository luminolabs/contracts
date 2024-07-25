// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./ACL.sol";
import "../Initializable.sol";
import "./storage/BlockStorage.sol";
import "./StateManager.sol";
import "./interface/IStakeManager.sol";

contract BlockManager is Initializable, BlockStorage, StateManager {
    IStakeManager public stakeManager;
    // IVoteManager public voteManager;

}