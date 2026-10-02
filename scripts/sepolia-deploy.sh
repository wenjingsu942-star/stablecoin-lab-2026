#!/usr/bin/env bash
# Tier 2: deploy the 1:1 loop to Sepolia.
# The private key stays in .env, which is gitignored. This script prints only the address.
set -euo pipefail
cd "$(dirname "$0")/.."

RPC_DEFAULT=https://ethereum-sepolia-rpc.publicnode.com

if [[ ! -f .env ]] || grep -q '0000000000000000000000000000000000000000000000000000000000000000' .env; then
  umask 077
  OUT=$(cast wallet new)
  ADDR=$(echo "$OUT" | awk '/Address/ {print $2}')
  KEY=$(echo "$OUT" | awk '/Private key/ {print $3}')
  if [[ -z "$ADDR" || -z "$KEY" ]]; then
    echo "could not parse the new wallet"
    exit 1
  fi
  cat > .env << EOF
PRIVATE_KEY=$KEY
SEPOLIA_RPC_URL=$RPC_DEFAULT
ETHERSCAN_API_KEY=
EOF
  echo "created a throwaway wallet"
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
BAL=$(cast balance "$ADDR" --rpc-url "$SEPOLIA_RPC_URL")
echo "ADDRESS=$ADDR"
echo "BALANCE_WEI=$BAL"

if [[ "$BAL" == "0" ]]; then
  echo "NO_FUNDS"
  echo "Fund this address with Sepolia ETH, then run: bash scripts/sepolia-deploy.sh"
  exit 2
fi

ARGS=(
  script script/Deploy.s.sol:Deploy
  --rpc-url "$SEPOLIA_RPC_URL"
  --broadcast
  --private-key "$PRIVATE_KEY"
  -vv
)
if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
  ARGS+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

forge "${ARGS[@]}"
