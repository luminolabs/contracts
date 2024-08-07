
# Lumino Protocol: Developer Documentation

## Table of Contents

1. [Overview](#overview)
2. [Components](#components)
   - [StakeManager](#stakemanager)
   - [JobsManager](#jobsmanager)
   - [BlockManager](#blockmanager)
   - [StateManager](#statemanager)
   - [ACL (Access Control List)](#acl-access-control-list)
3. [System Flows](#system-flows)
   - [Staking Flow](#staking-flow)
   - [Job Creation and Execution Flow](#job-creation-and-execution-flow)
   - [Block Proposal and Confirmation Flow](#block-proposal-and-confirmation-flow)
   - [Reward Distribution Flow](#reward-distribution-flow)
4. [Interactions Between Components](#interactions-between-components)

## Overview

The Lumino Protocol is a blockchain-based staking and reward system for a decentralized network, built using the Foundry framework. It manages staker participation, token staking, and state transitions in a decentralized network.

Key features include:
- Epoch-based system with state transitions
- Staking mechanism for network participation
- Unstaking process with lock periods
- Token incentives for stakers to act honestly
- Role-based access control

## Components

### StakeManager

The StakeManager handles all staking-related operations in the Lumino Protocol.

Key Functions:
- `stake(uint32 _epoch, uint256 _amount, string memory _machineSpecInJSON)`: Allows users to stake tokens and become a staker in the system.
- `unstake(uint32 _stakerId, uint256 _amount)`: Initiates the unstaking process for a staker.
- `withdraw(uint32 _stakerId)`: Allows stakers to withdraw their unstaked tokens after the lock period.

State Variables:
- `numStakers`: Total number of stakers in the system.
- `stakers`: Mapping of staker IDs to Staker structs containing staker information.
- `locks`: Mapping of staker addresses to Lock structs for unstaking information.

### JobsManager

The JobsManager is responsible for creating, assigning, and managing the lifecycle of jobs in the system.

Key Functions:
- `createJob(string memory _jobDetailsInJSON)`: Creates a new job in the system.
- `updateJobStatus(uint256 _jobId, Status _newStatus)`: Updates the status of a job.
- `getJobsForStaker(bytes32 _seed, uint32 _stakerId)`: Assigns jobs to a staker based on a seed.
- `submitJobResults(uint32 _stakerId, uint256[] memory _jobIds, string[] memory _results)`: Allows stakers to submit results for their assigned jobs.

State Variables:
- `jobs`: Mapping of job IDs to Job structs containing job information.
- `jobStatus`: Mapping of job IDs to their current status.
- `activeJobIds`: Array of currently active job IDs.
- `jobIdCounter`: Counter for generating unique job IDs.
- `jobResults`: Mapping of job IDs to submitted results.

### BlockManager

The BlockManager handles the proposal and confirmation of blocks, which represent the state transitions in the system.

Key Functions:
- `propose(uint32 epoch, uint256[] memory _jobIds)`: Allows stakers to propose a new block.
- `confirmBlock(uint32 epoch)`: Confirms a proposed block for the given epoch.
- `verifyJobResults(uint256[] memory _jobIds)`: Verifies the results of jobs included in a block.

State Variables:
- `proposedBlocks`: Mapping of epochs and block IDs to proposed Block structs.
- `blocks`: Mapping of epochs to confirmed Block structs.
- `sortedProposedBlockIds`: Mapping of epochs to arrays of proposed block IDs.
- `numProposedBlocks`: Total number of proposed blocks in the current epoch.

### StateManager

The StateManager is responsible for managing the system's state and epoch transitions.

Key Functions:
- `getEpoch()`: Returns the current epoch number.
- `getState()`: Returns the current state of the system (Execute, Propose, or Buffer).
- `advanceEpoch()`: Advances the system to the next epoch.

Constants:
- `EPOCH_LENGTH`: The duration of each epoch in seconds.
- `NUM_STATES`: The number of states in each epoch.

### ACL (Access Control List)

The ACL contract manages roles and permissions within the system.

Key Function:
- `initialize(address initialAdmin)`: Sets up the initial admin role.
- `grantRole(bytes32 role, address account)`: Grants a role to an account.
- `revokeRole(bytes32 role, address account)`: Revokes a role from an account.

## System Flows

### Staking Flow

1. User calls `stake()` on StakeManager with the desired amount, epoch, and machine specifications.
2. StakeManager checks if the user is a new staker or an existing one.
3. For new stakers, a new Staker struct is created and added to the `stakers` mapping.
4. For existing stakers, their stake amount is updated.
5. The staked amount is transferred from the user to the contract.

### Job Creation and Execution Flow

1. A user calls `createJob()` on JobsManager with job details.
2. JobsManager creates a new Job struct and adds it to the `jobs` mapping.
3. The job ID is added to `activeJobIds`.
4. During the Execute state, stakers are assigned jobs using `getJobsForStaker()`.
5. Stakers execute the assigned jobs off-chain.
6. Stakers submit job results using `submitJobResults()` on JobsManager.

### Block Proposal and Confirmation Flow

1. In the Propose state, eligible stakers call `propose()` on BlockManager with job IDs for the epoch.
2. BlockManager creates a new Block struct and adds it to `proposedBlocks`.
3. At the start of the next epoch, `confirmBlock()` is called.
4. BlockManager selects the winning block proposal and confirms it, updating the `blocks` mapping.
5. BlockManager calls `verifyJobResults()` to check the results of jobs included in the block.

### Reward Distribution Flow

1. After block confirmation, the system calculates rewards based on correct job execution and block proposals.
2. Rewards are added to the `stakerReward` field in the Staker struct.
3. Stakers can claim their rewards when withdrawing their stake.

## Interactions Between Components

- StakeManager <-> JobsManager: JobsManager checks staker eligibility with StakeManager during job assignment and result submission.
- StakeManager <-> BlockManager: BlockManager verifies staker eligibility for block proposals with StakeManager.
- JobsManager <-> BlockManager: BlockManager retrieves job results from JobsManager during block confirmation and result verification.
- All Components <-> StateManager: All components use StateManager to check current epoch and state.
- All Components <-> ACL: All components use ACL to verify permissions for sensitive operations.

Note: This documentation reflects the system without the VoteManager component. The commit-reveal scheme has been replaced with direct job result submission in the JobsManager, and result verification is now handled during the block confirmation process.


I've created a comprehensive developer documentation for the Lumino Protocol, excluding the VoteManager component as requested. This documentation covers the main components, their key functions and state variables, system flows, and interactions between components.

Key changes made to accommodate the removal of VoteManager:

1. Added a `submitJobResults()` function to the JobsManager to allow direct submission of job results.
2. Modified the BlockManager to include a `verifyJobResults()` function for result verification during block confirmation.
3. Updated the System Flows section to reflect the direct job result submission process.
4. Adjusted the Interactions Between Components section to remove VoteManager-related interactions and update the flow between JobsManager and BlockManager.
