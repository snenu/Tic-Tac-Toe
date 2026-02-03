# Docker Setup - Complete & Ready

## ✅ Everything is Configured

This project is **fully Dockerized** and ready to run with a single command.

## Quick Start

```bash
docker compose up
```

That's it! Everything runs automatically.

## What's Included

### 1. Dockerfile
- ✅ Rust 1.85.0 with WASM target support
- ✅ Linera CLI tools (linera-service, linera-storage-service)
- ✅ Node.js via NVM (lts/krypton)
- ✅ All build dependencies
- ✅ Health check configured

### 2. compose.yaml
- ✅ Port mappings:
  - `5173` - Frontend web app
  - `8080` - Linera faucet
  - `9001` - Shard proxy
  - `13001` - Shard
- ✅ Volume mount: `.:/build` (for code hot-reload)
- ✅ Environment variables configured
- ✅ Auto-restart on failure

### 3. run.bash Script
- ✅ Comprehensive cleanup (prevents "storage already initialized" errors)
- ✅ Linera network startup
- ✅ Wallet initialization
- ✅ Rust contract build (WASM)
- ✅ Application deployment
- ✅ Frontend dependency installation
- ✅ Frontend server startup
- ✅ Clear progress indicators
- ✅ Error handling and retries

## File Structure

```
.
├── Dockerfile          # Container configuration
├── compose.yaml        # Docker Compose setup
├── run.bash            # Main startup script
├── README.md           # Full documentation
├── QUICKSTART.md       # Simple quick start guide
├── .gitignore          # Git ignore rules
├── tictactoe/          # Rust smart contract
└── client/             # React frontend
```

## How It Works

1. **Docker builds the image** with all dependencies
2. **Container starts** and runs `run.bash`
3. **Cleanup** removes any old Linera storage
4. **Network starts** - Linera local blockchain
5. **Wallet initialized** - Creates/loads wallet
6. **Contract built** - Rust → WASM compilation
7. **App deployed** - Published to Linera network
8. **Frontend starts** - React dev server on port 5173

## Testing the Setup

### First Run
```bash
docker compose up
```
Wait ~2-3 minutes for initial setup.

### Verify It Works
1. Check logs show: "✅ Frontend: http://localhost:5173"
2. Open browser: http://localhost:5173
3. You should see the TicTacToe home page

### Common Commands
```bash
# Start
docker compose up

# Stop
docker compose down

# Rebuild
docker compose up --build

# Clean restart
docker compose down
docker compose up --force-recreate

# View logs
docker compose logs -f app
```

## Troubleshooting

### Port Conflicts
If ports are in use, stop other services or modify `compose.yaml`.

### Storage Errors
The cleanup script handles this automatically. If issues persist:
```bash
docker compose down
docker compose up --force-recreate
```

### Build Failures
```bash
# Clean rebuild
docker compose down
docker compose build --no-cache
docker compose up
```

## System Requirements

- Docker Desktop (Windows/Mac) or Docker Engine (Linux)
- 4GB RAM minimum (8GB recommended)
- 5GB free disk space
- Internet connection (for first build)

## No Additional Software Needed!

Everything runs in Docker:
- ✅ No Rust installation needed
- ✅ No Node.js installation needed
- ✅ No Linera CLI installation needed
- ✅ No manual configuration needed

Just Docker! 🐳

---

**Status:** ✅ **READY FOR PRODUCTION USE**

Anyone can clone this repo and run `docker compose up` to get a working on-chain TicTacToe game!
