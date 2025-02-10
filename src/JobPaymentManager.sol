// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IJobPaymentEscrow} from "./interfaces/IJobPaymentEscrow.sol";
import {IJobPaymentManager} from "./interfaces/IJobPaymentManager.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {INodeRegistryCore} from "./interfaces/INodeRegistryCore.sol";

/**
 * @title JobPaymentManager
 * @notice Manages job payments and fee calculations for completed jobs
 * @dev Handles the processing, calculation, and distribution of payments for completed jobs
 */
contract JobPaymentManager is IJobPaymentManager, AccessControlled {
    // Core contracts
    IJobRegistry public immutable jobRegistry;
    INodeRegistryCore public immutable nodeRegistry;
    IJobPaymentEscrow public immutable paymentEscrow;

    // Payment configuration
    uint256 public baseFee;
    uint256 public ratingMultiplier;

    // State variables
    /// @dev Mapping of processed jobs to prevent double payments
    mapping(uint256 => bool) private processedJobs;
    /// @dev Mapping of last withdrawal timestamp for cooldown period
    mapping(address => uint256) private lastWithdrawal;

    // Constants
    uint256 public constant WITHDRAWAL_COOLDOWN = 1 days;
    uint256 public constant MIN_WITHDRAWAL = 0.1 ether;

    // Custom errors
    error JobAlreadyProcessed(uint256 jobId);
    error JobNotComplete(uint256 jobId);
    error WithdrawalCooldownActive(uint256 remainingTime);
    error InsufficientWithdrawalAmount(uint256 amount, uint256 minimum);
    error TransferFailed();
    error InvalidFeeUpdate(uint256 newBaseFee, uint256 newRatingMultiplier);

    /**
     * @notice Ensures a job hasn't been processed already
     * @param jobId The ID of the job to check
     */
    modifier jobNotProcessed(uint256 jobId) {
        if (processedJobs[jobId]) {
            revert JobAlreadyProcessed(jobId);
        }
        _;
    }

    /**
     * @notice Initializes the JobPaymentManager contract
     * @param _jobRegistry Address of the JobRegistry contract
     * @param _nodeRegistry Address of the NodeRegistryCore contract
     * @param _paymentEscrow Address of the JobPaymentEscrow contract
     * @param _accessController Address of the AccessController contract
     * @param _baseFee Initial base fee for job payments
     * @param _ratingMultiplier Initial rating multiplier for job payments
     * @dev Sets up core contract references and payment parameters
     */
    constructor(
        address _jobRegistry,
        address _nodeRegistry,
        address _paymentEscrow,
        address _accessController,
        uint256 _baseFee,
        uint256 _ratingMultiplier
    ) AccessControlled(_accessController) {
        jobRegistry = IJobRegistry(_jobRegistry);
        nodeRegistry = INodeRegistryCore(_nodeRegistry);
        paymentEscrow = IJobPaymentEscrow(_paymentEscrow);
        baseFee = _baseFee;
        ratingMultiplier = _ratingMultiplier;
    }

    /**
     * @notice Process payment for a completed job
     * @param jobId The ID of the completed job
     * @dev Can be called by operators or authorized contracts
     * @dev Verifies job completion and releases payment through escrow
     * @dev Emits PaymentProcessed or PaymentFailed event
     */
    function processPayment(uint256 jobId) external jobNotProcessed(jobId) onlyOperatorOrContracts {
        IJobRegistry.Job memory job = jobRegistry.getJob(jobId);
        if (job.status != IJobRegistry.JobStatus.COMPLETE) {
            revert JobNotComplete(jobId);
        }

        address nodeOwner = nodeRegistry.getNodeOwner(job.assignedNode);
        uint256 payment = calculateJobPayment(jobId);

        try paymentEscrow.releaseJobPayment(nodeOwner, payment, jobId) {
            processedJobs[jobId] = true;
            emit PaymentProcessed(jobId, nodeOwner, payment);
        } catch Error(string memory reason) {
            emit PaymentFailed(jobId, nodeOwner, reason);
        }
    }

    /**
     * @notice Calculate payment amount for a job
     * @param jobId The ID of the job to calculate payment for
     * @return uint256 The calculated payment amount
     * @dev Payment = baseFee + (node.computeRating * ratingMultiplier)
     */
    function calculateJobPayment(uint256 jobId) public view returns (uint256) {
        IJobRegistry.Job memory job = jobRegistry.getJob(jobId);
        INodeRegistryCore.NodeInfo memory node = nodeRegistry.getNodeInfo(job.assignedNode);

        // Base payment calculation
        uint256 payment = baseFee;

        // Add rating multiplier
        payment += (node.computeRating * ratingMultiplier);

        return payment;
    }

    /**
     * @notice Update fee structure for job payments
     * @param newBaseFee New base fee value
     * @param newRatingMultiplier New rating multiplier value
     * @dev Can only be called by admin
     * @dev Emits FeeUpdated event
     */
    function updateFeeStructure(
        uint256 newBaseFee,
        uint256 newRatingMultiplier
    ) external onlyAdmin {
        if (newBaseFee == 0 || newRatingMultiplier == 0) {
            revert InvalidFeeUpdate(newBaseFee, newRatingMultiplier);
        }

        baseFee = newBaseFee;
        ratingMultiplier = newRatingMultiplier;

        emit FeeUpdated(newBaseFee, newRatingMultiplier);
    }

    /**
     * @notice Get pending payments for a node
     * @param node Address of the node
     * @return uint256 Amount of pending payments
     * @dev Returns the total balance held in escrow for the node
     */
    function getPendingPayments(address node) external view returns (uint256) {
        return paymentEscrow.getBalance(node);
    }

    /**
     * @notice Check if a job has been processed for payment
     * @param jobId The ID of the job to check
     * @return bool True if the job has been processed, false otherwise
     */
    function isJobProcessed(uint256 jobId) external view returns (bool) {
        return processedJobs[jobId];
    }
}