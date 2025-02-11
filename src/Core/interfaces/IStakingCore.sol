// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStakingCore {
    event Staked(address indexed cp, uint256 amount);
    event UnstakeRequested(address indexed cp, uint256 amount);
    event Withdrawn(address indexed cp, uint256 amount);

    function stake(uint256 amount) external;
    function requestUnstake(uint256 amount) external;
    function withdraw() external;
    function getStakedBalance(address cp) external view returns (uint256);
    function hasUnstakeRequest(address cp) external view returns (bool);
    function getUnstakeRequestDetails(address cp) external view returns (uint256 amount, uint256 requestTime);
}