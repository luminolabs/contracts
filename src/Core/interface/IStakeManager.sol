// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../lib/Structs.sol";
import "../storage/Constants.sol";

interface IStakeManager {

    /**
     * @param _address Address of the staker
     * @return The staker ID
     */
    function getStakerId(address _address) external view returns (uint32);

    /**
     * @param _id The staker ID
     * @return staker The Struct of staker information
     */
    function getStaker(uint32 _id) external view returns (Structs.Staker memory staker);

    /**
     * @return The number of stakers in the razor network
     */
    function getNumStakers() external view returns (uint32);

    /**
     * @param stakerId ID of the staker
     * @return stake of staker
     */
    function getStake(uint32 stakerId) external view returns (uint256);
}