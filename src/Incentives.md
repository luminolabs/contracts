
## Incentive Mechanism Analysis

1. **Rewards**:
   - `LEADER_REWARD`: Awarded to leaders who successfully start assignment rounds
   - `JOB_AVAILABILITY_REWARD`: Given to nodes that participated by revealing secrets
   - `DISPUTER_REWARD`: Given to the account that calls `processAll()` to trigger incentive distribution

2. **Penalties**:
   - `LEADER_NOT_EXECUTED_PENALTY`: Applied to leaders who don't start assignment rounds
   - `JOB_NOT_CONFIRMED_PENALTY`: Applied to nodes that don't confirm assigned jobs
   - `MAX_PENALTIES_BEFORE_SLASH`: Threshold after which a node's entire stake is slashed

3. **Staking Requirements**:
   - `STAKE_PER_RATING`: Amount of tokens needed per compute rating unit
   - Nodes with higher compute ratings require more stake

## Values for testnet

### Token Supply and Denominations

For a testnet, I recommend:

- **Total supply**: 100,000,000 tokens (already set in your `LuminoToken.sol`)
- **Testnet distribution**: 
  - 60% for node operators (60M tokens)
  - 20% for job submitters (20M tokens)
  - 20% for protocol treasury/incentives (20M tokens)

### Incentive Constants

```solidity
// Leader and node incentives
uint256 public constant LEADER_REWARD = 5 * 1e18;                   // 5 tokens
uint256 public constant JOB_AVAILABILITY_REWARD = 1 * 1e18;         // 1 token
uint256 public constant DISPUTER_REWARD = 0.5 * 1e18;               // 0.5 tokens
uint256 public constant LEADER_NOT_EXECUTED_PENALTY = 15 * 1e18;    // 15 tokens
uint256 public constant JOB_NOT_CONFIRMED_PENALTY = 10 * 1e18;      // 10 tokens
uint256 public constant MAX_PENALTIES_BEFORE_SLASH = 10;            // 10 penalties

// Job submission
uint256 public constant MIN_BALANCE_TO_SUBMIT = 1 * 1e18;           // 1 token

// Node management
uint256 public constant WHITELIST_COOLDOWN = 3 days;                // 3 days
uint256 public constant STAKE_PER_RATING = 10 * 1e18;               // 10 tokens per rating
```

## Rationale for Constants

### Rewards

1. **LEADER_REWARD = 5 tokens**
   - Higher to properly incentivize leaders
   - Leaders have critical responsibilities, so their rewards should be higher than regular nodes
   - For a testnet with 1,000 epochs, this would distribute up to 5,000 tokens to leaders (5% of allocated incentives)

2. **JOB_AVAILABILITY_REWARD = 1 token**
   - Lower than leader rewards since just revealing secrets is less work
   - Still meaningful enough to encourage participation
   - With 100 nodes participating in 1,000 epochs, this would distribute up to 100,000 tokens (manageable for testnet)

3. **DISPUTER_REWARD = 0.5 tokens**
   - Lower than other rewards as this is a maintenance function
   - Still provides incentive for someone to call the function
   - Prevents "free-riding" where everyone waits for others to process rewards

### Penalties

1. **LEADER_NOT_EXECUTED_PENALTY = 15 tokens**
   - Higher than the reward (15 vs 5) to discourage neglecting leader duties
   - The penalty is 3x the reward to make being a reliable leader net positive
   - High enough to be a deterrent but not completely devastating for testnet participants

2. **JOB_NOT_CONFIRMED_PENALTY = 10 tokens**
   - Substantial enough to discourage neglecting job confirmations
   - Higher than the availability reward to create positive incentives
   - Balanced to not be overly punitive during testnet phases

3. **MAX_PENALTIES_BEFORE_SLASH = 10**
   - 10 for testnet to detect bad actors more quickly
   - At 10 failures, node has demonstrated a pattern of unreliability
   - With penalties of 10-15 tokens per failure, they'll have lost 100-150 tokens before slashing

### Staking and Other Parameters

1. **MIN_BALANCE_TO_SUBMIT = 1 token**
   - Low barrier to entry for job submitters in testnet
   - Prevents spam submissions while keeping the system accessible

2. **WHITELIST_COOLDOWN = 3 days**
   - Shorter than your 7 days to allow more flexibility during testnet
   - Still long enough to prevent rapid churning of providers

3. **STAKE_PER_RATING = 10 tokens**
   - Increased from 1 to 10 to ensure nodes have meaningful stake at risk
   - For a compute rating of 10, node would need to stake 100 tokens
   - Makes the economics more realistic - higher compute power requires higher stake

## Economic Balance

These values create a balanced economic system:

- **Rewards vs. Penalties**: Penalties are 3x rewards to discourage misbehavior
- **Risk vs. Reward**: For a node with compute rating 10 (100 token stake):
  - Could earn ~1 token per epoch for availability
  - Leader would earn extra 5 tokens when elected
  - Risk of 10-15 token penalties for non-performance
  - Full stake slashing after 10 penalties

This creates positive expected value for honest participants while having strong disincentives for poor performance or attacks.

For a testnet environment, these values should provide meaningful economic signals while not being overly punitive for participants who are learning the system.