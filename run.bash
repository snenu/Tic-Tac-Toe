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

# Clear any existing Linera network storage so we don't get
# "storage is already initialized" when re-running (e.g. after docker compose down/up).
# Storage can persist on the host via the .:/build volume mount, in the container's home,
# or in /tmp (e.g. .tmp* dirs from linera net helper).
echo ">>> Starting Linera network..."

# Always clear wallet so we get a fresh chain on every startup (avoids stale network references).
if [ -d "$HOME/.config/linera" ] || [ -f "$HOME/.config/linera/wallet.json" ]; then
  echo ">>> Clearing wallet for fresh start..."
  rm -rf "$HOME/.config/linera" 2>/dev/null || true
fi

# Clear from common locations (matching stonepapersessior example)
for base in /build "$HOME"; do
  if [ -d "$base/.linera" ]; then
    echo ">>> Clearing existing Linera network storage ($base/.linera)..."
    rm -rf "$base/.linera" 2>/dev/null || true
  fi
  for d in "$base"/linera-*; do
    if [ -d "$d" ]; then
      echo ">>> Clearing existing Linera network storage ($d)..."
      rm -rf "$d" 2>/dev/null || true
    fi
  done
done
# Clear /tmp Linera dirs (helper may use e.g. /tmp/.tmpXXXX)
for tmpd in /tmp/.tmp* /tmp/linera*; do
  if [ -d "$tmpd" ]; then
    echo ">>> Clearing existing Linera temp storage ($tmpd)..."
    rm -rf "$tmpd" 2>/dev/null || true
  fi
done

# Aggressive find-based cleanup (catches any remaining linera-* dirs, e.g. on Windows volume mounts)
for base in /build /tmp "$HOME"; do
  [ "$base" = "/" ] && continue
  while IFS= read -r -d '' d; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d" 2>/dev/null || true
  done < <(find "$base" -maxdepth 4 -type d -name "linera-*" -print0 2>/dev/null || true)
done
while IFS= read -r -d '' d; do
  [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d" 2>/dev/null || true
done < <(find /tmp -maxdepth 2 -type d \( -name ".tmp*" -o -name "linera*" \) -print0 2>/dev/null || true)

# Get helper and clear its paths
eval "$(linera net helper)"

# Clear the path the helper just set (it may point to existing storage from a previous run)
for var in LINERA_NETWORK LINERA_NETWORK_DIR LINERA_STORAGE LINERA_NETWORK_STORAGE LINERA_NET; do
  if [ -n "${!var:-}" ]; then
    path="${!var}"
    path="${path#rocksdb:}"  # strip rocksdb: prefix if present
    if [ -f "$path" ]; then
      echo ">>> Clearing helper storage file ($path)..."
      rm -f "$path" 2>/dev/null || true
    fi
    if [ -d "$path" ]; then
      echo ">>> Clearing helper storage path ($path)..."
      rm -rf "$path" 2>/dev/null || true
    fi
  fi
done 2>/dev/null || true

sleep 2
# Short extra delay so volume/filesystem can release handles (helps on Windows)
sleep 1

# Start network (run in main shell so validator and faucet stay alive)
linera_spawn linera net up --with-faucet

# Wait for faucet to be ready (give it time to bind to 8080)
echo ">>> Waiting for faucet to be ready..."
sleep 10
for i in {1..45}; do
  if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo ">>> Faucet is ready!"
    break
  fi
  echo ">>> Waiting for faucet... ($i/45)"
  sleep 1
done

export LINERA_FAUCET_URL=http://localhost:8080

# Initialize wallet (we cleared it above for a fresh start)
echo ">>> Initializing wallet..."
linera wallet init --faucet="$LINERA_FAUCET_URL" || true

echo ">>> Requesting chain..."
set +e
CHAIN_OUTPUT=$(linera wallet request-chain --faucet="$LINERA_FAUCET_URL" 2>&1)
CHAIN_ID=$(echo "$CHAIN_OUTPUT" | grep -oE '[a-f0-9]{64}' | head -1)
set -e

# Wait for the new chain to propagate to the validator (avoids ChainDescription "Blobs not found")
echo ">>> Waiting for chain to propagate..."
sleep 15

echo ">>> Building Rust contract and service..."
echo "  This may take 30-60 seconds..."
cd /build
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --release --target wasm32-unknown-unknown -p tictactoe
echo "  ✓ Build completed successfully"

# Wait so validator is ready for blob upload (avoids ContractBytecode/ServiceBytecode "Blobs not found" on first try)
echo ">>> Waiting for validator before publish..."
sleep 15

echo ">>> Publishing and creating application..."
LINERA_APPLICATION_ID=""
for attempt in 1 2 3 4 5; do
  # Linera CLI may exit 1 due to internal "xargs: kill" cleanup; treat success by presence of app ID in output
  PUBLISH_OUT=$(linera --wait-for-outgoing-messages \
    publish-and-create \
    /build/target/wasm32-unknown-unknown/release/tictactoe_contract.wasm \
    /build/target/wasm32-unknown-unknown/release/tictactoe_service.wasm \
    --json-argument "null" 2>&1) || true
  # Extract only the application ID (format: 64 hex chars, or 64hex:digits). Ignore log lines/timestamps.
  LINERA_APPLICATION_ID=$(echo "$PUBLISH_OUT" | grep -oE '[a-f0-9]{64}(:[0-9]+)?' | tail -1)
  if [ -z "$LINERA_APPLICATION_ID" ]; then
    # Fallback: last line might be the ID only (some CLI versions output 64 hex or 64hex:digits)
    last_line=$(echo "$PUBLISH_OUT" | tail -1 | tr -d '\r\n' | sed 's/[^0-9a-fA-F:]//g')
    if echo "$last_line" | grep -qE '^[a-f0-9]{64}(:[0-9]+)?$'; then
      LINERA_APPLICATION_ID=$last_line
    fi
  fi
  if [ -n "$LINERA_APPLICATION_ID" ]; then
    echo "  ✓ Application published: $LINERA_APPLICATION_ID"
    break
  fi
  # No app ID in output - retry on blob/validator propagation errors (ContractBytecode, ServiceBytecode, ChainDescription)
  if echo "$PUBLISH_OUT" | grep -q "Blobs not found\|Failed to communicate\|ContractBytecode\|ServiceBytecode"; then
    echo ">>> Publish attempt $attempt failed (validator/blob propagation), retrying in 20s..."
    echo "$PUBLISH_OUT" | head -3
    sleep 20
    LINERA_APPLICATION_ID=""
  else
    echo ">>> Publish failed (no application ID in output):" >&2
    echo "$PUBLISH_OUT" | tail -20 >&2
    exit 1
  fi
done
if [ -z "$LINERA_APPLICATION_ID" ]; then
  echo ">>> Failed to publish application after 5 attempts" >&2
  exit 1
fi
# Application ID is already in correct form (64hex or 64hex:digits); ensure no stray chars
LINERA_APPLICATION_ID=$(echo "$LINERA_APPLICATION_ID" | tr -d '\r\n' | sed 's/[^0-9a-fA-F:]//g')
export VITE_LINERA_APPLICATION_ID=$LINERA_APPLICATION_ID

echo ">>> Creating client .env file..."
mkdir -p /build/client
cat > /build/client/.env <<EOF
VITE_LINERA_APPLICATION_ID=$LINERA_APPLICATION_ID
VITE_LINERA_FAUCET_URL=$LINERA_FAUCET_URL
EOF

# Display startup summary
echo ""
echo "========================================"
echo "🚀 TicTacToe - On-Chain Game"
echo "========================================"
echo ""
echo "✅ Linera Network: Running"
echo "✅ Application ID: $LINERA_APPLICATION_ID"
echo "✅ Faucet URL: $LINERA_FAUCET_URL"
echo "✅ Chain ID: ${CHAIN_ID:-<not available>}"
echo "✅ Frontend: http://localhost:5173"
echo ""
echo "📝 Next Steps:"
echo "1. Open http://localhost:5173 in your browser"
echo "2. Create or join a match"
echo "3. Play TicTacToe on-chain!"
echo ""
echo "========================================"
echo ""

echo ">>> Installing frontend dependencies..."
cd /build/client

# Load nvm and use Node.js
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Ensure Node.js is available
if ! command -v node &> /dev/null; then
  echo ">>> Node.js not found, installing..."
  nvm install lts/krypton
  nvm use lts/krypton
fi

# Verify Node.js version
NODE_VERSION=$(node --version || echo "unknown")
echo ">>> Using Node.js: $NODE_VERSION"

# Always run npm install to ensure all dependencies are installed
npm install

echo ">>> Starting frontend development server..."
echo ""
echo "========================================"
echo "🎮 Application is starting up!"
echo "========================================"
echo ""
echo "Frontend is compiling... Please wait for 'Local:' message"
echo ""
echo "Once compiled, access the app at:"
echo "  🌐 http://localhost:5173"
echo ""
echo "To view logs: docker compose logs -f app"
echo "To stop: docker compose down"
echo ""
echo "========================================"
echo ""

npm run dev -- --host 0.0.0.0 --port 5173
