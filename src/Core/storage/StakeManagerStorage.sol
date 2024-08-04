// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/Structs.sol";

/**
 * @title StakeManagerStorage
 * @notice Manages storage for staker-related data in the Lumino network
 * @dev This contract is intended to be inherited by the StakeManager contract
 */
abstract contract StakeManagerStorage {
    /**
     * @notice Total number of stakers in the network
     * @dev Also used as a counter for assigning new staker IDs
     */
    uint32 public numStakers;

    /**
     * @notice Maps staker addresses to their unique staker IDs
     */
    mapping(address => uint32) public stakerIds;

    /**
     * @notice Stores detailed information about each staker
     * @dev Maps staker IDs to Staker structs
     */
    mapping(uint32 => Structs.Staker) public stakers;

    /**
     * @notice Tracks locked stakes for each staker address
     */
    mapping(address => Structs.Lock) public locks;

    /**
     * @notice Defines the percentages for different actions when slashing occurs
     */
    struct SlashNums {
        /**
         * @notice Percentage of slashed stake given as bounty to the reporter
         */
        uint32 bounty;

        /**
         * @notice Percentage of slashed stake to be burned
         */
        uint32 burn;

        /**
         * @notice Percentage of slashed stake to be kept by the staker
         */
        uint32 keep;
    }

    /**
     * @notice The current slashing percentages
     */
    SlashNums public slashNums;

   
}