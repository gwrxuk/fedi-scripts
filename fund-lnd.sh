#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose"
AMOUNT="${1:-10}"

echo "Getting new LND address …"
LND_ADDR=$($COMPOSE exec -T lnd lncli --network=regtest newaddress p2wkh \
  | grep -o '"address": "[^"]*"' | cut -d'"' -f4)
echo "  LND address: $LND_ADDR"

echo "Sending $AMOUNT BTC from bitcoind to LND …"
$COMPOSE exec -T bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
  sendtoaddress "$LND_ADDR" "$AMOUNT"

echo "Mining 6 confirmations …"
MINE_ADDR=$($COMPOSE exec -T bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
  getnewaddress "" bech32)
$COMPOSE exec -T bitcoind bitcoin-cli -regtest \
  -rpcuser=bitcoin -rpcpassword=bitcoin -rpcwallet=miner \
  generatetoaddress 6 "$MINE_ADDR" > /dev/null

echo "Done! LND wallet funded with $AMOUNT BTC."

echo ""
echo "LND wallet balance:"
$COMPOSE exec -T lnd lncli --network=regtest walletbalance
