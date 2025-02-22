## End-to-end test flows:


1. Node Lifecycle Flows:
   - Node Registration Flow:
     * Whitelisting CP
     * Token deposit for staking
     * Node registration with compute rating
     * Verification of stake requirements

   - Node Exit Flow:
     * Request withdrawal
     * Wait lock period
     * Complete withdrawal
     * Node unregistration

2. Job Lifecycle Flow:
   - Job Submission:
     * Token deposit by job submitter
     * Job creation with parameters
     * Validation of pool requirements

   - Job Assignment:
     * Leader election process
     * Assignment round execution
     * Node selection and job distribution

   - Job Execution:
     * Node confirmation
     * Job completion 
     * Payment processing
     * Token transfers

3. Epoch State Transition Flow:
   - Complete epoch cycle:
     * Commit phase with multiple nodes
     * Reveal phase participation
     * Leader election 
     * Execute phase with assignments
     * Confirm phase with job status updates
     * Dispute phase with penalties/rewards

4. Incentive Flow:
   - Rewards:
     * Leader rewards for assignment
     * Node rewards for availability
     * Rewards distribution timing

   - Penalties:
     * Missing assignments
     * Failed confirmations
     * Accumulated penalties leading to slash
