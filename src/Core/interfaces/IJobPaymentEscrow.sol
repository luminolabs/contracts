// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IJobPaymentEscrow {
    struct WithdrawRequest {
        uint256 amount;
        uint256 requestTime;
        bool active;
    }

    event Deposited(address indexed user, uint256 amount, uint256 newBalance);
    event WithdrawRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event WithdrawCancelled(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount, uint256 remainingBalance);
    event JobPaymentReleased(address indexed node, uint256 amount, uint256 jobId);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    // Customer functions
    function deposit() external payable;
    function requestWithdraw(uint256 amount) external;
    function cancelWithdraw() external;
    function withdraw() external;

    // Job payment functions
    function releaseJobPayment(address node, uint256 amount, uint256 jobId) external;

    // View functions
    function getBalance(address user) external view returns (uint256);
    function hasMinimumBalance(address user) external view returns (bool);
    function getWithdrawRequest(address user) external view returns (
        uint256 amount,
        uint256 requestTime,
        bool active,
        uint256 remainingLockTime
    );

    // Admin functions
    function emergencyWithdraw() external;

    // Constants
    function LOCK_PERIOD() external view returns (uint256);
    function MIN_DEPOSIT() external view returns (uint256);
    function MIN_BALANCE() external view returns (uint256);
}