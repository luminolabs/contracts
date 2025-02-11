// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {PausableController} from "./abstracts/PausableController.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IJobPaymentEscrow} from "./interfaces/IJobPaymentEscrow.sol";

/**
 * @title JobPaymentEscrow
 * @notice Manages escrow payments for job execution in the Lumino network
 * @dev Handles deposits, withdrawals, and payment releases for computing providers
 *
 * This contract serves as the central payment escrow system for the Lumino network.
 * It manages deposits from job submitters, ensures secure payment releases to computing
 * providers, and handles withdrawal requests with appropriate lock periods.
 *
 * Security measures include:
 * - ReentrancyGuard for all value transfer functions
 * - Role-based access control for administrative functions
 * - Lock periods for withdrawals to prevent rapid fund drainage
 * - Emergency pause functionality for system-wide issues
 */
contract JobPaymentEscrow is IJobPaymentEscrow, PausableController, ReentrancyGuard {
    // Core contracts
    //

    // Constants
    uint256 public constant LOCK_PERIOD = 1 days;
    uint256 public constant MIN_DEPOSIT = 0.1 ether;
    uint256 public constant MIN_BALANCE = 0.01 ether;

    // State variables
    mapping(address => uint256) public balances;
    mapping(address => WithdrawRequest) public withdrawRequests;

    // Custom errors
    error BelowMinimumDeposit(uint256 provided, uint256 minimum);
    error InsufficientBalance(address user, uint256 requested, uint256 available);
    error ExistingWithdrawRequest(address user);
    error NoWithdrawRequest(address user);
    error LockPeriodActive(address user, uint256 remainingTime);
    error TransferFailed();
    error InsufficientContractBalance(uint256 requested, uint256 available);

    // Events
    //

    /**
     * @notice Initializes the escrow contract
     * @param _accessController Address of the access controller contract
     */
    constructor(address _accessController) PausableController(_accessController) {}

    /**
     * @notice Allows users to deposit funds into escrow
     * @dev Requires minimum deposit amount and system to be unpaused
     * @dev Emits a {Deposited} event upon successful deposit
     */
    function deposit() external payable whenNotPaused {
        if (msg.value < MIN_DEPOSIT) {
            revert BelowMinimumDeposit(msg.value, MIN_DEPOSIT);
        }

        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value, balances[msg.sender]);
    }

    /**
     * @notice Initiates a withdrawal request for funds
     * @dev Starts the lock period for the requested amount
     * @dev Only one active withdrawal request allowed per address
     * @param amount Amount of funds to withdraw
     * @dev Emits a {WithdrawRequested} event upon successful request
     */
    function requestWithdraw(uint256 amount) external whenNotPaused {
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance(msg.sender, amount, balances[msg.sender]);
        }
        if (withdrawRequests[msg.sender].active) {
            revert ExistingWithdrawRequest(msg.sender);
        }

        withdrawRequests[msg.sender] = WithdrawRequest({
            amount: amount,
            requestTime: block.timestamp,
            active: true
        });

        emit WithdrawRequested(msg.sender, amount, block.timestamp + LOCK_PERIOD);
    }

    /**
     * @notice Cancels an existing withdrawal request
     * @dev Deletes the withdrawal request and emits a {WithdrawCancelled} event
     */
    function cancelWithdraw() external {
        WithdrawRequest storage req = withdrawRequests[msg.sender];
        if (!req.active) {
            revert NoWithdrawRequest(msg.sender);
        }

        uint256 amount = req.amount;
        delete withdrawRequests[msg.sender];

        emit WithdrawCancelled(msg.sender, amount);
    }

    /**
     * @notice Completes a withdrawal after lock period
     * @dev Requires lock period to be completed and sufficient balance
     * @dev Protected against reentrancy attacks
     * @dev Emits a {Withdrawn} event upon successful withdrawal
     */
    function withdraw() external nonReentrant whenNotPaused {
        WithdrawRequest storage req = withdrawRequests[msg.sender];
        if (!req.active) {
            revert NoWithdrawRequest(msg.sender);
        }

        if (block.timestamp < req.requestTime + LOCK_PERIOD) {
            revert LockPeriodActive(msg.sender, (req.requestTime + LOCK_PERIOD) - block.timestamp);
        }

        uint256 amount = req.amount;
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance(msg.sender, amount, balances[msg.sender]);
        }

        balances[msg.sender] -= amount;
        delete withdrawRequests[msg.sender];

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit Withdrawn(msg.sender, amount, balances[msg.sender]);
    }

    /**
     * @notice Releases payment to a node for completed job
     * @dev Only callable by authorized contracts
     * @dev Protected against reentrancy attacks
     * @param node Address of the node to receive payment
     * @param amount Amount to be paid
     * @param jobId Identifier of the completed job
     * @dev Emits a {JobPaymentReleased} event upon successful payment
     */
    function releaseJobPayment(
        address node,
        uint256 amount,
        uint256 jobId
    ) external onlyContracts nonReentrant whenNotPaused {
        if (address(this).balance < amount) {
            revert InsufficientContractBalance(amount, address(this).balance);
        }

        (bool success,) = node.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit JobPaymentReleased(node, amount, jobId);
    }

    /**
     * @notice Emergency withdrawal function for admin
     * @dev Only callable when system is paused
     * @dev Protected against reentrancy attacks
     * @dev Emits an {EmergencyWithdraw} event upon successful withdrawal
     */
    function emergencyWithdraw() external nonReentrant onlyAdmin whenNotPaused {
        uint256 balance = balances[msg.sender];
        if (balance == 0) {
            revert InsufficientBalance(msg.sender, 0, 0);
        }

        balances[msg.sender] = 0;
        delete withdrawRequests[msg.sender];

        (bool success,) = msg.sender.call{value: balance}("");
        if (!success) {
            revert TransferFailed();
        }

        emit EmergencyWithdraw(msg.sender, balance);
    }

    /**
     * @notice Gets the current balance of a user
     * @param user Address to check balance for
     * @return uint256 Current balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice Checks if user has minimum required balance
     * @param user Address to check
     * @return bool True if balance meets minimum requirement
     */
    function hasMinimumBalance(address user) external view returns (bool) {
        return balances[user] >= MIN_BALANCE;
    }

    /**
     * @notice Gets details of a user's withdrawal request
     * @param user Address to check
     * @return amount Amount requested for withdrawal
     * @return requestTime Time when withdrawal was requested
     * @return active Whether request is active
     * @return remainingLockTime Time remaining in lock period
     */
    function getWithdrawRequest(address user)
    external
    view
    returns (
        uint256 amount,
        uint256 requestTime,
        bool active,
        uint256 remainingLockTime
    )
    {
        WithdrawRequest memory req = withdrawRequests[user];
        if (!req.active) {
            return (0, 0, false, 0);
        }

        uint256 unlockTime = req.requestTime + LOCK_PERIOD;
        uint256 remaining = block.timestamp >= unlockTime
            ? 0
            : unlockTime - block.timestamp;

        return (req.amount, req.requestTime, req.active, remaining);
    }

    /**
     * @notice Allows contract to receive ETH payments
     */
    receive() external payable {}
}