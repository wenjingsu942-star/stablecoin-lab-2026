#!/usr/bin/env bash
# Verify the already-deployed Sepolia contracts. Reads ETHERSCAN_API_KEY from .env.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
  echo "ETHERSCAN_API_KEY is empty"
  exit 1
fi
echo "key_length=${#ETHERSCAN_API_KEY}"

forge verify-contract \
  --chain sepolia \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --watch \
  0xdd21E34A176e7a999e7B821a4a78B9aE93B17F63 \
  src/MockUSDC.sol:MockUSDC

stable_args=$(cast abi-encode "constructor(address)" 0xaf75CE3e7623d10A5A44d0e5AB6c4A27642C1160)
forge verify-contract \
  --chain sepolia \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$stable_args" \
  --watch \
  0xbB14Af29E5a1a1cef3Ef15d80be9C3C792ddDD07 \
  src/SimpleStablecoin.sol:SimpleStablecoin

vault_args=$(cast abi-encode "constructor(address,address)" \
  0xdd21E34A176e7a999e7B821a4a78B9aE93B17F63 \
  0xbB14Af29E5a1a1cef3Ef15d80be9C3C792ddDD07)
forge verify-contract \
  --chain sepolia \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$vault_args" \
  --watch \
  0x31B6f07b125282a193BaA9A3deD1500CC074557F \
  src/Vault.sol:Vault
