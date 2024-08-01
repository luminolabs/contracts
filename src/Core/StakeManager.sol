// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import "./storage/StakeManagerStorage.sol";
import "./StateManager.sol";
import "./interface/IVoteManager.sol";
import "./ACL.sol";

/**
 * @title StakeManager
 * @dev Manages staking, unstaking, withdrawing, and rewarding functions for stakers in the Lumino network.
 * This contract handles the core staking mechanics of the system.
 */

contract StakeManager is Initializable, StakeManagerStorage, StateManager, ACL {
    IVoteManager public voteManager;
    // TODO: Uncomment and implement these interfaces when ready
    // IERC20 public lumino;

    function initialize(address _voteManagerAddress) public initializer override {
        // Initialize contract state here
        // lumino = IERC20(_luminoAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        voteManager = IVoteManager(_voteManagerAddress);
    }

    /**
     * @dev Allows a user to stake $LUMINO tokens in the network.
     * @param _epoch The epoch for which the staker is requesting to stake
     * @param _amount The amount of $LUMINO tokens to stake
     * @param _machineSpecInJSON JSON object describing the staker's machine specifications
     */
    function stake(
        uint32 _epoch,
        uint256 _amount,
        string memory _machineSpecInJSON
    ) external checkEpoch(_epoch) {
        uint32 stakerId = stakerIds[msg.sender];

        if (stakerId == 0) {
            // First-time staker
            require(_amount >= minSafeLumToken, "Less than minimum safe LUMINO token amount");

            // Increment the total number of stakers
            numStakers = numStakers + 1;
            stakerId = numStakers;

            // Associate the staker's address with their new ID
            stakerIds[msg.sender] = stakerId;

            // Create a new Staker struct for the new staker
            stakers[numStakers] = Structs.Staker({
                isSlashed: false,
                _address: msg.sender,
                id: numStakers,
                age: 0,
                epochFirstStaked: _epoch,
                epochLastPenalized: 0,
                stake: _amount,
                stakerReward: 0,
                machineSpecInJSON: _machineSpecInJSON
            });
        } else {
            // Existing staker
            require(!stakers[stakerId].isSlashed, "Staker is slashed");

            // Increase the staker's existing stake
            stakers[stakerId].stake = stakers[stakerId].stake + _amount;
        }

        // TODO: Transfer LUMINO tokens from the staker to this contract
        // require(lumino.transferFrom(msg.sender, address(this), _amount), "Token transfer failed");
    }

    /**
     * @dev Initiates the unstaking process for a staker.
     * @param _stakerId The ID of the staker who wants to unstake
     * @param _amount The amount of $LUMINO tokens to unstake
     */
    function unstake(uint32 _stakerId, uint256 _amount) external {
        require(_stakerId != 0, "Invalid staker ID");
        require(stakers[_stakerId].stake > 0, "No stake to unstake");
        require(locks[msg.sender].amount == 0, "Existing unstake lock");

        require(stakers[_stakerId]._address == msg.sender, "Can only unstake your own funds");
        require(stakers[_stakerId].stake >= _amount, "Unstake amount exceeds current stake");

        uint32 currentEpoch = getEpoch();

        // Create a new lock for the unstaked amount
        locks[msg.sender] = Structs.Lock(_amount, currentEpoch + unstakeLockPeriod);

        // TODO: Consider reducing the staker's stake here or in the withdraw function
    }

    /**
     * @dev Allows a staker to withdraw their unstaked $LUMINO tokens after the lock period.
     * @param _stakerId The ID of the staker
     */
    function withdraw(uint32 _stakerId) external {
        uint32 currentEpoch = getEpoch();
        require(_stakerId != 0, "Staker doesn't exist");

        Structs.Lock storage lock = locks[msg.sender];

        require(lock.unlockAfter != 0, "No unstake request found");
        require(lock.unlockAfter <= currentEpoch, "Unlock period not reached");

        uint256 withdrawAmount = lock.amount;

        // Reduce the staker's stake
        stakers[_stakerId].stake = stakers[_stakerId].stake - withdrawAmount;

        // Reset the lock
        _resetLock(_stakerId);

        // TODO: Transfer LUMINO tokens back to the staker
        // require(lumino.transfer(msg.sender, withdrawAmount), "Token transfer failed");
    }

    /**
     * @dev Resets the unstake lock for a staker.
     * @param _stakerId ID of the staker whose lock is being reset
     */
    function _resetLock(uint32 _stakerId) private {
        locks[stakers[_stakerId]._address] = Structs.Lock({
            amount: 0,
            unlockAfter: 0
        });
    }

    // TODO: Implement additional functions such as slashing, reward distribution, etc.
    
    // for possible future upgrades
    uint256[50] private __gap;
}
