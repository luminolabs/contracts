// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IStakingCore.sol";
import "./interfaces/IWhitelistManager.sol";
import "./interfaces/IAccessController.sol";

/**
 * @title StakingCore
 * @dev Manages the staking mechanism for computing providers in the network.
 * Providers must be whitelisted and stake a minimum amount of tokens to participate.
 * Includes functionality for staking, requesting unstaking, and withdrawing stakes
 * after a lock period.
 *
 * Security:
 * - Uses ReentrancyGuard for all external functions that involve token transfers
 * - Requires whitelist verification before staking
 * - Implements a time lock for unstaking to prevent rapid stake/unstake cycles
 * - Only authorized contracts can apply penalties
 *
 * @custom:security-contact security@luminonetwork.com
 */
contract StakingCore is IStakingCore, ReentrancyGuard {
    // Core contracts
    IERC20 public immutable stakingToken;
    IWhitelistManager public immutable whitelistManager;
    IAccessController public immutable accessController;

    /**
     * @notice Duration that stakes must be locked before withdrawal
     * @dev Set to 1 day to balance security with provider flexibility
     */
    uint256 public constant LOCK_PERIOD = 1 days;

    /**
     * @notice Minimum amount that can be staked
     * @dev Set to 100 tokens to ensure meaningful economic stake
     */
    uint256 public constant MIN_STAKE = 100 ether; // 100 tokens minimum

    // Staking state
    mapping(address => uint256) private stakes;
    mapping(address => UnstakeRequest) private unstakeRequests;

    // Custom errors
    error Unauthorized(address caller);
    error NotWhitelisted(address cp);
    error BelowMinimumStake(uint256 provided, uint256 minimum);
    error InsufficientStake(address cp, uint256 requested, uint256 available);
    error ExistingUnstakeRequest(address cp);
    error NoUnstakeRequest(address cp);
    error LockPeriodActive(address cp, uint256 remainingTime);
    error TransferFailed();
    error ZeroAddress();

    // Events
    event StakeUpdated(address indexed cp, uint256 oldStake, uint256 newStake);
    event UnstakeRequestCancelled(address indexed cp, uint256 amount);

    /**
     * @dev Ensures caller is an authorized contract
     */
    modifier onlyContracts() {
        if (!accessController.isAuthorized(msg.sender, keccak256("CONTRACTS_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @dev Ensures caller has admin role
     */
    modifier onlyAdmin() {
        if (!accessController.isAuthorized(msg.sender, keccak256("ADMIN_ROLE"))) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @notice Initialize the staking contract
     * @dev Sets up core contract references and validates addresses
     * @param _stakingToken Address of the ERC20 token used for staking
     * @param _whitelistManager Address of the whitelist contract
     * @param _accessController Address of the access control contract
     */
    constructor(
        address _stakingToken,
        address _whitelistManager,
        address _accessController
    ) {
        if (_stakingToken == address(0) || _whitelistManager == address(0) ||
            _accessController == address(0)) revert ZeroAddress();

        stakingToken = IERC20(_stakingToken);
        whitelistManager = IWhitelistManager(_whitelistManager);
        accessController = IAccessController(_accessController);
    }

    /**
     * @notice Stake tokens into the system
     * @dev Requires provider to be whitelisted and stake at least MIN_STAKE
     * Tokens are transferred from the provider to this contract
     * @param amount The amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        if (!whitelistManager.isWhitelisted(msg.sender)) {
            revert NotWhitelisted(msg.sender);
        }
        if (amount < MIN_STAKE) {
            revert BelowMinimumStake(amount, MIN_STAKE);
        }

        uint256 oldStake = stakes[msg.sender];
        stakes[msg.sender] += amount;

        // Transfer tokens
        bool success = stakingToken.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert TransferFailed();
        }

        emit StakeUpdated(msg.sender, oldStake, stakes[msg.sender]);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Request to unstake tokens
     * @dev Creates an unstake request that can be fulfilled after LOCK_PERIOD
     * Only one active unstake request allowed per provider
     * @param amount The amount of tokens to unstake
     */
    function requestUnstake(uint256 amount) external nonReentrant {
        if (stakes[msg.sender] < amount) {
            revert InsufficientStake(msg.sender, amount, stakes[msg.sender]);
        }
        if (unstakeRequests[msg.sender].amount > 0) {
            revert ExistingUnstakeRequest(msg.sender);
        }

        unstakeRequests[msg.sender] = UnstakeRequest({
            amount: amount,
            timestamp: block.timestamp
        });

        emit UnstakeRequested(msg.sender, amount);
    }

    /**
     * @notice Cancel an existing unstake request
     * @dev Removes the unstake request and emits cancellation event
     */
    function cancelUnstakeRequest() external {
        UnstakeRequest memory request = unstakeRequests[msg.sender];
        if (request.amount == 0) {
            revert NoUnstakeRequest(msg.sender);
        }

        uint256 amount = request.amount;
        delete unstakeRequests[msg.sender];

        emit UnstakeRequestCancelled(msg.sender, amount);
    }

    /**
     * @notice Withdraw unstaked tokens after lock period
     * @dev Transfers tokens back to provider if lock period has passed
     * Requires an active unstake request and sufficient staked balance
     */
    function withdraw() external nonReentrant {
        UnstakeRequest memory request = unstakeRequests[msg.sender];
        if (request.amount == 0) {
            revert NoUnstakeRequest(msg.sender);
        }

        uint256 lockEndTime = request.timestamp + LOCK_PERIOD;
        if (block.timestamp < lockEndTime) {
            revert LockPeriodActive(msg.sender, lockEndTime - block.timestamp);
        }

        if (stakes[msg.sender] < request.amount) {
            revert InsufficientStake(msg.sender, request.amount, stakes[msg.sender]);
        }

        uint256 amount = request.amount;
        uint256 oldStake = stakes[msg.sender];
        stakes[msg.sender] -= amount;
        delete unstakeRequests[msg.sender];

        bool success = stakingToken.transfer(msg.sender, amount);
        if (!success) {
            revert TransferFailed();
        }

        emit StakeUpdated(msg.sender, oldStake, stakes[msg.sender]);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Apply a penalty to a provider's stake
     * @dev Only callable by authorized contracts (e.g., PenaltyManager)
     * Reduces the provider's stake by the penalty amount
     * @param cp Address of the computing provider
     * @param amount Amount of tokens to penalize
     */
    function applyPenalty(address cp, uint256 amount) external onlyContracts nonReentrant {
        if (stakes[cp] < amount) {
            revert InsufficientStake(cp, amount, stakes[cp]);
        }

        uint256 oldStake = stakes[cp];
        stakes[cp] -= amount;

        emit StakeUpdated(cp, oldStake, stakes[cp]);
    }

    // View functions

    /**
     * @notice Get the current staked balance of a provider
     * @param cp Address of the computing provider
     * @return uint256 Current staked balance
     */
    function getStakedBalance(address cp) external view returns (uint256) {
        return stakes[cp];
    }

    /**
     * @notice Check if a provider has an active unstake request
     * @param cp Address of the computing provider
     * @return bool True if there is an active unstake request
     */
    function hasUnstakeRequest(address cp) external view returns (bool) {
        return unstakeRequests[cp].amount > 0;
    }

    /**
     * @notice Get details of a provider's unstake request
     * @param cp Address of the computing provider
     * @return amount The requested unstake amount
     * @return requestTime The timestamp when the request was made
     */
    function getUnstakeRequestDetails(address cp)
    external
    view
    returns (uint256 amount, uint256 requestTime)
    {
        UnstakeRequest memory request = unstakeRequests[cp];
        return (request.amount, request.timestamp);
    }

    /**
     * @notice Get remaining lock time for an unstake request
     * @param cp Address of the computing provider
     * @return uint256 Remaining time in seconds, 0 if no request or lock expired
     */
    function getRemainingLockTime(address cp) external view returns (uint256) {
        UnstakeRequest memory request = unstakeRequests[cp];
        if (request.amount == 0) return 0;

        uint256 lockEndTime = request.timestamp + LOCK_PERIOD;
        if (block.timestamp >= lockEndTime) return 0;
        return lockEndTime - block.timestamp;
    }
}