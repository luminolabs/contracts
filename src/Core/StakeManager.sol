// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./storage/StakeManagerStorage.sol";
import "./StateManager.sol";


/** @title StakeManager
 * @notice StakeManager handles stake, unstake, withdraw, reward, functions
 * for stakers
 */

contract StakeManager is StakeManagerStorage, StateManager {
   
    // IVoteManager public voteManager;
    // IERC20 public lumino;

    //  A staker can stake in any state
    //  An ERC20 token($LUMINO) is staked and locked by a staker in the Contract
    //  param1: epoch, The Epoch value for which staker is requesting to stake
    //  param2: amount, The amount in LUM
    function stake(uint32 epoch, uint256 amount) external checkEpoch(epoch) {
        uint32 stakerId = stakerIds[msg.sender];
        
        // first time stakers would have stakerId as 0
        if (stakerId == 0) {
            // require();
        } else {

        }
    }

}