# Bitcoin / Lightning / Fedimint Docker Stack

A complete local development environment running **Bitcoin Core**, **Lightning Network (LND)**, and **Fedimint** with full UI support — all in Docker.

## Quick start

```bash
cd fedi-scripts   # this repository
docker compose up -d
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Dashboard (:3002)                     │
│              Unified status & controls                  │
└──────────┬──────────┬──────────┬──────────┬─────────────┘
           │          │          │          │
     ┌─────▼───┐ ┌────▼────┐ ┌──▼───┐ ┌───▼────┐
     │ Bitcoin  │ │   LND   │ │ RTL  │ │Fedimint│
     │  Core    │ │         │ │ UI   │ │Guardian│
     │ (regtest)│ │Lightning│ │:3003 │ │  UI    │
     │  :18443  │ │ :10009  │ └──────┘ │ :8175  │
     └────┬─────┘ └────┬────┘          └───┬────┘
          │            │                   │
          │     ┌──────▼──────┐     ┌──────▼──────┐
          │     │  Gateway    │     │  Fedimintd  │
          │     │  (LN↔FM)   │     │  (Guardian)  │
          │     │   :8176     │     │   :8174     │
          │     └─────────────┘     └─────────────┘
          │            │                   │
          └────────────┴───────────────────┘
                    Bitcoin P2P / RPC
```

## Services

| Service | Description | Port | URL |
|---------|-------------|------|-----|
| **Bitcoin Core** | Base layer (regtest) | 18443 | `http://localhost:18443` |
| **LND** | Lightning Network daemon | 10009 (gRPC), 8080 (REST) | `https://localhost:8080` |
| **RTL** | Ride The Lightning UI | 3003 | `http://localhost:3003` |
| **Fedimintd** | Fedimint guardian daemon | 8174 (API), 8173 (P2P) | `ws://localhost:8174` |
| **Guardian UI** | Fedimint guardian web UI | 8175 | `http://localhost:8175` |
| **Gateway** | Fedimint ↔ Lightning bridge | 8176 | `http://localhost:8176` |
| **Dashboard** | Unified status dashboard | 3002 | `http://localhost:3002` |

## Quick Start

```bash
# 1. Start everything (mines initial blocks, waits for sync)
./setup.sh

# 2. Open the dashboard
open http://localhost:3002
```

## Manual Start

```bash
# Start all containers
docker compose up -d

# Mine initial blocks (101 needed to make coinbase spendable)
docker compose exec bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin \
  generatetoaddress 101 $(docker compose exec bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin getnewaddress "" bech32)
```

## Helper Scripts

| Script | Description |
|--------|-------------|
| `./setup.sh` | Full bootstrap: starts services, mines blocks, shows status |
| `./mine.sh [N]` | Mine N blocks (default: 1) |
| `./fund-lnd.sh [BTC]` | Send BTC from bitcoind to LND (default: 10) |
| `./status.sh` | Check health of all services |
| `./turbo.sh <cmd>` | Fast dev shortcuts (bootstrap, reset, health, status, etc.) |

The unified **dashboard** (Compose service `dashboard`, default port 3002) is built from **`ui/`**: `public/index.html` and `nginx.conf` (reverse proxy to stack APIs).

## Using the Stack

### RTL (Lightning Management)

Open **http://localhost:3003** and log in with password: `password`

From RTL you can:
- View wallet balance
- Open/close payment channels
- Create and pay Lightning invoices
- View routing history

### Fedimint Guardian Setup

Open **http://localhost:8175** to access the guardian setup wizard.

For a single-guardian dev federation:
1. Open the Guardian UI
2. Follow the setup wizard to initialize the federation
3. Set the federation name and configure modules

### Funding LND

```bash
# Send 10 BTC from the regtest miner to LND
./fund-lnd.sh 10

# Or manually:
LND_ADDR=$(docker compose exec lnd lncli --network=regtest newaddress p2wkh | jq -r .address)
docker compose exec bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin \
  sendtoaddress "$LND_ADDR" 10
./mine.sh 6
```

### Connecting Gateway to Federation

After the federation is set up:

```bash
# Get the federation invite code from the guardian UI, then:
docker compose exec gatewayd gateway-cli connect <INVITE_CODE>

# Check gateway info
docker compose exec gatewayd gateway-cli info
```

### Turbo shortcuts

`turbo.sh` wraps common operations:

| Command | Description |
|---------|-------------|
| `turbo.sh bootstrap` | Start stack, mine 101 blocks, fund LND |
| `turbo.sh reset` | `docker compose down -v`, rebuild, bootstrap |
| `turbo.sh cycle` | Restart all containers (keep volumes) |
| `turbo.sh fund [amt]` | Mine + fund LND |
| `turbo.sh mine [n]` | Mine n regtest blocks |
| `turbo.sh logs [svc]` | Tail Compose logs |
| `turbo.sh health` | Run `./status.sh` (RPC/UI checks) |
| `turbo.sh status` | One-line Docker status per stack service |

## Troubleshooting

### LND image tag not found

If `lightninglabs/lnd:v0.18.4-beta` is not available, update `LND_IMAGE` in `.env`:

```bash
# Use the latest daily build
LND_IMAGE=lightninglabs/lnd:daily-testing-only

# Or check available tags
docker search lightninglabs/lnd --limit 25
```

### Fedimintd not starting

Ensure Bitcoin Core is healthy first — fedimintd depends on it:

```bash
docker compose logs bitcoind
docker compose logs fedimintd
```

### Reset everything

```bash
docker compose down -v   # Stops containers and removes volumes
docker compose up -d     # Fresh start
```

### View logs

```bash
docker compose logs -f              # All services
docker compose logs -f lnd          # Single service
docker compose logs -f fedimintd    # Fedimint guardian
```

## Configuration

All configuration is in the `.env` file. Key settings:

- **Image versions**: Change Docker image tags
- **Ports**: Remap any port to avoid conflicts
- **Credentials**: Bitcoin RPC user/password, RTL password

Service-specific configs are under `config/`:
- `config/bitcoin/bitcoin.conf` — Bitcoin Core configuration (reference; stack also sets flags via compose)
- `config/lnd/lnd.conf` — LND configuration (bind-mounted into the `lnd` container)

## Requirements

- Docker Engine 24+
- Docker Compose v2
- ~4 GB disk space for images
- ~2 GB RAM

## License

MIT
