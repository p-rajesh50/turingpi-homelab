#!/usr/bin/env bash
# scripts/os-flash/flash-rk1.sh
# Flashes Ubuntu 22.04 onto RK1 nodes (slots 1, 3, 4) via BMC.
# Slot 2 is the Orin NX — never touched by this script.
#
# Usage:
#   ./scripts/os-flash/flash-rk1.sh              # flash all 3 RK1 nodes
#   ./scripts/os-flash/flash-rk1.sh --node 1     # flash single node
#   ./scripts/os-flash/flash-rk1.sh --skip-download
set -euo pipefail

[[ -f "$HOME/.turingpi" ]] && source "$HOME/.turingpi"

BMC_IP="${BMC_IP:-10.0.0.10}"
BMC_USER="${BMC_USER:-root}"
BMC_PASSWORD="${BMC_PASSWORD:-}"
IMAGE_VERSION="v1.33"
IMAGE_NAME="ubuntu-22.04.3-preinstalled-server-arm64-turing-rk1_${IMAGE_VERSION}.img"
IMAGE_XZ="${IMAGE_NAME}.xz"
IMAGE_SHA="${IMAGE_XZ}.sha256"
BASE_URL="https://firmware.turingpi.com/turing-rk1/ubuntu_22.04_rockchip_linux/${IMAGE_VERSION}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_PATH="${SCRIPT_DIR}/images/${IMAGE_NAME}"

# Confirmed: RK1 modules are in slots 1, 3, 4. Slot 2 is Orin NX — never flash here.
RK1_NODES=(1 3 4)

SKIP_DOWNLOAD=false; SINGLE_NODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-download) SKIP_DOWNLOAD=true ;;
    --node) SINGLE_NODE="$2"; shift ;;
  esac; shift
done
[[ -n "$SINGLE_NODE" ]] && RK1_NODES=("$SINGLE_NODE")

TPI="tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║       TuringPi RK1 — Automated OS Flash                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "  BMC: ${BMC_IP}  |  Nodes: ${RK1_NODES[*]}"
echo ""

# ── Dependency check ──────────────────────────────────────────────────────────
for cmd in tpi wget sha256sum xz; do
  command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found. Run: make setup"; exit 1; }
done

# ── BMC check ─────────────────────────────────────────────────────────────────
echo "→ Checking BMC..."
$TPI power status || { echo "ERROR: Cannot reach BMC at ${BMC_IP}"; exit 1; }
echo "  ✓ BMC reachable"

# ── Download ──────────────────────────────────────────────────────────────────
mkdir -p "${SCRIPT_DIR}/images"

if [[ "$SKIP_DOWNLOAD" == false && ! -f "$IMAGE_PATH" ]]; then
  echo "→ Downloading Ubuntu 22.04 RK1 image (719MB)..."
  wget --progress=bar:force:noscroll \
    -O "${SCRIPT_DIR}/images/${IMAGE_XZ}" "${BASE_URL}/${IMAGE_XZ}"
  wget -q -O "${SCRIPT_DIR}/images/${IMAGE_SHA}" "${BASE_URL}/${IMAGE_SHA}"

  echo "→ Verifying checksum..."
  cd "${SCRIPT_DIR}/images"
  sha256sum -c "$IMAGE_SHA" && echo "  ✓ Checksum OK" || { echo "  ✗ Checksum FAILED"; exit 1; }

  echo "→ Decompressing (~2 minutes)..."
  xz --decompress --keep "${SCRIPT_DIR}/images/${IMAGE_XZ}"
  echo "  ✓ Ready: ${IMAGE_PATH}"
fi

[[ ! -f "$IMAGE_PATH" ]] && { echo "ERROR: Image not found: ${IMAGE_PATH}"; exit 1; }

# ── Flash each node ───────────────────────────────────────────────────────────
for node in "${RK1_NODES[@]}"; do
  echo ""
  echo "━━━ Flashing Node ${node} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "→ Powering off node ${node}..."
  $TPI power off --node "$node"; sleep 3

  echo "→ Flashing Ubuntu 22.04 (~5-10 minutes)..."
  $TPI flash --node "$node" --image-path "$IMAGE_PATH"

  echo "→ Powering on node ${node}..."
  $TPI power on --node "$node"
  echo "  ✓ Node ${node} flash complete"

  [[ "${node}" != "${RK1_NODES[-1]}" ]] && { echo "→ Pausing 15s..."; sleep 15; }
done

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ All nodes flashed with Ubuntu 22.04                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Default credentials: ubuntu / ubuntu (forced change on first login)"
echo ""
echo "Wait ~60s for nodes to boot, then:"
echo "  make discover    ← find node IPs"
echo "  make bootstrap   ← push SSH keys and set static IPs"
