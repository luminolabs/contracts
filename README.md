# Lumino Contracts

A blockchain-based staking and reward system for a decentralized network, built using the Foundry framework.

## Overview

The Lumino Staking System is designed to manage staker participation, token staking, and state transitions in a decentralized network. Key features include:

- Epoch-based system with state transitions
- Staking mechanism for network participation
- Unstaking process with lock periods
- 2-phase Commit-Reveal for Jobs Verification and assignment
- Token Incentives for stakers to act honestly
- Role-based access control

## Lumino Protocol: Detailed Component and Flow Documentation

### Table of Contents

- [Components](#components)
    - [StakeManager](#stakemanager)
    - [VoteManager](#votemanager)
    - [JobsManager](#jobsmanager)
    - [BlockManager](#blockmanager)
    - [StateManager](#statemanager)
    - [ACL (Access Control List)](#acl-access-control-list)
- [System Flows](#2-system-flows)
   - [Staking Flow](#21-staking-flow)
   - [Job Creation and Execution Flow](#22-job-creation-and-execution-flow)
   - [Commit-Reveal Flow](#23-commit-reveal-flow)
   - [Block Proposal and Confirmation Flow](#24-block-proposal-and-confirmation-flow)
   - [Reward Distribution Flow](#25-reward-distribution-flow)
- [Interactions Between Components](/INTERACTIONS.md)

## Components

### StakeManager

The StakeManager is responsible for handling all staking-related operations in the Lumino Protocol.

Key Functions:
- `stake(uint32 _epoch, uint256 _amount, string memory _machineSpecInJSON)`: Allows users to stake tokens and become a staker in the system.
- `unstake(uint32 _stakerId, uint256 _amount)`: Initiates the unstaking process for a staker.
- `withdraw(uint32 _stakerId)`: Allows stakers to withdraw their unstaked tokens after the lock period.

State Variables:
- `numStakers`: Total number of stakers in the system.
- `stakers`: Mapping of staker IDs to Staker structs containing staker information.
- `locks`: Mapping of staker addresses to Lock structs for unstaking information.

### VoteManager

The VoteManager handles the commit-reveal scheme for job result submission and verification.

Key Functions:
- `commit(uint32 epoch, bytes32 commitment)`: Allows stakers to commit their job results without revealing them.
- `reveal(uint32 epoch, Structs.JobVerifier[] memory results, bytes memory signature)`: Allows stakers to reveal their previously committed results.

State Variables:
- `commitments`: Mapping of staker IDs to Commitment structs containing commitment information.
- `assignedJob`: Mapping of epoch and staker ID to assigned jobs and their results.
- `salt`: A value used in the commit-reveal process to prevent result manipulation.

### JobsManager

The JobsManager is responsible for creating, assigning, and managing the lifecycle of jobs in the system.

Key Functions:
- `createJob(string memory _jobDetailsInJSON)`: Creates a new job in the system.
- `updateJobStatus(uint256 _jobId, Status _newStatus)`: Updates the status of a job.
- `getJobsForStaker(bytes32 _seed, uint32 _stakerId)`: Assigns jobs to a staker based on a seed.

State Variables:
- `jobs`: Mapping of job IDs to Job structs containing job information.
- `jobStatus`: Mapping of job IDs to their current status.
- `activeJobIds`: Array of currently active job IDs.
- `jobIdCounter`: Counter for generating unique job IDs.

### BlockManager

The BlockManager handles the proposal and confirmation of blocks, which represent the state transitions in the system.

Key Functions:
- `propose(uint32 epoch, uint256[] memory _jobIds)`: Allows stakers to propose a new block.
- `confirmBlock(uint32 epoch)`: Confirms a proposed block for the given epoch.

State Variables:
- `proposedBlocks`: Mapping of epochs and block IDs to proposed Block structs.
- `blocks`: Mapping of epochs to confirmed Block structs.
- `sortedProposedBlockIds`: Mapping of epochs to arrays of proposed block IDs.
- `numProposedBlocks`: Total number of proposed blocks in the current epoch.

### StateManager

The StateManager is responsible for managing the system's state and epoch transitions.

Key Functions:
- `getEpoch()`: Returns the current epoch number.
- `getState(uint8 buffer)`: Returns the current state of the system (Commit, Reveal, Propose, or Buffer).

Constants:
- `EPOCH_LENGTH`: The duration of each epoch in seconds.
- `NUM_STATES`: The number of states in each epoch.

### ACL (Access Control List)

The ACL contract manages roles and permissions within the system.

Key Function:
- `initialize(address initialAdmin)`: Sets up the initial admin role.

## System Flows

### Staking Flow

1. User calls `stake()` on StakeManager with the desired amount and epoch.
2. StakeManager checks if the user is a new staker or existing one.
3. For new stakers, a new Staker struct is created and added to the `stakers` mapping.
4. For existing stakers, their stake amount is updated.
5. The staked amount is transferred from the user to the contract.

### Creation and Execution Flow

1. A user calls `createJob()` on JobsManager with job details.
2. JobsManager creates a new Job struct and adds it to the `jobs` mapping.
3. The job ID is added to `activeJobIds`.
4. During the Commit state, stakers are assigned jobs using `getJobsForStaker()`.
5. Stakers execute the assigned jobs off-chain.

### Commit-Reveal Flow

1. In the Commit state, stakers call `commit()` on VoteManager with a hash of their job results.
2. VoteManager stores the commitment in the `commitments` mapping.
3. In the Reveal state, stakers call `reveal()` on VoteManager with their actual results and a signature.
4. VoteManager verifies the revealed results against the commitment and processes the results.

### Block Proposal and Confirmation Flow

1. In the Propose state, eligible stakers call `propose()` on BlockManager with job IDs for the epoch.
2. BlockManager creates a new Block struct and adds it to `proposedBlocks`.
3. At the start of the next epoch, `confirmBlock()` is called.
4. BlockManager selects the winning block proposal and confirms it, updating the `blocks` mapping.

### Reward Distribution Flow

1. After block confirmation, the system calculates rewards based on correct job execution and block proposals.
2. Rewards are added to the `stakerReward` field in the Staker struct.
3. Stakers can claim their rewards when withdrawing their stake.

## Interactions Between Components

- StakeManager <-> VoteManager: VoteManager checks staker eligibility with StakeManager during commit and reveal.
- StakeManager <-> BlockManager: BlockManager verifies staker eligibility for block proposals with StakeManager.
- JobsManager <-> VoteManager: VoteManager retrieves active jobs from JobsManager for result processing.
- BlockManager <-> VoteManager: BlockManager uses VoteManager to verify revealed results during block confirmation.
- All Components <-> StateManager: All components use StateManager to check current epoch and state.
- All Components <-> ACL: All components use ACL to verify permissions for sensitive operations.

More on interactions can be found in [`Interactions`](/INTERACTIONS.md)