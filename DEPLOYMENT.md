# Deployment Guide

This guide explains how to deploy the TicTacToe on-chain application.

## Quick Start (Docker)

The easiest way to run the application is using Docker Compose:

```bash
docker compose up --force-recreate
```

This will:
1. Build the Docker image with all dependencies
2. Start a local Linera network
3. Build and publish the application
4. Start the frontend on `http://localhost:5173`

## Manual Deployment

### Prerequisites

- Rust (latest stable)
- Node.js 18+ and npm/pnpm
- Linera CLI tools installed

### Step 1: Build the Backend

```bash
# Navigate to project root
cd /path/to/tictacto

# Add WASM target
rustup target add wasm32-unknown-unknown

# Build the contract and service
cargo build --release --target wasm32-unknown-unknown -p tictactoe
```

The WASM files will be in:
- `target/wasm32-unknown-unknown/release/tictactoe_contract.wasm`
- `target/wasm32-unknown-unknown/release/tictactoe_service.wasm`

### Step 2: Start Linera Network

```bash
# Start local network with faucet
linera net up --with-faucet

# Initialize wallet (if not already done)
linera wallet init --faucet=http://localhost:8080

# Request a chain
linera wallet request-chain --faucet=http://localhost:8080
```

### Step 3: Publish Application

```bash
# Publish and create the application
linera publish-and-create \
  target/wasm32-unknown-unknown/release/tictactoe_contract.wasm \
  target/wasm32-unknown-unknown/release/tictactoe_service.wasm \
  --json-argument "null"

# Copy the application ID from the output
```

### Step 4: Configure Frontend

Create `client/.env`:

```env
VITE_LINERA_APPLICATION_ID=<your_application_id_here>
VITE_LINERA_FAUCET_URL=http://localhost:8080
```

### Step 5: Run Frontend

```bash
cd client
npm install
npm run dev
```

The frontend will be available at `http://localhost:5173`

## Production Deployment

### Backend (Linera Application)

1. Deploy to Linera testnet or mainnet
2. Get your application ID
3. Ensure your application is accessible

### Frontend

1. Update `client/.env` with production values:
   ```env
   VITE_LINERA_APPLICATION_ID=<production_app_id>
   VITE_LINERA_FAUCET_URL=<production_faucet_url>
   ```

2. Build the frontend:
   ```bash
   cd client
   npm install
   npm run build
   ```

3. Deploy the `client/dist` directory to your hosting provider:
   - Vercel
   - Netlify
   - GitHub Pages
   - Any static hosting service

### Environment Variables

For production, set these environment variables:

- `VITE_LINERA_APPLICATION_ID`: Your deployed Linera application ID
- `VITE_LINERA_FAUCET_URL`: Linera faucet URL (testnet or mainnet)

## Troubleshooting

### Wallet Already Exists Error

If you see "Keystore already exists" error, the script handles this automatically. If running manually, you can:

```bash
# Remove existing wallet (WARNING: This deletes your wallet)
rm -rf ~/.config/linera

# Or skip wallet initialization if wallet exists
```

### Application ID Not Found

If the application ID parsing fails:
1. Check the `linera publish-and-create` output manually
2. Look for a 64-character hex string
3. Manually set it in `client/.env`

### Frontend Not Connecting

1. Verify `VITE_LINERA_APPLICATION_ID` is set correctly
2. Check that the Linera network is running
3. Ensure the faucet is accessible at the configured URL
4. Check browser console for errors

### Build Errors

If you encounter Rust compilation errors:
1. Ensure you're using Rust stable (1.70+)
2. Update dependencies: `cargo update`
3. Clean build: `cargo clean && cargo build --release --target wasm32-unknown-unknown`

## Testing

### Local Testing

1. Open two browser windows (or use incognito mode)
2. Create a room in one window
3. Copy the room ID
4. Join the room in the second window
5. Play a game!

### Network Testing

Test cross-chain functionality:
1. Create a match on one chain
2. Join from a different chain
3. Verify moves sync correctly
4. Verify win/draw detection works

## Support

For issues or questions:
1. Check the main README.md
2. Review Linera documentation: https://linera.io/
3. Check the RPSv2 example for reference patterns
