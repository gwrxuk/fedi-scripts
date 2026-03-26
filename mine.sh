#!/usr/bin/env bash
set -euo pipefail

N="${1:-1}"
COMPOSE="docker compose"

ADDR=$($COMPOSE exec -T bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
  getnewaddress "" bech32)

$COMPOSE exec -T bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
  generatetoaddress "$N" "$ADDR" > /dev/null

HEIGHT=$($COMPOSE exec -T bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin \
  getblockcount)

echo "Mined $N block(s) — height is now $HEIGHT"
