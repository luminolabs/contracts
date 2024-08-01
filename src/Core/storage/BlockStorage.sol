// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../../lib/Structs.sol";

contract BlockStorage {
    
    /// mapping of epoch -> blockId -> block
    mapping(uint32 => mapping(uint32 => Structs.Block)) public proposedBlocks;
    
    /// mapping of  epoch -> blocks
    mapping(uint32 => Structs.Block) public blocks;

    /// mapping of epoch->blockId
    mapping(uint32 => uint32[]) public sortedProposedBlockIds;
    
    /// mapping of stakerId->epoch
    mapping(uint32 => uint32) public epochLastProposed;
    
    /// total number of proposed blocks in an epoch
    uint32 public numProposedBlocks;
        
    /// block index that is to be confirmed if not disputed
    int8 public blockIndexToBeConfirmed; // Index in sortedProposedBlockIds

    uint256 public constant MAX_BLOCKS_PER_EPOCH_PER_STAKER = 1;

}