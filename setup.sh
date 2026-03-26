#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${CYAN}[setup]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[err ]${NC} $*"; }

COMPOSE="docker compose"

# ── wait for a container to become healthy / running ──────────
wait_for() {
  local svc="$1" max="${2:-60}" i=0
  log "Waiting for $svc …"
  while [ $i -lt $max ]; do
    if $COMPOSE exec -T "$svc" true 2>/dev/null; then
      ok "$svc is up"
      return 0
    fi
    sleep 2
    i=$((i + 2))
  done
  err "$svc did not start within ${max}s"
  return 1
}

# ── mine initial regtest blocks ───────────────────────────────
create_wallet() {
  $COMPOSE exec -T bitcoind bitcoin-cli -regtest \
    -rpcuser=bitcoin -rpcpassword=bitcoin \
    createwallet "miner" 2>/dev/null || true
}

mine_blocks() {
  local n="${1:-101}"
  log "Mining $n regtest blocks …"
  local addr
  addr=$($COMPOSE exec -T bitcoind bitcoin-cli -regtest \
    -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
    getnewaddress "" bech32)

  $COMPOSE exec -T bitcoind bitcoin-cli -regtest \
    -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
    generatetoaddress "$n" "$addr" > /dev/null
  ok "Mined $n blocks"
}

# ── show status ───────────────────────────────────────────────
show_info() {
  echo ""
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  Bitcoin / Lightning / Fedimint Stack${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"

  local height
  height=$($COMPOSE exec -T bitcoind bitcoin-cli -regtest \
    -rpcuser=bitcoin -rpcpassword=bitcoin \
    getblockcount 2>/dev/null || echo "0")
  echo -e "  Bitcoin block height : ${GREEN}${height}${NC}"

  echo ""
  echo -e "  ${GREEN}Dashboard${NC}        → http://localhost:3002"
  echo -e "  ${GREEN}RTL (Lightning)${NC}  → http://localhost:3003  (pass: password)"
  echo -e "  ${GREEN}Fedimint UI${NC}      → http://localhost:8175"
  echo -e "  ${GREEN}Bitcoin RPC${NC}      → http://localhost:18443"
  echo -e "  ${GREEN}LND REST${NC}         → https://localhost:8080"
  echo -e "  ${GREEN}LND gRPC${NC}         → localhost:10009"
  echo -e "  ${GREEN}Fedimint API${NC}     → ws://localhost:8174"
  echo -e "  ${GREEN}Gateway API${NC}      → http://localhost:8176"
  echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
  echo ""
}

# ── main ──────────────────────────────────────────────────────
main() {
  log "Starting all services …"
  $COMPOSE up -d

  wait_for bitcoind 60
  sleep 3

  create_wallet
  mine_blocks 101

  log "Waiting for LND to sync …"
  sleep 10

  show_info

  ok "Stack is ready! Use './mine.sh [N]' to mine more blocks."
}

main "$@"
