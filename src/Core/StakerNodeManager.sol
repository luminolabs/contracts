// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
// import {IStakingCore} from "./interfaces/IStakingCore.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Shared} from "./storage/Shared.sol";
import "./storage/StakerNodeStorage.sol";
import "./EpochManager.sol";
import "./ACL.sol";

/**
 * @title StakerNodeManager
 * @dev Manages the staking mechanism for computing providers in the network.
 * Providers must be whitelisted and stake a minimum amount of tokens to participate.
 * Includes functionality for staking, requesting unstaking, and withdrawing stakes
 * after a lock period.
 *
 * Security:
 * - Uses ReentrancyGuard for all external functions that involve token transfers
 * - Requires whitelist verification before staking
 * - Implements a time lock for unstaking to prevent rapid stake/unstake cycles
 * - Only authorized contracts can apply penalties
 */
contract StakerNodeManager is StakerNodeStorage, Shared, Initializable, ACL, EpochManager, ReentrancyGuard {
    // Core contracts
    IERC20 public immutable luminoToken;

    // Events
    event StakeUpdated(address indexed cp, uint256 oldStake, uint256 newStake);

    /**
     * @notice Initialize the staking contract
     * @dev Sets up core contract references and validates addresses
     * @param _stakingToken Address of the ERC20 token used for staking
     * @param _whitelistManager Address of the whitelist contract
     * @param _accessController Address of the access control contract
     */
    // constructor(
    //     address _stakingToken,
    //     address _whitelistManager,
    //     address _accessController
    // )
    // {
    //     if (_stakingToken == address(0) || _whitelistManager == address(0) ||
    //         _accessController == address(0)) revert ZeroAddress();

    //     stakingToken = IERC20(_stakingToken);
    // }

    /**
     * @notice Stake tokens into the system
     * @dev Requires provider to be whitelisted and stake at least MIN_STAKE
     * Tokens are transferred from the provider to this contract
     * @param _amount The amount of tokens to stake
     * @param _nodeId The nodeId
     */
    // function stake(uint256 _amount, uint32 _nodeId) external isWhitelisted nonReentrant {
    function stake(uint256 _amount, uint32 _nodeId, uint32 _epoch) external payable nonReentrant checkEpoch(_epoch) {
        
        require(msg.value == _amount, "token amount and tokens sent does not match");
        require(_amount > 0, "amount cannot be zero");
        require(!stakers[msg.sender].isSlashed, "Staker is slashed");

        if (_nodeId == 0) {
            require(msg.value >= MIN_STAKE, "amount below minimum stake");

            nodeCounter = nodeCounter + 1;
            _nodeId = nodeCounter;

            // transferToken
            
            if (stakers[msg.sender].totalStake == 0) {
                // first time staker
                stakers[msg.sender]._address = msg.sender;
            } 
            stakers[msg.sender].nodeIds.push(_nodeId);
            stakers[msg.sender].totalStake = stakers[msg.sender].totalStake + _amount;
            nodes[msg.sender][_nodeId] = NodeInfo({
                isActive: false,
                _cpAddress: msg.sender,
                _nodeId: _nodeId,
                age: 0,                
                epochFirstStaked: _epoch,    
                epochLastPenalized: 0,  
                nodeStake: _amount,
                computeRating: 0
            });

            // emit event

        } else {

            // Transfer tokens

            stakers[msg.sender].totalStake = stakers[msg.sender].totalStake + _amount;
            nodes[msg.sender][_nodeId].nodeStake = nodes[msg.sender][_nodeId].nodeStake + _amount;

            // emit events
        }   
        // if (amount < MIN_STAKE) {
        //     revert BelowMinimumStake(amount, MIN_STAKE);
        // }

        // uint256 oldStake = stakes[msg.sender];
        // stakes[msg.sender] += amount;

        // // Transfer tokens
        // bool success = stakingToken.transferFrom(msg.sender, address(this), amount);
        // if (!success) {
        //     revert TransferFailed();
        // }

        // emit StakeUpdated(msg.sender, oldStake, stakes[msg.sender]);
        // emit Staked(msg.sender, amount);
    }

    /**
     * @dev Initiates the unstaking process for a staker.
     * @param _nodeId The ID of the staker who wants to unstake
     * @param _amount The amount of $LUMINO tokens to unstake
     */
    function unstake(uint32 _nodeId, uint256 _amount) external {
        require(_nodeId != 0, "Invalid staker ID");
        require(_amount > 0, "Invalid amount to unstake");
        require(nodes[msg.sender][_nodeId].nodeStake > 0, "No stake to unstake");
        require(locks[msg.sender][_nodeId].amount == 0, "Existing unstake lock");
        require(nodes[msg.sender][_nodeId]._cpAddress == msg.sender, "Can only unstake your own funds");
        require(nodes[msg.sender][_nodeId].nodeStake >= _amount, "Unstake amount exceeds current stake");

        uint32 currentEpoch = getEpoch();

        // Create a new lock for the unstaked amount
        locks[msg.sender][_nodeId] = Lock(
            currentEpoch + LOCK_PERIOD,
            _amount
        );

    }


    /**
     * @dev Allows a staker to withdraw their unstaked $LUMINO tokens after the lock period.
     * @param _nodeId The ID of the staker
     */
    function withdraw(uint32 _nodeId) external {
        uint32 currentEpoch = getEpoch();
        require(_nodeId != 0, "nodeId doesn't exist");

        require(locks[msg.sender][_nodeId].unlockAfter != 0, "No unstake request found");
        require(locks[msg.sender][_nodeId].unlockAfter <= currentEpoch, "Unlock period not reached");

        uint256 withdrawAmount = locks[msg.sender][_nodeId].amount;

        // Reduce the staker's stake
        stakers[msg.sender].totalStake = stakers[msg.sender].totalStake - withdrawAmount;
        nodes[msg.sender][_nodeId].nodeStake = nodes[msg.sender][_nodeId].nodeStake - withdrawAmount;

        // Reset the lock
        _resetLock(_nodeId, msg.sender);

        // Transfer the amount to the sender
        (bool success, ) = msg.sender.call{value: withdrawAmount}("");
        require(success, "Transfer failed");

        // TODO: Transfer LUMINO tokens back to the staker
        // require(lumino.transfer(msg.sender, withdrawAmount), "Token transfer failed");
        // emit event
    }

    /**
     * @dev Resets the unstake lock for a staker.
     * @param _nodeId ID of the staker whose lock is being reset
     */
    function _resetLock(uint32 _nodeId, address _cpAddress) internal {
        locks[_cpAddress][_nodeId] = Lock({
            amount: 0,
            unlockAfter: 0
        });
    }


    /**
     * @notice Apply a penalty to a provider's stake
     * @dev Only callable by authorized contracts (e.g., PenaltyManager)
     * Reduces the provider's stake by the penalty amount
     * @param cp Address of the computing provider
     * @param amount Amount of tokens to penalize
     */
    // function applyPenalty(address cp, uint256 amount) external hasRewardsRole nonReentrant {
    // function applyPenalty(address cp, uint256 amount) external nonReentrant {
    //     if (stakers[cp] < amount) {
    //         revert InsufficientStake(cp, amount, stakes[cp]);
    //     }

    //     uint256 oldStake = stakes[cp];
    //     stakes[cp] -= amount;

    //     emit StakeUpdated(cp, oldStake, stakes[cp]);
    // }

    // View functions

    /**
     * @notice Get the current staked balance of a provider
     * @param cp Address of the computing provider
     * @return uint256 Current staked balance
     */
    // function getStakedBalance(address cp) external view returns (uint256) {
    //     return stakes[cp];
    // }

    /**
     * @notice Check if a provider has an active unstake request
     * @param cp Address of the computing provider
     * @return bool True if there is an active unstake request
     */
    // function hasUnstakeRequest(address cp) external view returns (bool) {
    //     return unstakeRequests[cp].amount > 0;
    // }

    /**
     * @notice Get details of a provider's unstake request
     * @param cp Address of the computing provider
     * @return amount The requested unstake amount
     * @return requestTime The timestamp when the request was made
     */
    // function getUnstakeRequestDetails(address cp)
    // external
    // view
    // returns (uint256 amount, uint256 requestTime)
    // {
    //     UnstakeRequest memory request = unstakeRequests[cp];
    //     return (request.amount, request.timestamp);
    // }

    /**
     * @notice Get remaining lock time for an unstake request
     * @param cp Address of the computing provider
     * @return uint256 Remaining time in seconds, 0 if no request or lock expired
     */
    // function getRemainingLockTime(address cp) external view returns (uint256) {
    //     UnstakeRequest memory request = unstakeRequests[cp];
    //     if (request.amount == 0) return 0;

    //     uint256 lockEndTime = request.timestamp + LOCK_PERIOD;
    //     if (block.timestamp >= lockEndTime) return 0;
    //     return lockEndTime - block.timestamp;
    // }
}