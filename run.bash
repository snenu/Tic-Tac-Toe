#!/usr/bin/env bash

set -eu

echo "=========================================="
echo "  TicTacToe on Linera - Starting Setup"
echo "=========================================="
echo ""
echo "⏳ Please wait - this will take 1-2 minutes..."
echo "   The frontend will be available at http://localhost:5173"
echo "   once setup is complete."
echo ""

# Clear /tmp Linera dirs (helper may use e.g. /tmp/.tmpXXXX)
echo ">>> Cleaning up previous Linera temp directories..."
for tmpd in /tmp/.tmp* /tmp/linera*; do
  if [ -d "$tmpd" ]; then
    echo "  - Clearing: $tmpd"
    rm -rf "$tmpd" 2>/dev/null || true
  fi
done

eval "$(linera net helper)" 2>/dev/null || true

# Clear the path the helper just set (it may point to existing storage from a previous run)
echo ">>> Cleaning up helper storage paths..."
for var in LINERA_NETWORK LINERA_NETWORK_DIR LINERA_STORAGE LINERA_NETWORK_STORAGE LINERA_NET; do
  if [ -n "${!var:-}" ]; then
    path="${!var}"
    path="${path#rocksdb:}"  # strip rocksdb: prefix if present
    if [ -f "$path" ]; then
      path="$(dirname "$path")"
    fi
    if [ -d "$path" ]; then
      echo "  - Clearing: $path"
      rm -rf "$path" 2>/dev/null || true
    fi
  fi
done 2>/dev/null || true

echo ""
echo ">>> Starting Linera network..."
echo "  This may take 10-15 seconds..."
linera_spawn linera net up --with-faucet 2>&1 | grep -v "xargs.*kill" || {
  echo "  Warning: linera_spawn had issues, starting network directly..."
  linera net up --with-faucet &
}
echo "  Waiting for network to be ready..."
sleep 10  # Give network time to fully start

export LINERA_FAUCET_URL=http://localhost:8080
echo "  ✓ Linera network started"
echo "  ✓ Faucet URL: $LINERA_FAUCET_URL"
echo ""

# Initialize wallet (ignore error if already exists)
echo ">>> Initializing wallet..."
set +e
linera wallet init --faucet="$LINERA_FAUCET_URL" 2>&1 | grep -v "already exists" || true
set -e

# Request chain (may already exist, that's okay)
echo ">>> Requesting chain..."
set +e
CHAIN_OUTPUT=$(linera wallet request-chain --faucet="$LINERA_FAUCET_URL" 2>&1)
echo "$CHAIN_OUTPUT" | grep -v "already" || true
CHAIN_ID=$(echo "$CHAIN_OUTPUT" | grep -oE '[a-f0-9]{64}' | head -1)
set -e
echo "  ✓ Chain ID: ${CHAIN_ID:-<pending>}"
echo ""

# Build tictactoe backend (contract + service) for wasm32
echo ">>> Building Rust contract and service..."
echo "  This may take 30-60 seconds..."
cd /build
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --release --target wasm32-unknown-unknown -p tictactoe
echo "  ✓ Build completed successfully"
echo ""

# Wait for network to be fully ready
echo ">>> Verifying network is ready..."
sleep 5

# Publish application and capture application ID
echo ">>> Publishing application to Linera..."
PUBLISH_OUTPUT=$(linera publish-and-create \
  /build/target/wasm32-unknown-unknown/release/tictactoe_contract.wasm \
  /build/target/wasm32-unknown-unknown/release/tictactoe_service.wasm \
  --json-argument "null" 2>&1) || {
  echo "  ✗ Publish failed!"
  echo "  Output:"
  echo "$PUBLISH_OUTPUT"
  exit 1
}

# Parse application ID: accept 64 hex chars, optionally with 0x prefix, or in JSON "id"/"applicationId"
APP_ID=$(echo "$PUBLISH_OUTPUT" | grep -oE '0x[a-f0-9]{64}' | head -1 | sed 's/^0x//')
if [ -z "$APP_ID" ]; then
  APP_ID=$(echo "$PUBLISH_OUTPUT" | grep -oE '[a-f0-9]{64}' | head -1)
fi
if [ -z "$APP_ID" ]; then
  APP_ID=$(echo "$PUBLISH_OUTPUT" | grep -iE "application|id" | grep -oE '[a-f0-9]{64}' | head -1)
fi
if [ -z "$APP_ID" ]; then
  echo "  ⚠ Warning: Could not parse application ID from publish output."
  echo "  Full output:"
  echo "$PUBLISH_OUTPUT"
  APP_ID="0000000000000000000000000000000000000000000000000000000000000000"
fi

echo "  ✓ Application published successfully"
echo ""

# Write client .env so frontend can connect to the application
echo ">>> Configuring frontend..."
mkdir -p /build/client
cat > /build/client/.env <<EOF
VITE_LINERA_APPLICATION_ID=$APP_ID
VITE_LINERA_FAUCET_URL=$LINERA_FAUCET_URL
EOF
echo "  ✓ Environment file created"
echo ""

# Display summary
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Application Details:"
echo "  • Application ID: $APP_ID"
echo "  • Faucet URL: $LINERA_FAUCET_URL"
echo "  • Chain ID: ${CHAIN_ID:-<not available>}"
echo ""
echo "🌐 Frontend:"
echo "  • URL: http://localhost:5173"
echo "  • Status: Starting..."
echo ""
echo "🔗 Linera Services:"
echo "  • Validator: http://localhost:13001"
echo "  • Proxy: http://localhost:9001"
echo "  • Faucet: http://localhost:8080"
echo ""
echo "=========================================="
echo "  Starting Frontend Server..."
echo "=========================================="
echo ""

# Build and run frontend
cd /build/client
if command -v pnpm &>/dev/null; then
  echo ">>> Installing dependencies with pnpm..."
  echo "  This may take 30-60 seconds..."
  pnpm install
  echo "  ✓ Dependencies installed"
  echo ""
  echo ">>> Starting Vite dev server..."
  echo ""
  echo "🎉 Frontend is starting! You can now access:"
  echo "   http://localhost:5173"
  echo ""
  echo "   (Press Ctrl+C to stop)"
  echo ""
  pnpm run dev --host 0.0.0.0 --port 5173
else
  echo ">>> Installing dependencies with npm..."
  echo "  This may take 30-60 seconds..."
  npm install
  echo "  ✓ Dependencies installed"
  echo ""
  echo ">>> Starting Vite dev server..."
  echo ""
  echo "🎉 Frontend is starting! You can now access:"
  echo "   http://localhost:5173"
  echo ""
  echo "   (Press Ctrl+C to stop)"
  echo ""
  npm run dev -- --host 0.0.0.0 --port 5173
fi
