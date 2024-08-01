# Lumino Staking System: Contract Interactions 

## Overview

The Lumino Staking System consists of several interconnected contracts, each responsible for a specific aspect of the system. The main contracts and their primary responsibilities are:

1. ACL (Access Control List): Manages roles and permissions
2. StakeManager: Handles staking, unstaking, and stake-related operations
3. JobsManager: Manages job creation, assignment, and lifecycle
4. VoteManager: Handles the commit-reveal scheme for job result submission
5. BlockManager: Manages block proposals and confirmations
6. StateManager: Manages system state and epoch transitions

## Key Interactions

### 1. ACL (Access Control List)

- **Interacts with**: All other contracts
- **When**: During function calls that require role-based access control
- **How**: Other contracts inherit from ACL and use its modifiers to restrict access to certain functions
- **Key Functions**:
  - `grantRole(bytes32 role, address account)`
  - `revokeRole(bytes32 role, address account)`
- **Examples of Roles**:
  - `DEFAULT_ADMIN_ROLE`
  - `STAKER_ROLE`

### 2. StakeManager

- **Interacts with**: JobsManager, VoteManager, BlockManager
- **When**:
  - Staking: When a user stakes tokens
  - Unstaking: When a user requests to unstake tokens
  - Slashing: When a staker needs to be penalized
- **How**:
  - Provides stake information to other contracts
  - Updates stake amounts based on rewards or penalties
- **Key Functions**:
  - `stake(uint32 _epoch, uint256 _amount, string memory _machineSpecInJSON)`
  - `unstake(uint32 _stakerId, uint256 _amount)`
  - `withdraw(uint32 _stakerId)`
- **Important State Variables**:
  - `stakers`: Mapping of staker IDs to Staker structs
  - `locks`: Mapping of staker addresses to Lock structs

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
- **Key Functions**:
  - `createJob(string memory _jobDetailsInJSON)`
  - `updateJobStatus(uint256 _jobId, Status _newStatus)`
  - `getJobsForStaker(bytes32 _seed, uint32 _stakerId)`
- **Important State Variables**:
  - `jobs`: Mapping of job IDs to Job structs
  - `jobsPerStaker`: Number of jobs assigned to each staker

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
- **Key Functions**:
  - `commit(uint32 epoch, bytes32 commitment)`
  - `reveal(uint32 epoch, Structs.JobVerifier[] memory results, bytes memory signature)`
- **Important State Variables**:
  - `commitments`: Mapping of staker IDs to Commitment structs
  - `assignedJob`: Mapping of epoch and staker ID to assigned jobs

### 5. BlockManager

- **Interacts with**: StakeManager, JobsManager, VoteManager
- **When**:
  - Block Proposal: When a new block is proposed
  - Block Confirmation: When a block is confirmed
- **How**:
  - Verifies proposer's stake with StakeManager
  - Includes completed jobs from JobsManager in blocks
  - Uses voting results from VoteManager to determine valid blocks
- **Key Functions**:
  - `propose(uint32 epoch, uint256[] memory _jobIds)`
  - `confirmBlock(uint32 epoch)`
- **Important State Variables**:
  - `proposedBlocks`: Mapping of epochs and block IDs to proposed Block structs
  - `sortedProposedBlockIds`: Mapping of epochs to arrays of proposed block IDs

### 6. StateManager

- **Interacts with**: All other contracts
- **When**: During state transitions between epochs and phases
- **How**: Provides current state and epoch information to other contracts
- **Key Functions**:
  - `getEpoch()`
  - `getState(uint8 buffer)`
- **Important Constants**:
  - `EPOCH_LENGTH`: Duration of each epoch in seconds
  - `NUM_STATES`: Number of states in each epoch

## Interaction Flow Examples

1. **Staking Process**:
   - User calls `StakeManager.stake(epoch, amount, machineSpec)`
   - StakeManager updates `stakers` mapping
   - JobsManager assigns jobs using `getJobsForStaker(seed, stakerId)`
   - VoteManager enables voting for the staker

2. **Job Execution and Voting**:
   - User calls `JobsManager.createJob(jobDetails)`
   - JobsManager calls `StakeManager.getStake(stakerId)` to check eligibility
   - Staker calls `VoteManager.commit(epoch, commitment)` to commit votes
   - Staker calls `VoteManager.reveal(epoch, results, signature)` to reveal votes
   - BlockManager includes job results in the proposed block

3. **Block Creation and Confirmation**:
   - Staker calls `BlockManager.propose(epoch, jobIds)`
   - BlockManager calls `StakeManager.getStake(proposerId)` to verify proposer
   - VoteManager provides voting results to BlockManager
   - BlockManager calls `confirmBlock(epoch)` to finalize the block

## State Transitions

The system transitions through four states in each epoch: Commit, Reveal, Propose, and Buffer. The StateManager's `getState()` function determines the current state, which affects how other contracts interact:

- Commit: Stakers commit their job results (VoteManager)
- Reveal: Stakers reveal their commitments (VoteManager)
- Propose: Stakers propose new blocks (BlockManager)
- Buffer: A short period between states to account for network delays

## Error Handling

The system handles various error scenarios:

- Insufficient stake: StakeManager reverts the transaction
- Missed reveals: VoteManager may penalize the staker
- Invalid job results: BlockManager may exclude the results from the block

Proper error handling ensures the system's reliability and fairness.

## Gas Considerations

To optimize gas usage in contract interactions:

- Use batch operations where possible (e.g., revealing multiple job results at once)
- Implement gas-efficient data structures (e.g., using mappings instead of arrays for large datasets)
- Minimize on-chain storage by using events for less critical data

## Events

Important events emitted during interactions include:

- `Staked(address indexed staker, uint256 amount)`
- `JobCreated(uint256 indexed jobId, address indexed creator)`
- `BlockProposed(uint32 indexed epoch, uint32 indexed blockId, address proposer)`
- `BlockConfirmed(uint32 indexed epoch, uint32 indexed blockId)`

These events facilitate off-chain tracking and system monitoring.

## Visual Representation

Here are diagrams showing the main contract interactions:

![State Transition Flow](/assets/stateTransition.png)

![staking Diagram](/assets/stakingSquenceDiagram.png)

![Commit Reveal Flow](/assets/CommitRevealFlow.png)

![BlockManagerFlow](/assets/BlockManagerFlow.png)

## Security Considerations

- Access Control: ACL ensures only authorized addresses can perform sensitive operations
- Input Validation: All contracts implement thorough input validation to prevent malicious inputs
- Commit-Reveal Scheme: Prevents result manipulation in the voting process
- Slashing: Discourages malicious behavior by penalizing bad actors

## Upgradeability

The contracts use the `Initializable` pattern for upgradeability:

- Allows for future improvements and bug fixes
- Requires careful management of storage layouts during upgrades
- May affect contract interactions if new functions or state variables are introduced

When upgrading, ensure all contracts are compatible with the new versions to maintain system integrity.