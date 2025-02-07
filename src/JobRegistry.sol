// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IJobRegistry.sol";
import "./interfaces/IJobPaymentManager.sol";
import "./interfaces/INodeRegistryCore.sol";
import "./interfaces/IJobPaymentEscrow.sol";
import "./interfaces/IAccessController.sol";

/**
 * @title JobRegistry
 * @dev Contract for managing the lifecycle of computing jobs in the Lumino network.
 * Handles job submission, status tracking, and node assignment while enforcing
 * payment escrow requirements and access controls.
 *
 * Key functionalities:
 * - Job submission with escrow validation
 * - Status tracking through job lifecycle states
 * - Node assignment tracking
 * - Access control for operators and authorized contracts
 *
 * The contract maintains mappings for:
 * - Individual job details
 * - Jobs grouped by status
 * - Jobs by submitter address
 */
contract JobRegistry is IJobRegistry {
    // Core contracts
    /// @notice Manager for handling job payments
    IJobPaymentManager public immutable paymentManager;

    /// @notice Registry for node information and validation
    INodeRegistryCore public immutable nodeRegistry;

    /// @notice Escrow contract for securing job payments
    IJobPaymentEscrow public immutable paymentEscrow;

    /// @notice Contract handling role-based access control
    IAccessController public immutable accessController;

    // State variables
    /// @dev Counter for generating unique job IDs
    uint256 private jobCounter;

    /// @dev Mapping from job ID to job details
    mapping(uint256 => Job) private jobs;

    /// @dev Mapping from job status to array of job IDs
    mapping(JobStatus => uint256[]) private jobsByStatus;

    /// @dev Mapping from submitter address to array of their job IDs
    mapping(address => uint256[]) private submitterJobs;

    /**
     * @dev Constructor for JobRegistry
     * @param _paymentManager Address of the payment manager contract
     * @param _nodeRegistry Address of the node registry contract
     * @param _paymentEscrow Address of the payment escrow contract
     * @param _accessController Address of the access controller contract
     */
    constructor(
        address _paymentManager,
        address _nodeRegistry,
        address _paymentEscrow,
        address _accessController
    ) {
        paymentManager = IJobPaymentManager(_paymentManager);
        nodeRegistry = INodeRegistryCore(_nodeRegistry);
        paymentEscrow = IJobPaymentEscrow(_paymentEscrow);
        accessController = IAccessController(_accessController);
    }

    /**
     * @notice Submit a new job to the registry
     * @dev Creates a new job entry after validating submitter has sufficient escrow balance
     * @param jobArgs Job arguments/parameters in string format
     * @param requiredPool Required compute pool identifier
     * @return jobId Unique identifier for the submitted job
     * @custom:throws InsufficientBalance if submitter lacks minimum escrow balance
     */
    function submitJob(
        string calldata jobArgs,
        uint256 requiredPool
    ) external returns (uint256);

    /**
     * @notice Update the status of an existing job
     * @dev Can only be called by operators or authorized contracts
     * @param jobId Job identifier
     * @param newStatus New status to set for the job
     * @custom:throws JobNotFound if job ID doesn't exist
     * @custom:throws Unauthorized if caller lacks required role
     */
    function updateJobStatus(
        uint256 jobId,
        JobStatus newStatus
    ) external;

    /**
     * @notice Assign a node to handle a job
     * @dev Can only be called by authorized contracts
     * @param jobId Job identifier
     * @param nodeId Node identifier
     * @custom:throws NodeNotActive if specified node is not active
     * @custom:throws InvalidJobStatus if job is not in NEW status
     * @custom:throws Unauthorized if caller lacks CONTRACTS_ROLE
     */
    function assignNode(
        uint256 jobId,
        uint256 nodeId
    ) external;

    /**
     * @notice Retrieve details for a specific job
     * @param jobId Job identifier
     * @return Job struct containing all job details
     * @custom:throws JobNotFound if job ID doesn't exist
     */
    function getJob(uint256 jobId) external view returns (Job memory);

    /**
     * @notice Get all jobs with a specific status
     * @param status Job status to query
     * @return uint256[] Array of job IDs with the specified status
     */
    function getJobsByStatus(JobStatus status) external view returns (uint256[] memory);

    /**
     * @notice Get all jobs submitted by a specific address
     * @param submitter Address of the job submitter
     * @return uint256[] Array of job IDs submitted by the address
     */
    function getJobsBySubmitter(address submitter) external view returns (uint256[] memory);
}