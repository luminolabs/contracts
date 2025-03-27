
### Env variables
Set the environment variables for the proxy addresses and which contracts to upgrade:

```bash
export PROXY_ADMIN_ADDRESS=0x...
export TOKEN_PROXY_ADDRESS=0x...
export ACCESS_MANAGER_PROXY_ADDRESS=0x...
# Add other proxy addresses...

# Set which contracts to upgrade (true/false)
export UPGRADE_TOKEN=true
export UPGRADE_ACCESS_MANAGER=false
# Set other upgrade flags...
```

Run the script using Forge:
```bash
forge script UpgradeScript --rpc-url <your-rpc-url> --broadcast
```

### New Initializer
// If we are adding a new initializer function
// If you needed to call a hypothetical function 'reinitialize()' during upgrade:
bytes memory data = abi.encodeWithSelector(NewImplementation.reinitialize.selector);
proxyAdmin.upgradeAndCall(proxy, address(newImpl), data);