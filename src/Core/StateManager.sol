// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./storage/Constants.sol";

contract StateManager is Constants {
    /**
     * @notice a check to ensure the epoch value sent in the function is of the currect epoch
     */
    modifier checkEpoch(uint32 epoch) {
        require(epoch == getEpoch(), "incorrect epoch");
        _;
    }

    // returns the value of current epoch
    function getEpoch() public view returns (uint32) {
        return (uint32(block.timestamp) / (EPOCH_LENGTH));
    }

    // returns the value of current state
    function getState(uint8 buffer) public view returns (State) {
        uint8 lowerLimit = buffer;

        // EPOCH_LENGTH / NUM_STATES is stateLength
        uint16 upperLimit = EPOCH_LENGTH / NUM_STATES - buffer;

        if (
            block.timestamp % (EPOCH_LENGTH / NUM_STATES) > upperLimit ||
            block.timestamp % (EPOCH_LENGTH / NUM_STATES) < lowerLimit
        ) {
            return State.Buffer;
        }

        uint8 state = uint8(
            ((block.timestamp) / (EPOCH_LENGTH / NUM_STATES)) % (NUM_STATES)
        );
        return State(state);
    }
}
