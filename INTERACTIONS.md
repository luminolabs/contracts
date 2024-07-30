# Lumino Staking System: Contract Interactions

This document outlines the key interactions between contracts in the Lumino Staking System. Understanding these interactions is crucial for developers working on the system or integrating with it.

## Overview

The Lumino Staking System consists of several interconnected contracts, each responsible for a specific aspect of the system. The main contracts and their primary responsibilities are:

1. ACL (Access Control List)
2. StakeManager
3. JobsManager
4. VoteManager
5. BlockManager
6. StateManager

## Key Interactions

### 1. ACL (Access Control List)

- **Interacts with**: All other contracts
- **When**: During function calls that require role-based access control
- **How**: Other contracts inherit from ACL and use its modifiers to restrict access to certain functions

### 2. StakeManager

- **Interacts with**: JobsManager, VoteManager, BlockManager
- **When**:
    - Staking: When a user stakes tokens
    - Unstaking: When a user requests to unstake tokens
    - Slashing: When a staker needs to be penalized
- **How**:
    - Provides stake information to other contracts
    - Updates stake amounts based on rewards or penalties

### 3. JobsManager

- **Interacts with**: StakeManager, VoteManager, BlockManager
- **When**:
    - Job Creation: When a new job is submitted to the network
    - Job Assignment: When jobs are assigned to stakers
    - Job Completion: When a job is completed and needs verification
- **How**:
    - Requests stake information from StakeManager for job assignment
    - Provides job information to VoteManager for voting process
    - Submits completed jobs to BlockManager for inclusion in blocks

### 4. VoteManager

- **Interacts with**: StakeManager, JobsManager, BlockManager
- **When**:
    - Commit Phase: When stakers commit their votes
    - Reveal Phase: When stakers reveal their votes
    - Vote Tallying: When votes need to be counted to determine consensus
- **How**:
    - Verifies staker eligibility with StakeManager
    - Retrieves job information from JobsManager for voting
    - Provides voting results to BlockManager for block creation

### 5. BlockManager

- **Interacts with**: StakeManager, JobsManager, VoteManager
- **When**:
    - Block Proposal: When a new block is proposed
    - Block Confirmation: When a block is confirmed
- **How**:
    - Verifies proposer's stake with StakeManager
    - Includes completed jobs from JobsManager in blocks
    - Uses voting results from VoteManager to determine valid blocks

### 6. StateManager

- **Interacts with**: All other contracts
- **When**: During state transitions between epochs and phases
- **How**: Provides current state and epoch information to other contracts

## Interaction Flow Examples

1. **Staking Process**:
   User -> StakeManager (stake) -> JobsManager (assign jobs) -> VoteManager (enable voting)

2. **Job Execution and Voting**:
   JobsManager (create job) -> StakeManager (check eligibility) -> VoteManager (commit and reveal votes) -> BlockManager (include in block)

3. **Block Creation and Confirmation**:
   BlockManager (propose block) -> StakeManager (verify proposer) -> VoteManager (tally votes) -> BlockManager (confirm block)

## Important Notes

- All contracts use the `Initializable` pattern for upgradeability.
- The `ACL` contract ensures that only authorized addresses can perform certain actions across the system.
- The `StateManager` is crucial for synchronizing the actions of other contracts based on the current epoch and state.

This document provides a high-level overview of contract interactions. For detailed function calls and event emissions, please refer to the individual contract documentation.