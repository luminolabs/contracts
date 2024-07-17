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

    /** 
    *  @dev A staker can call stake() in any state
    *  An ERC20 token($LUMINO) is staked and locked by a staker in the Contract
    *  @param _epoch The Epoch value for which staker is requesting to stake
    *  @param _amount The amount in LUM
    *  @param _machineSpecInJSON JSON object for machineSpec
    */
   function stake(uint32 _epoch, uint256 _amount, string memory _machineSpecInJSON) external checkEpoch(_epoch) {
        uint32 stakerId = stakerIds[msg.sender];
        
        // first time stakers would have stakerId as 0
        if (stakerId == 0) {
            require(_amount >= minSafeLumToken, "less than minimum safe lumino token");
            numStakers = numStakers + (1);
            stakerId = numStakers;
            stakerIds[msg.sender] = stakerId;
            stakers[numStakers] = Structs.Staker(false, msg.sender, numStakers, 0, _epoch, 0, _amount, 0, _machineSpecInJSON);
        } else {
            require(!stakers[stakerId].isSlashed, "staker is slashed");
            stakers[stakerId].stake = stakers[stakerId].stake + (_amount);
        }
    }

    
    /**
     * @dev staker must call unstake() to lock their luminoTokens
     * and should wait for params.unlock_After period
     * after which he/she can call Withdraw() after unstakeLockPeriod
     * @param _stakerId The Id of staker associated with sRZR which user want to unstake
     * @param _amount The Amount in sRZR
     */
    function unstake(uint32 _stakerId, uint256 _amount) external {
        require(_stakerId != 0, "stakerId cannot be 0");
        require(stakers[_stakerId].stake > 0, "Non-positive stake");
        require(locks[msg.sender].amount == 0, "Existing Unstake Lock");

        uint32 epoch = getEpoch();

        locks[msg.sender] = Structs.Lock(_amount, epoch + unstakeLockPeriod);
    }

    /**
     * @notice staker can claim their locked $LUMINO tokens.
     * @param _stakerId The Id of staker
     */
    function withdraw(uint32 _stakerId) external {

        uint32 epoch = getEpoch();        
        require(_stakerId != 0, "staker doesn't exist");

        // Structs.Staker storage staker = stakers[_stakerId];
        Structs.Lock storage lock = locks[msg.sender];

        require(lock.unlockAfter != 0, "Did not Unstake");
        require(lock.unlockAfter <= epoch, "Withdraw epoch not reached");

        // uint256 withdrawAmount = lock.amount;

        _resetLock(_stakerId);

        // require(lumino.transfer(msg.sender, withdrawAmount));
        
    }

    /**
     * @notice a private function being called when the staker
     * successfully withdraws his funds from the network. This is
     * being done so that the staker can unstake and withdraw his remaining funds
     * incase of partial unstake
     * @param _stakerId Id of the staker for whose lock is being reset
     */
    function _resetLock(uint32 _stakerId) private {
        locks[stakers[_stakerId]._address] = Structs.Lock({amount: 0, unlockAfter: 0});
    }

}