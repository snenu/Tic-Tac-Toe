# TicTacToe on Linera

A fully on-chain TicTacToe game built on **Linera**. Each player uses their own **microchain**, and the game progresses via **cross-chain messages** inside a single Linera application.

## Features

- **Fully On-Chain**: All game state is stored on-chain
- **Cross-Chain**: Players interact via cross-chain messages
- **Real-Time**: Game state updates in real-time
- **Web Interface**: Modern React frontend with Vite

## Repository Structure

- `tictactoe/` — Linera application (Rust): contract + service (GraphQL)
- `client/` — React frontend (Vite) that talks to the Linera app via `@linera/client`
- `run.bash` — Build and deployment script
- `Dockerfile` — Docker container configuration
- `compose.yaml` — Docker Compose configuration

## How It Works

### Smart Contract (Linera Application)

The Linera application is split into:

- **Contract** (`tictactoe/src/contract.rs`): Executes operations and handles cross-chain messages
- **Service** (`tictactoe/src/service.rs`): Exposes GraphQL queries and mutations
- **State** (`tictactoe/src/state.rs`): Stores game state using Linera views

### Core Game Flow

1. **Create Match**: Host creates a match on their chain (`WaitingForPlayer` status)
2. **Join Match**: Guest sends a `JoinRequest` to the host chain
3. **Play**: Players take turns making moves (X goes first, then O)
4. **Win/Draw Detection**: Contract automatically detects wins and draws
5. **State Sync**: Game state is synchronized across both players' chains

### Operations

- `CreateMatch { host_name }`: Host creates a match
- `JoinMatch { host_chain_id, player_name }`: Guest joins a match
- `MakeMove { row, col }`: Player makes a move
- `LeaveMatch`: Player leaves the match

### Cross-Chain Messages

- `JoinRequest`: Guest requests to join host's match
- `InitialStateSync`: Host sends initial game state to guest
- `GameSync`: Synchronize game state after each move
- `LeaveNotice`: Notify opponent when a player leaves

## 🚀 Quick Start (Docker - Recommended)

**Just run one command and everything works!**

```bash
docker compose up
```

That's it! The setup will automatically:
1. ✅ Start a local Linera network with faucet
2. ✅ Build the Rust contract and service to WASM
3. ✅ Deploy the application on-chain
4. ✅ Start the frontend development server

**Access the app:** Open **http://localhost:5173** in your browser

**To stop:** Press `Ctrl+C` or run `docker compose down`

**To rebuild:** `docker compose up --build`

**To view logs:** `docker compose logs -f app`

> 📖 For detailed setup instructions, see [QUICKSTART.md](QUICKSTART.md)

### Prerequisites

- **Docker** and **Docker Compose** (that's all you need!)
- **4GB RAM** minimum, **8GB recommended**
- **5GB free disk space**
- No Rust, Node.js, or Linera CLI installation required - everything runs in Docker!

### Manual Setup

1. **Build the backend**:
   ```bash
   cd tictactoe
   rustup target add wasm32-unknown-unknown
   cargo build --release --target wasm32-unknown-unknown
   ```

2. **Publish the application**:
   ```bash
   linera publish-and-create \
     target/wasm32-unknown-unknown/release/tictactoe_contract.wasm \
     target/wasm32-unknown-unknown/release/tictactoe_service.wasm \
     --json-argument "null"
   ```

3. **Configure frontend**:
   Create `client/.env`:
   ```env
   VITE_LINERA_APPLICATION_ID=<your_application_id>
   VITE_LINERA_FAUCET_URL=http://localhost:8080
   ```

4. **Run frontend**:
   ```bash
   cd client
   npm install
   npm run dev
   ```

## How to Play

1. **Create a Room**: Enter your name and click "Create room"
2. **Share Room ID**: Copy your room ID and share it with your opponent
3. **Join Room**: Your opponent pastes your room ID and joins
4. **Play**: Take turns making moves (X goes first)
5. **Win**: First player to get 3 in a row wins!

## Game Rules

- X (host) always goes first
- O (guest) goes second
- Players alternate turns
- First to get 3 in a row (horizontal, vertical, or diagonal) wins
- If the board fills up with no winner, it's a draw

## Technical Details

### State Management

Game state is stored using Linera's view system:
- `game`: Current game state (board, players, status, etc.)
- `last_notification`: Last notification message

### GraphQL API

The service exposes the following queries:
- `game`: Get current game state
- `matchStatus`: Get game status
- `isHost`: Check if current player is host
- `opponentChainId`: Get opponent's chain ID
- `board`: Get current board state
- `currentTurnChainId`: Get chain ID of player whose turn it is
- `winnerChainId`: Get winner's chain ID (if game ended)

And mutations:
- `createMatch(hostName: String)`: Create a new match
- `joinMatch(hostChainId: String, playerName: String)`: Join a match
- `makeMove(row: Int, col: Int)`: Make a move
- `leaveMatch`: Leave the current match

## Running on Different Machines

Anyone can run the app on their own machine with no manual configuration:

1. **Clone the repository:**
   ```bash
   git clone <your-repo-url>
   cd Tic-Tac-Toe
   ```

2. **Ensure Docker is running:**
   ```bash
   docker --version
   docker compose version
   ```

3. **Start the application:**
   ```bash
   docker compose up
   ```
   For a clean run (e.g. after a previous run): `docker compose up --force-recreate`

4. **That's it.** The setup is fully automated: Linera network starts, the contract builds and deploys, `.env` is generated, and the frontend starts. No Rust, Node.js, or Linera CLI installation required. Open **http://localhost:5173** in your browser.

**Port requirements:** 5173 (frontend), 8080 (faucet), 9001 (shard proxy), 13001 (shard). If a port is in use, change it in `compose.yaml`.

## Deployment

### Local Network

Use the provided Docker setup for local testing.

### Testnet

1. Deploy the application to Linera testnet
2. Update `client/.env` with testnet faucet URL:
   ```env
   VITE_LINERA_FAUCET_URL=https://faucet.testnet-conway.linera.net
   VITE_LINERA_APPLICATION_ID=<your_testnet_app_id>
   ```
3. Build and deploy the frontend to your hosting provider

## Troubleshooting

### Port Already in Use

If you get port conflicts, stop other services using ports 5173, 8080, 9001, or 13001:

```bash
# On Linux/Mac
lsof -ti:5173 | xargs kill -9
lsof -ti:8080 | xargs kill -9

# On Windows (PowerShell)
netstat -ano | findstr :5173
taskkill /PID <PID> /F
```

### Storage Already Initialized Error

If you see "storage is already initialized", the cleanup script should handle this automatically. If it persists:

```bash
docker compose down
docker compose up --force-recreate
```

### Frontend Not Loading

1. Wait for the "Local: http://localhost:5173" message in logs
2. Check that port 5173 is accessible: `curl http://localhost:5173`
3. View logs: `docker compose logs -f app`

### Rebuild Everything

```bash
docker compose down
docker compose build --no-cache
docker compose up
```

### Rust Version Error

If you see an error like "rustc 1.85.0 is not supported" or "requires rustc 1.86.0":
- The Dockerfile uses `rust:latest` which should have Rust 1.86+
- If issues persist, rebuild: `docker compose build --no-cache`
- The error means the Rust version in the image is too old

## License

This project is provided as-is for educational and demonstration purposes.
 
