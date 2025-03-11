#!/bin/bash

set -e  # Exit immediately if a command exits with non-zero status

# Define paths
CONTRACTS_DIR="."
ADDRESSES_JSON="./addresses.json"

# Step 1: Deploy contracts using Forge script
echo "Deploying contracts..."
cd "$CONTRACTS_DIR"

# Run the deployment script and capture the output
FORGE_OUT=$(mktemp)
forge script script/Deploy.s.sol:DeploymentScript --rpc-url $(grep "RPC_URL" .env | cut -d'=' -f2) --private-key $(grep "DEPLOYER_PRIVATE_KEY" .env | cut -d'=' -f2) --broadcast | tee "$FORGE_OUT"

# Step 2: Extract contract addresses from deployment output
echo "Extracting contract addresses..."

# Initialize JSON file
echo "{" > "$ADDRESSES_JSON"

# Process proxy contract addresses
grep "(Proxy):" "$FORGE_OUT" | while read -r line; do
    CONTRACT_NAME=$(echo "$line" | cut -d':' -f1 | sed 's/(Proxy)//' | tr -d '[:space:]')
    ADDRESS=$(echo "$line" | cut -d':' -f2 | tr -d '[:space:]')
    echo "  \"$CONTRACT_NAME\": \"$ADDRESS\"," >> "$ADDRESSES_JSON"
done

# Add EpochManager (no proxy)
grep "EpochManager:" "$FORGE_OUT" | while read -r line; do
    ADDRESS=$(echo "$line" | cut -d':' -f2 | tr -d '[:space:]')
    echo "  \"EpochManager\": \"$ADDRESS\"" >> "$ADDRESSES_JSON"
done

# Fix the JSON file (remove trailing comma if needed)
# sed -i '$ s/,$//' "$ADDRESSES_JSON"

# Close the JSON object
echo "}" >> "$ADDRESSES_JSON"

# Clean up
rm -f "$FORGE_OUT"

echo "Deployment completed and addresses stored in $ADDRESSES_JSON"
