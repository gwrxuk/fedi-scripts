# Project Architecture

## Overview

This project runs a complete Bitcoin / Lightning / Fedimint development stack in Docker. Six containers operate on a shared bridge network (`fedimint-net`), with data persisted across restarts via named volumes.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Host Machine                                   │
│                                                                         │
│   localhost:3002   localhost:3003   localhost:8175                       │
│        │                │                │                              │
│   ┌────▼────┐      ┌────▼────┐      ┌───▼──────┐                       │
│   │Dashboard│      │  RTL    │      │Fedimint  │                       │
│   │ (nginx) │      │  UI    │      │Guardian UI│                       │
│   │ :80     │      │ :3000  │      │ :8175     │                       │
│   └────┬────┘      └────┬───┘      └───┬──────┘                       │
│        │                │               │                              │
│ ═══════╪════════════════╪═══════════════╪══════ fedimint-net ════════  │
│        │                │               │                              │
│        │           ┌────▼───────────────▼───┐    ┌──────────────┐      │
│        │           │         LND            │    │  fedimintd   │      │
│        │           │  gRPC :10009           │    │  API  :8174  │      │
│        │           │  REST :8080            │    │  P2P  :8173  │      │
│        │           │  P2P  :9735            │    │  UI   :8175  │      │
│        │           └────┬──────────┬────────┘    └──────┬───────┘      │
│        │                │          │                    │              │
│        │                │     ┌────▼────────────────────▼───┐          │
│        │                │     │        gatewayd             │          │
│        │                │     │   Lightning ↔ Fedimint      │          │
│        │                │     │        API :8176            │          │
│        │                │     └────────────┬────────────────┘          │
│        │                │                  │                           │
│   ┌────▼────────────────▼──────────────────▼───┐                       │
│   │              bitcoind (regtest)              │                      │
│   │         RPC :18443   P2P :18444              │                      │
│   │    ZMQ blocks :28332   ZMQ tx :28333         │                      │
│   └──────────────────────────────────────────────┘                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Source code layout

This repository is the **Fedi stack** only: `docker-compose.yml`, shell helpers, `config/`, and `ui/` (dashboard + nginx reverse proxy). Bitcoin Core, LND, Fedimint, gateway, RTL, and the static dashboard are defined in Compose and wired on `fedimint-net`.

---

## Containers (6 total)

### 1. `bitcoind` — The Foundation

**Image:** `lncm/bitcoind:v28.0`

Bitcoin Core running in **regtest** mode — a private test blockchain where you control block production. This is the base layer everything else depends on.

**Key configuration** (passed as CLI flags):
- `-regtest` — isolated test network, no real money
- `-txindex=1` — full transaction index for lookups
- `-rpcallowip=0.0.0.0/0` — allows RPC from any container on the Docker network
- `-zmqpubrawblock` / `-zmqpubrawtx` — ZeroMQ streams that push new blocks and transactions to subscribers (LND uses these)

**Healthcheck:** Runs `bitcoin-cli getblockchaininfo` every 5 seconds. Other services wait for this to pass before starting.

**Ports exposed to host:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 18443 | JSON-RPC | Bitcoin Core RPC API |
| 18444 | P2P | Bitcoin peer-to-peer |
| 28332 | ZMQ | Raw block notifications |
| 28333 | ZMQ | Raw transaction notifications |

---

### 2. `lnd` — Lightning Network Daemon

**Image:** `lightninglabs/lnd:daily-testing-only`

LND connects to bitcoind and operates a Lightning Network node. It subscribes to bitcoind's ZMQ streams for real-time block/transaction notifications and uses RPC to query chain state.

**Key configuration** (`config/lnd/lnd.conf`):
- `noseedbackup=true` — auto-creates a wallet without manual seed backup (dev only)
- `tlsextradomain=lnd` — adds `lnd` as a valid TLS hostname so other containers can connect via HTTPS
- `accept-keysend=true` — accepts spontaneous payments without an invoice
- `bitcoin.node=bitcoind` — tells LND to use bitcoind as its chain backend

**Dependency:** Waits for `bitcoind` healthcheck to pass.

**Connections:**
```
lnd ──RPC──────> bitcoind:18443     (chain queries)
lnd <──ZMQ────── bitcoind:28332     (new block stream)
lnd <──ZMQ────── bitcoind:28333     (new tx stream)
```

**Ports exposed to host:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 10009 | gRPC | LND programmatic API |
| 8080 | REST/HTTPS | LND REST API |
| 9735 | P2P | Lightning peer connections |

---

### 3. `fedimintd` — Fedimint Guardian

**Image:** `fedimint/fedimintd:releases-v0.10.0`

The Fedimint guardian daemon. Manages a federated e-cash mint backed by Bitcoin. Connects directly to bitcoind for on-chain operations (deposits, withdrawals, watching for confirmations).

**Key environment variables:**
- `FM_BIND_API` / `FM_BIND_P2P` / `FM_BIND_UI` — listen addresses for the three interfaces
- `FM_BITCOIND_URL` — bitcoind RPC endpoint for on-chain operations
- `FM_BITCOIND_USERNAME` / `FM_BITCOIND_PASSWORD` — RPC credentials
- `FM_DATA_DIR` — persistent data (consensus state, e-cash database)

**Dependency:** Waits for `bitcoind` healthcheck.

**Connections:**
```
fedimintd ──RPC──> bitcoind:18443   (on-chain deposits/withdrawals)
```

**Ports exposed to host:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 8173 | TCP | Guardian peer-to-peer consensus |
| 8174 | WebSocket | Fedimint client API |
| 8175 | HTTP | Guardian setup and management UI |

---

### 4. `gatewayd` — Lightning Gateway

**Image:** `fedimint/gatewayd:releases-v0.10.0`

The bridge between Fedimint and Lightning. It holds an LND connection and can route payments between federation members and the external Lightning Network.

**How it connects to LND:**
- Mounts the `lnd_data` volume **read-only** to access LND's TLS certificate and admin macaroon
- Connects to LND's gRPC API at `lnd:10009`

**Key environment variables:**
- `FM_LND_RPC_ADDR` — LND gRPC endpoint
- `FM_LND_TLS_CERT` / `FM_LND_MACAROON` — auth files read from the shared volume
- `FM_GATEWAY_BCRYPT_PASSWORD_HASH` — bcrypt hash of the gateway admin password

**Command:** `gatewayd lnd` — tells the gateway to use LND as its Lightning backend (could also use `ldk`).

**Dependency:** Waits for both `lnd` and `fedimintd`.

**Connections:**
```
gatewayd ──gRPC──> lnd:10009         (send/receive Lightning payments)
gatewayd ──RPC───> bitcoind:18443    (on-chain fee estimation)
gatewayd ──WS────> fedimintd:8174    (federation API, after setup)
```

**Ports exposed to host:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 8176 | HTTP | Gateway management API |

---

### 5. `rtl` — Ride The Lightning UI

**Image:** `shahanafarooqui/rtl:v0.15.8`

A full-featured web UI for managing the LND node. Provides wallet management, channel operations, invoice creation, and payment history.

**How it connects to LND:**
- Mounts `lnd_data` read-only for the macaroon (authentication token)
- Connects to LND's REST API at `https://lnd:8080`

**Ports exposed to host:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 3003 | HTTP | RTL web interface |

---

### 6. `dashboard` — Unified Dashboard

**Image:** `nginx:alpine`

A custom single-page dashboard served by Nginx. It provides a unified view of all services and acts as a **reverse proxy** to reach each service's API from the browser.

**Nginx reverse proxy routes:**

```
Browser request              Proxied to (inside Docker network)
─────────────────            ──────────────────────────────────
/api/bitcoin/          →     http://bitcoind:18443/
/api/bitcoin-wallet/   →     http://bitcoind:18443/wallet/miner
/api/lnd/              →     https://lnd:8080/
/api/fedimint/         →     http://fedimintd:8174/
/api/gateway/          →     http://gatewayd:8176/
/                      →     static HTML dashboard
```

This lets the browser-based dashboard make API calls to all services through a single origin, avoiding CORS issues.

**Ports exposed to host:**
| Port | Protocol | Purpose |
|------|----------|---------|
| 3002 | HTTP | Dashboard web interface |

---

## Networking

All containers share a single Docker bridge network called `fedimint-net`. Containers reference each other by container name (e.g., `bitcoind`, `lnd`, `fedimintd`), which Docker's internal DNS resolves to the container's IP.

```
fedimint-net (bridge)
├── bitcoind      ← everyone connects here
├── lnd           ← rtl, gatewayd, dashboard connect here
├── fedimintd     ← gatewayd, dashboard connect here
├── gatewayd      ← dashboard connects here
├── rtl           ← standalone, connects to lnd
└── dashboard     ← reverse proxy to all services
```

No container is exposed to the public internet. All ports are bound to `0.0.0.0` on the host for local development access only.

---

## Data Persistence (Volumes)

Five named volumes store persistent state:

| Volume | Mounted in | Contains |
|--------|------------|----------|
| `bitcoin_data` | bitcoind | Blockchain data, wallets, indexes |
| `lnd_data` | lnd, gatewayd (ro), rtl (ro) | LND wallet, channels, TLS cert, macaroons |
| `fedimint_data` | fedimintd | Federation consensus state, e-cash database |
| `gateway_data` | gatewayd | Gateway configuration and federation connections |
| `rtl_data` | rtl | RTL session data and settings |

**Shared volume pattern:** `lnd_data` is mounted read-write in `lnd` but **read-only** (`:ro`) in `gatewayd` and `rtl`. This gives them access to LND's TLS certificate and macaroon for authentication without allowing them to modify LND's data.

```
lnd_data volume
├── tls.cert           ← read by gatewayd and rtl for TLS verification
├── tls.key            ← only lnd reads this
├── data/
│   └── chain/
│       └── bitcoin/
│           └── regtest/
│               └── admin.macaroon  ← read by gatewayd and rtl for auth
└── lnd.conf           ← bind-mounted from ./config/lnd/lnd.conf
```

---

## Startup Order

Docker Compose enforces this dependency chain:

```
bitcoind                    (starts first, has healthcheck)
    │
    ├──► lnd                (waits for bitcoind healthy)
    │      │
    │      ├──► rtl         (waits for lnd)
    │      │
    │      └──► gatewayd    (waits for lnd AND fedimintd)
    │                │
    ├──► fedimintd   │      (waits for bitcoind healthy)
    │        │       │
    │        └───────┘
    │
    └──► dashboard          (waits for all 5 services)
```

The `bitcoind` healthcheck (`bitcoin-cli getblockchaininfo`) ensures the RPC interface is ready before any dependent service attempts to connect.

---

## Configuration Flow

```
.env                         docker-compose.yml              Container
────                         ──────────────────              ─────────
BITCOIN_RPC_USER=bitcoin  →  -rpcuser=${BITCOIN_RPC_USER} →  bitcoind CLI flag
BITCOIN_RPC_PASS=bitcoin  →  FM_BITCOIND_PASSWORD=...     →  fedimintd env var
RTL_PASSWORD=password     →  RTL_PASS=${RTL_PASSWORD}     →  rtl env var
PORT_RTL=3003             →  "${PORT_RTL}:3000"           →  host:container port mapping
GATEWAY_PASSWORD_HASH=... →  FM_GATEWAY_BCRYPT_...        →  gatewayd env var
```

All tunables live in `.env`. The `docker-compose.yml` references them with `${VAR:-default}` syntax. Service-specific config files (`config/lnd/lnd.conf`, `config/bitcoin/bitcoin.conf`) live under `config/`; LND’s conf is bind-mounted read-only into the container.

---

## File Structure (this repo)

```
fedi-scripts/   (example clone name)
├── .env                        ← all configurable variables
├── .gitignore
├── docker-compose.yml          ← six stack services + volumes
├── README.md
├── EXPLAINED.md
├── ARCHITECTURE.md             ← this file
├── setup.sh                    ← bootstrap: start, create wallet, mine 101 blocks
├── mine.sh
├── fund-lnd.sh
├── status.sh
├── turbo.sh
├── config/
│   ├── bitcoin/
│   │   └── bitcoin.conf
│   ├── lnd/
│   │   └── lnd.conf
│   └── rtl/                    ← optional RTL-related assets
└── ui/
    ├── nginx.conf
    └── public/
        └── index.html
```
