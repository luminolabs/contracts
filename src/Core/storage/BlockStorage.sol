// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.20;

// import "../../lib/Structs.sol";

// /**
//  * @title BlockStorage
//  * @notice This contract manages the storage of block-related data for the Lumino network
//  * @dev This contract is intended to be inherited by the BlockManager contract
//  */
// contract BlockStorage {
//     /**
//      * @notice Stores proposed blocks for each epoch
//      * @dev Mapping of epoch -> blockId -> block
//      */
//     mapping(uint32 => mapping(uint32 => Structs.Block)) public proposedBlocks;

//     /**
//      * @notice Stores confirmed blocks for each epoch
//      * @dev Mapping of epoch -> block
//      */
//     mapping(uint32 => Structs.Block) public blocks;

//     /**
//      * @notice Stores sorted block IDs for each epoch
//      * @dev Mapping of epoch -> array of blockIds
//      */
//     mapping(uint32 => uint32[]) public sortedProposedBlockIds;

//     /**
//      * @notice Tracks the last epoch in which each staker proposed a block
//      * @dev Mapping of stakerId -> epoch
//      */
//     mapping(uint32 => uint32) public epochLastProposed;

//     /**
//      * @notice Total number of proposed blocks in the current epoch
//      */
//     uint32 public numProposedBlocks;

//     /**
//      * @notice Index of the block that is to be confirmed if not disputed
//      * @dev Index in sortedProposedBlockIds array, -1 if no block to confirm
//      */
//     int8 public blockIndexToBeConfirmed;

//     /**
//      * @notice Maximum number of blocks a staker can propose per epoch
//      */
//     uint256 public constant MAX_BLOCKS_PER_EPOCH_PER_STAKER = 1;
    
// }