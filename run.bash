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
echo ">>> Cleaning up previous Linera network storage..."

# First, try to get any existing network info and clear it
set +e
EXISTING_NETWORK=$(linera net helper 2>/dev/null | grep -E "LINERA_NETWORK|LINERA_NETWORK_DIR" | head -1 | cut -d'=' -f2 | tr -d "'\"")
if [ -n "$EXISTING_NETWORK" ]; then
  EXISTING_NETWORK="${EXISTING_NETWORK#rocksdb:}"
  EXISTING_NETWORK="${EXISTING_NETWORK#file:}"
  if [ -d "$EXISTING_NETWORK" ] || [ -f "$EXISTING_NETWORK" ]; then
    echo "  - Found existing network storage: $EXISTING_NETWORK"
    rm -rf "$EXISTING_NETWORK" 2>/dev/null || true
    # Also clear parent if it's a linera directory
    PARENT="$(dirname "$EXISTING_NETWORK")"
    if [[ "$PARENT" == *"linera"* ]] && [ -d "$PARENT" ]; then
      echo "  - Clearing parent: $PARENT"
      rm -rf "$PARENT" 2>/dev/null || true
    fi
  fi
fi
set -e

# Clear from common locations
for base in /build "$HOME" /tmp; do
  # Clear .linera directories
  if [ -d "$base/.linera" ]; then
    echo "  - Clearing: $base/.linera"
    rm -rf "$base/.linera" 2>/dev/null || true
  fi
  # Clear linera-* directories (match the pattern from error: linera-2026-02-03T...)
  for d in "$base"/linera-*; do
    if [ -d "$d" ]; then
      echo "  - Clearing: $d"
      rm -rf "$d" 2>/dev/null || true
    fi
  done
  # Clear server config files
  for f in "$base"/server_*.json "$base"/committee.json "$base"/*.rocksdb; do
    if [ -f "$f" ] || [ -d "$f" ]; then
      echo "  - Removing: $f"
      rm -rf "$f" 2>/dev/null || true
    fi
  done
done

# Clear /tmp Linera dirs (helper may use e.g. /tmp/.tmpXXXX)
for tmpd in /tmp/.tmp* /tmp/linera*; do
  if [ -d "$tmpd" ]; then
    echo "  - Clearing temp: $tmpd"
    rm -rf "$tmpd" 2>/dev/null || true
  fi
done

# Also clear any wallet/keystore that might conflict
if [ -d "$HOME/.config/linera" ]; then
  echo "  - Clearing wallet config: $HOME/.config/linera"
  rm -rf "$HOME/.config/linera" 2>/dev/null || true
fi

# Kill any existing linera processes FIRST (before they can lock storage)
echo ">>> Stopping any existing Linera processes..."
pkill -f "linera.*net" 2>/dev/null || true
pkill -f "linera.*server" 2>/dev/null || true
pkill -f "linera.*faucet" 2>/dev/null || true
pkill -f "linera.*shard" 2>/dev/null || true
sleep 3

# Try to bring down existing network if it exists
echo ">>> Attempting to bring down existing network..."
set +e
linera net down 2>/dev/null || true
set -e
sleep 1

echo ">>> Starting Linera network..."
eval "$(linera net helper)"

# Clear the path the helper just set (it may point to existing storage from a previous run)
echo ">>> Clearing helper storage paths..."
for var in LINERA_NETWORK LINERA_NETWORK_DIR LINERA_STORAGE LINERA_NETWORK_STORAGE LINERA_NET; do
  if [ -n "${!var:-}" ]; then
    path="${!var}"
    # Handle different path formats
    path="${path#rocksdb:}"  # strip rocksdb: prefix if present
    path="${path#file:}"     # strip file: prefix if present
    if [ -f "$path" ]; then
      echo "  - Removing file: $path"
      rm -f "$path" 2>/dev/null || true
      path="$(dirname "$path")"
    fi
    if [ -d "$path" ]; then
      echo "  - Clearing directory: $path"
      rm -rf "$path" 2>/dev/null || true
    fi
    # Also try parent directory
    if [ -n "$path" ] && [ "$path" != "/" ] && [ "$path" != "." ]; then
      parent="$(dirname "$path")"
      if [ -d "$parent" ] && [[ "$parent" == *"linera"* ]]; then
        echo "  - Clearing parent: $parent"
        rm -rf "$parent" 2>/dev/null || true
      fi
    fi
  fi
done 2>/dev/null || true

# Additional aggressive cleanup: find and remove ANY linera-related directories/files
# But exclude Rust build directories, node_modules, and client code
echo ">>> Performing aggressive cleanup..."
find /tmp /build "$HOME" -type d \( -name "linera-*" -o -name ".linera" \) ! -path "*/target/*" ! -path "*/node_modules/*" ! -path "*/client/*" 2>/dev/null | while read -r dir; do
  if [ -d "$dir" ] && [[ "$dir" != *"/target/"* ]] && [[ "$dir" != *"/node_modules/"* ]] && [[ "$dir" != *"/client/"* ]]; then
    echo "  - Removing: $dir"
    rm -rf "$dir" 2>/dev/null || true
  fi
done

# Also find and remove any linera network files (but not Rust build artifacts)
find /tmp /build "$HOME" -type f \( -name "*linera*" -o -name "server_*.json" -o -name "committee.json" \) ! -path "*/target/*" ! -path "*/node_modules/*" 2>/dev/null | while read -r file; do
  if [ -f "$file" ]; then
    echo "  - Removing file: $file"
    rm -f "$file" 2>/dev/null || true
  fi
done

# Clear any RocksDB databases that might be linera storage
find /tmp /build "$HOME" -type d -name "*.rocksdb" 2>/dev/null | while read -r dbdir; do
  if [ -d "$dbdir" ]; then
    echo "  - Removing RocksDB: $dbdir"
    rm -rf "$dbdir" 2>/dev/null || true
  fi
done

sleep 1

# Final check: clear any storage that the helper might have just pointed to
echo ">>> Final cleanup check..."
eval "$(linera net helper)" 2>/dev/null || true
for var in LINERA_NETWORK LINERA_NETWORK_DIR LINERA_STORAGE LINERA_NETWORK_STORAGE LINERA_NET; do
  if [ -n "${!var:-}" ]; then
    path="${!var}"
    path="${path#rocksdb:}"
    path="${path#file:}"
    if [ -n "$path" ] && [ "$path" != "/" ]; then
      if [ -f "$path" ] || [ -d "$path" ]; then
        echo "  - Final cleanup: $path"
        rm -rf "$path" 2>/dev/null || true
      fi
      # Also check parent
      parent="$(dirname "$path" 2>/dev/null || echo '')"
      if [ -n "$parent" ] && [ "$parent" != "/" ] && [ "$parent" != "." ] && [[ "$parent" == *"linera"* ]]; then
        if [ -d "$parent" ]; then
          echo "  - Final cleanup parent: $parent"
          rm -rf "$parent" 2>/dev/null || true
        fi
      fi
    fi
  fi
done 2>/dev/null || true

# One more aggressive find and remove - including timestamped networks like "linera-2026-02-03T..."
# But exclude Rust build directories and node_modules
echo ">>> Last aggressive cleanup pass..."
find /build /tmp "$HOME" -maxdepth 4 \( -type d -name "linera-*" -o -type d -name ".linera" \) ! -path "*/target/*" ! -path "*/node_modules/*" ! -path "*/client/*" 2>/dev/null | while read -r item; do
  if [ -e "$item" ] && [[ "$item" != *"/target/"* ]] && [[ "$item" != *"/node_modules/"* ]]; then
    echo "  - Removing: $item"
    rm -rf "$item" 2>/dev/null || true
  fi
done

# Also check for any RocksDB lock files that might prevent deletion
find /build /tmp "$HOME" -name "LOCK" -o -name "*.lock" 2>/dev/null | while read -r lockfile; do
  if [ -f "$lockfile" ] && [[ "$(dirname "$lockfile")" == *"linera"* ]]; then
    echo "  - Removing lock: $lockfile"
    rm -f "$lockfile" 2>/dev/null || true
  fi
done

sleep 1

echo ">>> Starting fresh Linera network..."
# Start network directly (linera_spawn has xargs issues in Docker)
# Filter out xargs errors and start in background
linera net up --with-faucet > /tmp/linera_net.log 2>&1 &
LINERA_NET_PID=$!
echo ">>> Linera network starting (PID: $LINERA_NET_PID)..."

# Wait a moment and check if it started successfully
sleep 3

# Check for storage initialization errors
if grep -q "storage is already initialized" /tmp/linera_net.log 2>/dev/null; then
  echo ">>> ERROR: Storage still exists, performing emergency cleanup..."
  
  # Extract network name from error
  NETWORK_NAME=$(grep -oE "linera-[0-9T:-]+" /tmp/linera_net.log 2>/dev/null | head -1)
  if [ -n "$NETWORK_NAME" ]; then
    echo "  - Removing network: $NETWORK_NAME"
    find /build /tmp "$HOME" -type d -name "$NETWORK_NAME" 2>/dev/null | while read -r netdir; do
      echo "    Removing: $netdir"
      rm -rf "$netdir" 2>/dev/null || true
    done
  fi
  
  # Kill the failed process
  kill $LINERA_NET_PID 2>/dev/null || true
  sleep 1
  
  # Clear all linera networks one more time (exclude Rust build dirs)
  find /build /tmp "$HOME" -type d -name "linera-*" ! -path "*/target/*" ! -path "*/node_modules/*" 2>/dev/null | while read -r dir; do
    if [[ "$dir" != *"/target/"* ]] && [[ "$dir" != *"/node_modules/"* ]]; then
      echo "  - Emergency removal: $dir"
      rm -rf "$dir" 2>/dev/null || true
    fi
  done
  
  # Clear helper paths again
  eval "$(linera net helper)" 2>/dev/null || true
  for var in LINERA_NETWORK LINERA_NETWORK_DIR LINERA_STORAGE LINERA_NETWORK_STORAGE LINERA_NET; do
    if [ -n "${!var:-}" ]; then
      path="${!var}"
      path="${path#rocksdb:}"
      path="${path#file:}"
      [ -n "$path" ] && [ "$path" != "/" ] && rm -rf "$path" 2>/dev/null || true
    fi
  done
  
  sleep 2
  echo ">>> Retrying network start after emergency cleanup..."
  linera net up --with-faucet > /tmp/linera_net.log 2>&1 &
  LINERA_NET_PID=$!
  sleep 3
fi

# Show network startup log (filter out xargs errors)
if [ -f /tmp/linera_net.log ]; then
  grep -v "xargs.*kill" /tmp/linera_net.log 2>/dev/null || true
fi

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
