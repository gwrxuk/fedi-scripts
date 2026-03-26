#!/usr/bin/env bash
set -euo pipefail
#
# turbo.sh — Fast development shortcuts for the Bitcoin/Lightning/Fedimint stack.
#
# Usage:
#   ./turbo.sh <command> [args]
#
# Commands:
#   bootstrap     Full stack bootstrap (start + mine + fund)
#   reset         Tear down everything and rebuild from scratch
#   nuke          Remove all containers, volumes, and images
#   cycle         Restart all containers without losing data
#   fund [amt]    Create wallet + mine + fund LND (default 10 BTC)
#   mine [n]      Mine n blocks (default 10)
#   logs [svc]    Tail logs for a service (default: all)
#   health        Run status.sh (service RPC/UI checks)
#   status        Compact one-line-per-service status

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[turbo]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ✓  ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn]${NC} $*"; }
err()  { echo -e "${RED}[ err ]${NC} $*"; }

COMPOSE="docker compose"
RPC="docker compose exec -T bitcoind bitcoin-cli -regtest -rpcuser=bitcoin -rpcpassword=bitcoin"
RPC_W="$RPC -rpcwallet=miner"

cmd_bootstrap() {
  log "Full stack bootstrap..."
  $COMPOSE up -d
  log "Waiting for bitcoind..."
  sleep 8
  $RPC createwallet miner 2>/dev/null || $RPC loadwallet miner 2>/dev/null || true
  log "Mining 101 blocks..."
  local addr
  addr=$($RPC_W getnewaddress "" bech32)
  $RPC_W generatetoaddress 101 "$addr" > /dev/null
  log "Waiting for LND sync..."
  sleep 8
  log "Funding LND..."
  bash "$(dirname "$0")/fund-lnd.sh" "${1:-10}" 2>/dev/null || warn "LND funding skipped (may need more time to sync)"
  ok "Stack bootstrapped. Dashboard: http://localhost:3002"
}

cmd_reset() {
  log "Tearing down and rebuilding..."
  $COMPOSE down -v --remove-orphans
  $COMPOSE build --no-cache
  cmd_bootstrap
}

cmd_nuke() {
  warn "This will remove ALL containers, volumes, and images for this project."
  $COMPOSE down -v --rmi local --remove-orphans
  ok "Everything removed. Run './turbo.sh bootstrap' to start fresh."
}

cmd_cycle() {
  log "Cycling all containers..."
  $COMPOSE restart
  sleep 5
  $RPC loadwallet miner 2>/dev/null || true
  ok "All containers restarted."
}

cmd_fund() {
  local amt="${1:-10}"
  $RPC createwallet miner 2>/dev/null || $RPC loadwallet miner 2>/dev/null || true
  local addr
  addr=$($RPC_W getnewaddress "" bech32)
  $RPC_W generatetoaddress 6 "$addr" > /dev/null
  log "Funding LND with $amt BTC..."
  bash "$(dirname "$0")/fund-lnd.sh" "$amt"
  local addr2
  addr2=$($RPC_W getnewaddress "" bech32)
  $RPC_W generatetoaddress 6 "$addr2" > /dev/null
  ok "Funded LND with $amt BTC and confirmed."
}

cmd_mine() {
  local n="${1:-10}"
  $RPC createwallet miner 2>/dev/null || $RPC loadwallet miner 2>/dev/null || true
  local addr
  addr=$($RPC_W getnewaddress "" bech32)
  $RPC_W generatetoaddress "$n" "$addr" > /dev/null
  local height
  height=$($RPC getblockcount)
  ok "Mined $n blocks (height: $height)"
}

cmd_logs() {
  local svc="${1:-}"
  if [ -z "$svc" ]; then
    $COMPOSE logs --tail=50 -f
  else
    $COMPOSE logs --tail=100 -f "$svc"
  fi
}

cmd_health() {
  bash "$(dirname "$0")/status.sh"
}

cmd_status() {
  echo -e "${BOLD}Service Status${NC}"
  echo "─────────────────────────────────────"
  for svc in bitcoind lnd fedimintd gatewayd rtl dashboard; do
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "not found")
    case "$state" in
      running) echo -e "  ${GREEN}●${NC} $svc: ${GREEN}$state${NC}" ;;
      *)       echo -e "  ${RED}●${NC} $svc: ${RED}$state${NC}" ;;
    esac
  done
}

show_help() {
  echo -e "${BOLD}turbo.sh${NC} — Fast development shortcuts"
  echo ""
  echo "Usage: ./turbo.sh <command> [args]"
  echo ""
  echo "Commands:"
  echo "  bootstrap     Full stack bootstrap (start + mine + fund)"
  echo "  reset         Tear down and rebuild from scratch"
  echo "  nuke          Remove all containers, volumes, and images"
  echo "  cycle         Restart all containers without data loss"
  echo "  fund [amt]    Create wallet + mine + fund LND (default 10 BTC)"
  echo "  mine [n]      Mine n blocks (default 10)"
  echo "  logs [svc]    Tail logs (all services or specific)"
  echo "  health        Run ./status.sh"
  echo "  status        One-line status for each stack service"
  echo ""
}

case "${1:-}" in
  bootstrap) shift; cmd_bootstrap "$@" ;;
  reset)     cmd_reset ;;
  nuke)      cmd_nuke ;;
  cycle)     cmd_cycle ;;
  fund)      shift; cmd_fund "$@" ;;
  mine)      shift; cmd_mine "$@" ;;
  logs)      shift; cmd_logs "$@" ;;
  health)    cmd_health ;;
  status)    cmd_status ;;
  help|--help|-h) show_help ;;
  *)
    err "Unknown command: ${1:-}"
    show_help
    exit 1
    ;;
esac
