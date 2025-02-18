// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEscrow {
    // Structs
    struct WithdrawRequest {
        uint256 amount;
        uint256 requestTime;
        bool active;
    }

    // Events
    event Deposited(address indexed user, uint256 amount, uint256 newBalance, string escrowName);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 unlockTime, string escrowName);
    event WithdrawCancelled(address indexed user, uint256 amount, string escrowName);
    event Withdrawn(address indexed user, uint256 amount, uint256 remainingBalance, string escrowName);

    // Errors
    error BelowMinimumDeposit(uint256 provided, uint256 minimum);
    error InsufficientBalance(address user, uint256 requested, uint256 available);
    error ExistingWithdrawRequest(address user);
    error NoWithdrawRequest(address user);
    error LockPeriodActive(address user, uint256 remainingTime);
    error TransferFailed();
    error InsufficientContractBalance(uint256 requested, uint256 available);

    // Escrow functions
    function deposit(uint256 amount) external;
    function requestWithdraw(uint256 amount) external;
    function cancelWithdraw() external;
    function withdraw() external;
    function getBalance(address user) external view returns (uint256);
    function requireBalance(address user, uint256 amount) external view;
}