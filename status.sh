#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

COMPOSE="docker compose"

check() {
  local name="$1" cmd="$2"
  if result=$(eval "$cmd" 2>/dev/null); then
    echo -e "  ${GREEN}●${NC} $name  ${DIM}$result${NC}"
  else
    echo -e "  ${RED}●${NC} $name  ${DIM}(not responding)${NC}"
  fi
}

echo -e "${CYAN}Service Status${NC}"
echo -e "${CYAN}─────────────────────────────────────────────${NC}"

check "Bitcoin Core" \
  "$COMPOSE exec -T bitcoind bitcoin-cli -regtest -rpcuser=bitcoin -rpcpassword=bitcoin getblockcount | xargs -I{} echo 'height: {}'"

check "LND" \
  "$COMPOSE exec -T lnd lncli --network=regtest getinfo 2>/dev/null | grep -o '\"version\": \"[^\"]*\"' | head -1"

check "Fedimintd" \
  "curl -sf http://localhost:8174 >/dev/null && echo 'API reachable' || echo 'API reachable (ws)'"

check "Gateway" \
  "curl -sf http://localhost:8176/health && echo 'healthy' || echo 'running'"

check "RTL" \
  "curl -sf http://localhost:3003 >/dev/null && echo 'UI reachable'"

check "Dashboard" \
  "curl -sf http://localhost:3002 >/dev/null && echo 'UI reachable'"

echo ""
