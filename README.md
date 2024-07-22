# Lumino Staking System

This project implements a blockchain-based staking and reward system for a decentralized network, built using the Foundry framework.

## Project Overview

The Lumino Staking System is designed to manage staker participation, token staking, and state transitions in a decentralized network. Key features include:

- Epoch-based system with state transitions
- Staking mechanism for network participation
- Unstaking process with lock periods
- Role-based access control

### Main Components

1. **ACL (Access Control List)**: Manages role-based access control.
2. **StakeManager**: Handles staking, unstaking, withdrawing, and rewarding functions.
3. **StateManager**: Manages system states and epochs.
4. **Constants**: Defines system-wide constants.
5. **StakeManagerStorage**: Defines storage structures for the StakeManager.

## Project Structure

- `src/Core/`: Contains the main contract files
    - `ACL.sol`: Access Control List implementation
    - `StakeManager.sol`: Manages staking operations
    - `StateManager.sol`: Handles state and epoch transitions
    - `storage/`: Contains storage-related contracts
- `lib/`: External libraries and dependencies
- `test/`: Contains test files, including `StateManager.t.sol`

## Key Concepts

1. **Epochs**: The system operates in epochs, each lasting 1200 seconds (20 minutes).
2. **States**: Each epoch is divided into Commit, Reveal, Propose, and Buffer states.
3. **Staking**: Users stake $LUMINO tokens to participate in the network.
4. **Unstaking**: Tokens are locked for a period when unstaking before they can be withdrawn.
5. **Machine Specifications**: Stakers provide JSON-formatted machine specifications.

For more detailed information about each component, please refer to the individual contract files in the `src/Core/` directory.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
