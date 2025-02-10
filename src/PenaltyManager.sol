// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {AccessControlled} from "./abstracts/AccessControlled.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IPenaltyManager} from "./interfaces/IPenaltyManager.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";

/**
 * @title PenaltyManager
 * @notice Manages penalties and slashing for computing providers in the network
 * @dev Handles the application of penalties to staked tokens and implements slashing
 * mechanisms for repeated violations
 *
 * The PenaltyManager implements a graduated penalty system where:
 * - Individual penalties result in partial loss of staked tokens
 * - Repeated penalties can trigger complete slashing of remaining stake
 * - All penalized tokens are sent to a treasury address
 */
contract PenaltyManager is IPenaltyManager, AccessControlled, ReentrancyGuard {
    // Core contracts
    IStakingCore public immutable stakingCore;
    IERC20 public immutable stakingToken;

    // Penalty configuration
    uint256 public penaltyRate;
    uint256 public slashThreshold;

    // State variables
    /// @dev Tracks number of penalties applied to each computing provider
    mapping(address => uint256) private penaltyCount;
    /// @dev Tracks total amount of penalties applied to each computing provider
    mapping(address => uint256) private totalPenaltyAmount;
    /// @dev Tracks whether a computing provider has been slashed
    mapping(address => bool) private slashed;

    /**
     * @notice Address where penalized tokens are sent
     * @dev Must be non-zero and can be updated by admin
     */
    address public treasury;

    // Custom errors
    error AlreadySlashed(address cp);
    error NoStakeToSlash(address cp);
    error InvalidPenaltyConfig(uint256 value);
    error ZeroAddress();
    error TransferFailed();
    error SlashThresholdNotMet(address cp, uint256 penalties, uint256 required);
    error InvalidStakingToken();

    // Events
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event EmergencyTransfer(address indexed token, address indexed recipient, uint256 amount);

    /**
     * @notice Initialize the PenaltyManager contract
     * @param _stakingCore Address of the StakingCore contract
     * @param _stakingToken Address of the staking token contract
     * @param _treasury Address where penalized tokens will be sent
     * @param _accessController Address of the AccessController contract
     * @param _initialPenaltyRate Initial penalty rate (percentage)
     * @param _initialSlashThreshold Initial number of penalties before slashing
     */
    constructor(
        address _stakingCore,
        address _stakingToken,
        address _treasury,
        address _accessController,
        uint256 _initialPenaltyRate,
        uint256 _initialSlashThreshold
    ) AccessControlled(_accessController) {
        if (_treasury == address(0)) revert ZeroAddress();

        stakingCore = IStakingCore(_stakingCore);
        stakingToken = IERC20(_stakingToken);
        treasury = _treasury;

        if (_initialPenaltyRate == 0 || _initialPenaltyRate > 100) {
            revert InvalidPenaltyConfig(_initialPenaltyRate);
        }
        if (_initialSlashThreshold == 0) {
            revert InvalidPenaltyConfig(_initialSlashThreshold);
        }

        penaltyRate = _initialPenaltyRate;
        slashThreshold = _initialSlashThreshold;
    }

    /**
     * @notice Apply a penalty to a computing provider's stake
     * @dev Calculates and transfers penalty amount to treasury
     * @param cp Address of computing provider
     * @param reason Reason for applying penalty
     */
    function applyPenalty(
        address cp,
        string calldata reason
    ) external onlyOperatorOrContracts nonReentrant {
        if (slashed[cp]) {
            revert AlreadySlashed(cp);
        }

        uint256 stakedAmount = stakingCore.getStakedBalance(cp);
        if (stakedAmount == 0) {
            revert NoStakeToSlash(cp);
        }

        // Calculate and apply penalty
        uint256 penaltyAmount = (stakedAmount * penaltyRate) / 100;
        penaltyCount[cp] += 1;
        totalPenaltyAmount[cp] += penaltyAmount;

        // Transfer penalty to treasury
        bool success = stakingToken.transferFrom(address(stakingCore), treasury, penaltyAmount);
        if (!success) {
            revert TransferFailed();
        }

        emit PenaltyApplied(cp, penaltyAmount, reason);

        // Check if slash threshold is reached
        (bool exceeded,) = checkSlashThreshold(cp);
        if (exceeded) {
            executeSlash(cp);
        }
    }

    /**
     * @notice Execute slashing of a computing provider's entire stake
     * @dev Transfers all remaining staked tokens to treasury
     * @param cp Address of computing provider to slash
     */
    function executeSlash(address cp) public nonReentrant {
        // TODO: Only in dispute state

        if (slashed[cp]) {
            revert AlreadySlashed(cp);
        }

        (bool exceeded, uint256 count) = checkSlashThreshold(cp);
        if (!exceeded) {
            revert SlashThresholdNotMet(cp, count, slashThreshold);
        }

        uint256 stakedAmount = stakingCore.getStakedBalance(cp);
        if (stakedAmount == 0) {
            revert NoStakeToSlash(cp);
        }

        // Mark as slashed before transfer
        slashed[cp] = true;

        // Transfer remaining stake to treasury
        bool success = stakingToken.transferFrom(address(stakingCore), treasury, stakedAmount);
        if (!success) {
            revert TransferFailed();
        }

        emit SlashExecuted(cp, stakedAmount);
    }

    /**
     * @notice Update the penalty threshold for slashing
     * @dev Only callable by admin
     * @param newThreshold New threshold value
     */
    function updatePenaltyThreshold(uint256 newThreshold) external onlyAdmin {
        if (newThreshold == 0) {
            revert InvalidPenaltyConfig(newThreshold);
        }
        slashThreshold = newThreshold;
        emit PenaltyThresholdUpdated(newThreshold);
    }

    /**
     * @notice Update the penalty rate
     * @dev Only callable by admin, rate must be between 1-100
     * @param newRate New penalty rate as percentage
     */
    function updatePenaltyRate(uint256 newRate) external onlyAdmin {
        if (newRate == 0 || newRate > 100) {
            revert InvalidPenaltyConfig(newRate);
        }
        penaltyRate = newRate;
        emit PenaltyRateUpdated(newRate);
    }

    /**
     * @notice Update the treasury address
     * @dev Only callable by admin
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) {
            revert ZeroAddress();
        }
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Emergency function to transfer non-staking tokens
     * @dev Only callable by admin, cannot transfer staking token
     * @param token Address of token to transfer
     * @param amount Amount to transfer
     */
    function emergencyTransfer(address token, uint256 amount) external onlyAdmin {
        if (token == address(stakingToken)) {
            revert InvalidStakingToken();
        }
        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }
        emit EmergencyTransfer(token, msg.sender, amount);
    }

    /**
     * @notice Get number of penalties applied to a computing provider
     * @param cp Address of computing provider
     * @return uint256 Number of penalties
     */
    function getPenaltyCount(address cp) external view returns (uint256) {
        return penaltyCount[cp];
    }

    /**
     * @notice Get total amount of penalties for a computing provider
     * @param cp Address of computing provider
     * @return uint256 Total penalty amount
     */
    function getTotalPenalties(address cp) external view returns (uint256) {
        return totalPenaltyAmount[cp];
    }

    /**
     * @notice Check if a computing provider has reached the slash threshold
     * @param cp Address of computing provider
     * @return exceeded Boolean indicating if threshold is exceeded
     * @return count Current number of penalties
     */
    function checkSlashThreshold(address cp) public view returns (bool exceeded, uint256 count) {
        count = penaltyCount[cp];
        exceeded = count >= slashThreshold;
        return (exceeded, count);
    }

    /**
     * @notice Check if a computing provider has been slashed
     * @param cp Address of computing provider
     * @return bool True if provider has been slashed
     */
    function isSlashed(address cp) external view returns (bool) {
        return slashed[cp];
    }
}