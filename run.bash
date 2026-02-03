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

# Kill any existing processes first
pkill -f "linera" 2>/dev/null || true
sleep 2

# Clear from common locations (matching working example)
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

# Get helper and clear its paths
eval "$(linera net helper)"

# Clear the path the helper just set (it may point to existing storage from a previous run)
for var in LINERA_NETWORK LINERA_NETWORK_DIR LINERA_STORAGE LINERA_NETWORK_STORAGE LINERA_NET; do
  if [ -n "${!var:-}" ]; then
    path="${!var}"
    path="${path#rocksdb:}"  # strip rocksdb: prefix if present
    if [ -f "$path" ]; then
      path="$(dirname "$path")"
    fi
    if [ -d "$path" ]; then
      echo ">>> Clearing helper storage path ($path)..."
      rm -rf "$path" 2>/dev/null || true
    fi
  fi
done 2>/dev/null || true

# Final aggressive cleanup - find and remove ALL linera-* directories
echo ">>> Final cleanup - removing all linera networks..."
find /build /tmp "$HOME" -maxdepth 3 -type d -name "linera-*" ! -path "*/target/*" ! -path "*/node_modules/*" 2>/dev/null | while read -r dir; do
  if [ -d "$dir" ]; then
    echo "  - Force removing: $dir"
    rm -rf "$dir" 2>/dev/null || true
  fi
done

sleep 1

# Start network (use linera_spawn like working example, but handle xargs errors)
linera_spawn linera net up --with-faucet 2>&1 | grep -v "xargs.*kill" || {
  # Fallback if linera_spawn has issues
  echo ">>> Starting network directly..."
  linera net up --with-faucet &
  sleep 3
}

# Wait for faucet to be ready
echo ">>> Waiting for faucet to be ready..."
sleep 5
for i in {1..30}; do
  if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo ">>> Faucet is ready!"
    break
  fi
  echo ">>> Waiting for faucet... ($i/30)"
  sleep 1
done

export LINERA_FAUCET_URL=http://localhost:8080

# Initialize wallet (will skip if already exists)
echo ">>> Initializing wallet..."
set +e
linera wallet init --faucet="$LINERA_FAUCET_URL" 2>&1 | grep -v "already exists" || true
set -e

echo ">>> Requesting chain..."
set +e
CHAIN_OUTPUT=$(linera wallet request-chain --faucet="$LINERA_FAUCET_URL" 2>&1)
CHAIN_ID=$(echo "$CHAIN_OUTPUT" | grep -oE '[a-f0-9]{64}' | head -1)
set -e

echo ">>> Building Rust contract and service..."
echo "  This may take 30-60 seconds..."
cd /build
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true
cargo build --release --target wasm32-unknown-unknown -p tictactoe
echo "  ✓ Build completed successfully"

echo ">>> Publishing and creating application..."
LINERA_APPLICATION_ID=$(linera --wait-for-outgoing-messages \
  publish-and-create \
  /build/target/wasm32-unknown-unknown/release/tictactoe_contract.wasm \
  /build/target/wasm32-unknown-unknown/release/tictactoe_service.wasm \
  --json-argument "null")

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
