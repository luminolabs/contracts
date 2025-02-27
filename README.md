### Local setup

1. Clone the repository
2. Install forge
3. Start anvil
4. Update .env file with correct values (use an address/private key from the anvil output)
5. Deploy contracts

#### Clone the repository
```bash
git clone git@github.com:luminolabs/contracts.git
```

#### Start anvil
```bash
anvil --chain-id 14
```

#### Deploy contracts (update .env file with correct values first)
```bash
export $(grep -v '^#' .env | xargs) && \
forge script script/Deploy.s.sol:DeploymentScript --rpc-url http://127.0.0.1:8545 --broadcast --sender $DEPLOYER_ADDRESS
```