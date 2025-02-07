// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IJobPaymentManager {
    event PaymentProcessed(uint256 indexed jobId, address indexed node, uint256 amount);
    event PaymentFailed(uint256 indexed jobId, address indexed node, string reason);
    event FeeUpdated(uint256 newBaseFee, uint256 newRatingMultiplier);

    function processPayment(uint256 jobId) external;
    function calculateJobPayment(uint256 jobId) external view returns (uint256);
    function withdrawEarnings() external;
    function updateFeeStructure(uint256 newBaseFee, uint256 newRatingMultiplier) external;
    function getPendingPayments(address node) external view returns (uint256);
}