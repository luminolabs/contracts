# Lumino Smart Contracts

This repository contains the smart contracts for the Lumino Network, a decentralized computing platform.

## Overview

The Lumino Network contracts manage the following aspects of the platform:
- Node registration and management
- Job submission and execution
- Staking and escrow mechanisms
- Epoch management
- Leader election
- Incentive distribution
- Access control

## Requirements

- [Foundry](https://book.getfoundry.sh/) (forge, anvil, cast)
- Solidity ^0.8.19

## Project Structure

- `/src`: Main contract implementations
  - `/abstracts`: Abstract contract implementations
  - `/interfaces`: Contract interfaces
  - `/libraries`: Shared libraries
- `/test`: Contract tests
  - Unit tests for individual contracts
  - End-to-end tests for system flows
- `/script`: Deployment scripts

## Setup and Installation

1. Clone the repository
2. Install dependencies: `forge install`
3. Build the contracts: `forge build`

## Testing

Run all tests:
```
forge test
```

Run specific tests:
```
forge test --match-path test/EpochManager.t.sol -vvv
```

## Deployment

### Local Development

1. Start a local Ethereum node:
```
anvil
```

2. Create environment file:
```
cp example.env .env
```

3. Update `.env` with appropriate values for local development

4. Export the environment variables:
```
export $(grep -v '^#' .env | xargs)
```

5. Run the deployment script:
```
./deploy.sh
```

### Testnet Deployment

1. Configure `.env` with network-specific values:
   - RPC URL
   - Deployer private key

2. Export the environment variables:
```
export $(grep -v '^#' .env | xargs)
```

3. Run the deployment script:
```
./deploy.sh
```

The deployment will create an `addresses.json` file containing all deployed contract addresses.

## Contract Interactions

Use the `lumino-contracts-client` python library to interact with the deployed contracts.