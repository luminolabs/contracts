// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title NodeStorage
 * @notice Manages storage for staker's node related data in the Lumino network
 * @dev This contract is intended to be inherited by the NodeManager contract
 */
abstract contract StakerNodeStorage {

     /**
     * @notice Represents a staker in the Lumino network
     * @dev Used to store comprehensive information about each staker
     */
    struct Staker {
        bool isSlashed;             // Whether the staker has been slashed
        address _address;           // Ethereum address of the staker
        uint32[] nodeIds;
        uint256 totalStake;         // Current total stake amount
        uint256 stakerReward;       // Accumulated rewards
    }

    struct Lock {
        uint32 unlockAfter;
        uint256 amount; 
    }

    struct NodeInfo {
        bool isActive;
        address _cpAddress;         // Ethereum address of the staker
        uint32 _nodeId;
        uint32 age;                 // Number of epochs the staker has been active
        uint32 epochFirstStaked;    // Epoch when the staker first staked
        uint32 epochLastPenalized;  // Last epoch when the staker was penalized
        uint256 nodeStake;
        uint256 computeRating;
    }

    /**
     * @notice Stores detailed information about each staker
     * @dev Maps staker addresses to Staker structs
     */
    mapping(address => Staker) public stakers;
    /**
     * @notice Stores detailed information about each node of a staker
     * @dev Map of staker address to nodeId to nodeInfo
     */
    mapping(address => mapping(uint32 => NodeInfo)) nodes;
     /// @notice Tracks locked stakes for each node of a staker address
    mapping(address => mapping(uint32 =>Lock)) public locks;
    /// @notice Mapping from pool ID (compute rating) to node IDs in that pool
    mapping(uint16 => uint32[]) public poolNodes;
    
    
}