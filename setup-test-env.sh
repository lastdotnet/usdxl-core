
#!/bin/bash

# @dev
# This bash script ensures a clean repository
# and loads environment variables for testing and deploying GHO source code.

export NODE_OPTIONS="--max_old_space_size=16384"
set -e

export COVERAGE=true

echo "[BASH] Setting up testnet environment"

if [ ! "$COVERAGE" = true ]; then
    # remove hardhat and artifacts cache
    npm run ci:clean

    # compile contracts
    npm run compile
else
    echo "[BASH] Skipping compilation to keep coverage artifacts"
fi

# Export MARKET_NAME variable to use Aave market as testnet deployment setup
export MARKET_NAME="Test"

# Deploy stkAave in local
export ENABLE_REWARDS="true"
echo "[BASH] Testnet environment ready"
