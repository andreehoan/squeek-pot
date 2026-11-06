#!/usr/bin/env bash
# Squeek Pot — one-shot Sepolia deploy.
#
# Usage (from Git Bash, inside C:\Users\Admin\Documents\squeek-pot):
#     ./deploy-sepolia.sh <YOUR_VRF_SUBSCRIPTION_ID> [sepolia-rpc-url]
#
# It will PROMPT you for the deployer wallet's private key (hidden, never saved).
# Everything else is pre-filled with the verified staged-launch-1 + Chainlink addresses.
set -euo pipefail

export PATH="$PATH:/c/Users/Admin/.foundry/bin"

# --- your input -------------------------------------------------------------
SUB_ID="${1:-}"
RPC="${2:-https://ethereum-sepolia-rpc.publicnode.com}"
if [ -z "$SUB_ID" ]; then
  echo "ERROR: pass your VRF subscription id as the first argument."
  echo "   e.g.  ./deploy-sepolia.sh 12345678901234567890..."
  exit 1
fi

# --- verified constants (do not change) -------------------------------------
export SQK=0xd78a3956cf63164d1fa1c622ad3c66623162fa1e                               # staged-launch-1 SQK
export VRF_COORDINATOR=0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B                   # Chainlink VRF 2.5 (Sepolia)
export VRF_KEYHASH=0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae  # Sepolia gas lane
export VRF_SUB_ID="$SUB_ID"

# --- tunables (defaults are fine for testnet) -------------------------------
export VRF_PAY_NATIVE=true       # pay VRF in ETH (no LINK needed). Set back to false to use LINK instead.
export DRAW_INTERVAL=86400       # 1 day between draws
export FIRST_DRAW_DELAY=86400    # first draw 1 day after deploy

echo "Deploying SqueekPot to Sepolia..."
echo "  SQK            = $SQK"
echo "  VRF coordinator= $VRF_COORDINATOR"
echo "  VRF sub id     = $VRF_SUB_ID"
echo "  RPC            = $RPC"
echo "  pay VRF in     = $([ "$VRF_PAY_NATIVE" = true ] && echo ETH || echo LINK)"
echo
echo "You'll be asked for the deployer wallet's private key (input is hidden, nothing is stored)."
echo

forge script script/DeploySqueekPot.s.sol:DeploySqueekPot \
  --rpc-url "$RPC" \
  --broadcast \
  --interactive

echo
echo "DONE. Copy the 'SqueekPot deployed:' address above — that's your contract."
echo "Next: add it as a consumer on your VRF subscription at https://vrf.chain.link/sepolia"
