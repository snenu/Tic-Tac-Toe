# Quick Start Guide

## 🚀 Run the App in 3 Steps

### Step 1: Make sure Docker is running

Open Docker Desktop or ensure Docker is running on your system.

### Step 2: Run the command

```bash
docker compose up
```

### Step 3: Open your browser

Go to: **http://localhost:5173**

That's it! 🎉

---

## What Happens Behind the Scenes

When you run `docker compose up`, the system automatically:

1. ✅ Builds the Docker image with all dependencies (Rust, Node.js, Linera CLI)
2. ✅ Starts a local Linera blockchain network
3. ✅ Builds the smart contract (Rust → WASM)
4. ✅ Deploys the application on-chain
5. ✅ Starts the frontend development server
6. ✅ Shows you the Application ID and access URL

**Total setup time:** ~2-3 minutes (first run)

---

## Common Commands

### Start the app
```bash
docker compose up
```

### Stop the app
```bash
docker compose down
```

### View logs
```bash
docker compose logs -f app
```

### Rebuild everything
```bash
docker compose down
docker compose up --build
```

### Clean start (if you have issues)
```bash
docker compose down
docker compose up --force-recreate
```

---

## Troubleshooting

### Port 5173 already in use?
- Stop other services using that port
- Or change the port in `compose.yaml`

### "Storage already initialized" error?
- Run: `docker compose down && docker compose up --force-recreate`
- The cleanup script should handle this automatically

### Frontend not loading?
- Wait for the "Local: http://localhost:5173" message in the logs
- Check logs: `docker compose logs -f app`

---

## System Requirements

- **Docker Desktop** (Windows/Mac) or **Docker Engine** (Linux)
- **4GB RAM** minimum (8GB recommended)
- **5GB free disk space**

No other software needed! Everything runs in Docker.

---

## Next Steps

1. Open http://localhost:5173
2. Enter your name
3. Click "Create room"
4. Share the Room ID with a friend
5. Play TicTacToe on-chain! 🎮

Enjoy! 🚀
