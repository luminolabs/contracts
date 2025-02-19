// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LuminoToken} from "../LuminoToken.sol";
import {IAccessManager} from "../interfaces/IAccessManager.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";

abstract contract AEscrow is IEscrow {
    // Constants
    uint256 public constant LOCK_PERIOD = 1 days;
    uint256 public constant MIN_DEPOSIT = 0.1 ether;
    uint256 public constant MIN_BALANCE = 0.01 ether;

    // Contracts
    IAccessManager internal immutable accessManager;
    LuminoToken internal immutable token;

    // State variables
    string private escrowName;
    mapping(address => uint256) internal balances;
    mapping(address => WithdrawRequest) internal withdrawRequests;

    /**
     * @notice Initializes the escrow contract
     */
    constructor(address _accessManager, address _token) {
        accessManager = IAccessManager(_accessManager);
        token = LuminoToken(_token);
        escrowName = getEscrowName();
    }

    function getEscrowName() internal virtual pure returns (string memory);

    /**
     * @notice Allows deposits into escrow
     */
    function deposit(uint256 amount) external {
        if (amount < MIN_DEPOSIT) {
            revert BelowMinimumDeposit(amount, MIN_DEPOSIT);
        }

        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        emit Deposited(msg.sender, amount, balances[msg.sender], getEscrowName());
    }

    /**
     * @notice Initiates a withdrawal request for funds
     */
    function requestWithdraw(uint256 amount) external {
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

        emit WithdrawRequested(msg.sender, amount, block.timestamp + LOCK_PERIOD, escrowName);
    }

    /**
     * @notice Cancels an existing withdrawal request
     */
    function cancelWithdraw() external {
        WithdrawRequest storage req = withdrawRequests[msg.sender];
        if (!req.active) {
            revert NoWithdrawRequest(msg.sender);
        }

        uint256 amount = req.amount;
        delete withdrawRequests[msg.sender];

        emit WithdrawCancelled(msg.sender, amount, escrowName);
    }

    /**
     * @notice Completes a withdrawal after lock period
     */
    function withdraw() external {
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
        if (address(this).balance < amount) {
            revert InsufficientContractBalance(amount, address(this).balance);
        }

        balances[msg.sender] -= amount;
        delete withdrawRequests[msg.sender];

        bool success = token.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }

        emit Withdrawn(msg.sender, amount, balances[msg.sender], escrowName);
    }

    /**
      * @notice Gets the balance of a user
      */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice Requires that an account has a minimum balance
     */
    function requireBalance(address user, uint256 amount) public view {
        if (balances[user] < amount) {
            revert InsufficientBalance(user, amount, balances[user]);
        }
    }
}