#!/usr/bin/env bash
# Ex1 and Ex3 on a local Anvil. Public Anvil keys only, from the Makefile.
set -euo pipefail
cd "$(dirname "$0")/.."

ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ATTACK_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ATTACKER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
RPC=http://127.0.0.1:8545
AMOUNT=1000000000
UNBACKED=1000000000000

anvil --port 8545 >/tmp/anvil-lab.log 2>&1 &
ANVIL_PID=$!
cleanup() { kill "$ANVIL_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

OUT=$(PRIVATE_KEY=$ANVIL_KEY forge script script/Deploy.s.sol:Deploy --rpc-url "$RPC" --broadcast)
echo "$OUT"
USDC=$(echo "$OUT" | awk '/MockUSDC/ {print $NF}')
SUSD=$(echo "$OUT" | awk '/SimpleStablecoin/ {print $NF}')
VAULT=$(echo "$OUT" | awk '/Vault[[:space:]]/ {print $NF}')
echo "USDC=$USDC"
echo "SUSD=$SUSD"
echo "VAULT=$VAULT"

cast send "$USDC" "faucet(address,uint256)" "$ME" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null
cast send "$USDC" "approve(address,uint256)" "$VAULT" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null
cast send "$VAULT" "deposit(uint256)" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null

echo "=== Ex1 after deposit (these three must match) ==="
echo -n "balanceOf(you)   "; cast call "$SUSD" "balanceOf(address)(uint256)" "$ME" --rpc-url "$RPC"
echo -n "totalSupply      "; cast call "$SUSD" "totalSupply()(uint256)" --rpc-url "$RPC"
echo -n "totalCollateral  "; cast call "$VAULT" "totalCollateral()(uint256)" --rpc-url "$RPC"

cast send "$VAULT" "redeem(uint256)" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null
echo "=== Ex1 after redeem ==="
echo -n "balanceOf(you)   "; cast call "$SUSD" "balanceOf(address)(uint256)" "$ME" --rpc-url "$RPC"
echo -n "totalSupply      "; cast call "$SUSD" "totalSupply()(uint256)" --rpc-url "$RPC"
echo -n "totalCollateral  "; cast call "$VAULT" "totalCollateral()(uint256)" --rpc-url "$RPC"

# Put honest collateral back, then show an unbacked mint.
cast send "$USDC" "faucet(address,uint256)" "$ME" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null
cast send "$USDC" "approve(address,uint256)" "$VAULT" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null
cast send "$VAULT" "deposit(uint256)" "$AMOUNT" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null

echo "=== Ex3 attacker mint before MINTER_ROLE (this must fail) ==="
if cast send "$SUSD" "mint(address,uint256)" "$ATTACKER" "$UNBACKED" --rpc-url "$RPC" --private-key "$ATTACK_KEY"; then
  echo "unexpected success"
  exit 1
else
  echo "reverted, as required"
fi

cast send "$SUSD" "grantRole(bytes32,address)" "$(cast keccak "MINTER_ROLE")" "$ATTACKER" --rpc-url "$RPC" --private-key "$ANVIL_KEY" >/dev/null
cast send "$SUSD" "mint(address,uint256)" "$ATTACKER" "$UNBACKED" --rpc-url "$RPC" --private-key "$ATTACK_KEY" >/dev/null

echo "=== Ex3 DEPEG: screenshot these two lines ==="
echo -n "totalSupply      "; cast call "$SUSD" "totalSupply()(uint256)" --rpc-url "$RPC"
echo -n "totalCollateral  "; cast call "$VAULT" "totalCollateral()(uint256)" --rpc-url "$RPC"
