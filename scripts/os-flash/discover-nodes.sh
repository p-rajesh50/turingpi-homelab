#!/usr/bin/env bash
# scripts/os-flash/discover-nodes.sh
# Scans network for freshly booted RK1 nodes and prints their IPs.
set -euo pipefail

SUBNET="${1:-10.0.0.0/24}"
command -v nmap &>/dev/null || sudo apt-get install -y nmap -q

echo "→ Scanning ${SUBNET} for ARM64 Ubuntu hosts (~30 seconds)..."
RESULTS=$(nmap -p 22 --open -T4 "$SUBNET" -oG - 2>/dev/null \
  | awk '/22\/open/{print $2}' | grep -v "10.0.0.10" || true)

[[ -z "$RESULTS" ]] && { echo "No hosts found yet. Wait 2 minutes and retry."; exit 0; }

echo ""; echo "Found SSH-reachable hosts:"; echo ""
i=1
while IFS= read -r ip; do
  HOSTNAME=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
    -o PasswordAuthentication=no ubuntu@"$ip" hostname 2>/dev/null || echo "unknown")
  ARCH=$(ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
    -o PasswordAuthentication=no ubuntu@"$ip" uname -m 2>/dev/null || echo "unknown")
  echo "  ${ip}  hostname=${HOSTNAME}  arch=${ARCH}"
  i=$((i+1))
done <<< "$RESULTS"

echo ""
echo "Update ansible/inventory/hosts.yml with the IPs above, then:"
echo "  make bootstrap"
