### Local setup

1. Clone the repository
2. Install the dependencies
3. Start anvil
4. Update .env file with correct values (DEPLOYER_ADDRESS, DEPLOYER_PRIVATE_KEY, NODE_ADDRESS, NODE_ADDRESS_PRIVATE_KEY)
5. Deploy contracts
6. Update .env file with correct values (contract addresses)
7. Transfer funds to node address
8. Whitelist node address
9. Install python dependencies
10. Start the server

#### Clone the repository
```bash
git clone git@github.com:luminolabs/contracts.git
```

#### Install the dependencies
```bash
cd contracts
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

#### Transfer funds to node address (update .env file with correct values first)
```bash
export $(grep -v '^#' .env | xargs) && \
cast send $LUMINO_TOKEN_ADDRESS "transfer(address,uint256)" $NODE_ADDRESS $TOKENS_500 --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL && \
v=$(cast call $LUMINO_TOKEN_ADDRESS "balanceOf(address)" $NODE_ADDRESS --rpc-url $RPC_URL) && \
python -c "print(int('$v', 16) / 10**18)"
```

#### Whitelist node address
```bash
cast send $WHITELIST_MANAGER_ADDRESS "addCP(address)" $NODE_ADDRESS --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL && \                  
cast call $WHITELIST_MANAGER_ADDRESS "requireWhitelisted(address)" $NODE_ADDRESS --rpc-url $RPC_URL
```

#### Install python dependencies
```bash
pip install -r requirements.txt
```

#### Start the server
```bash
python node_client.py
```