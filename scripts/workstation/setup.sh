#!/usr/bin/env bash
# scripts/workstation/setup.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-shot setup for any new WSL2 Ubuntu workstation.
# Run this first on every new machine before anything else.
#
# Usage:
#   chmod +x scripts/workstation/setup.sh
#   ./scripts/workstation/setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BMC_IP="10.0.0.10"
BMC_USER="root"
TPI_VERSION="1.0.7"
SSH_KEY_PATH="$HOME/.ssh/turingpi_homelab"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
error()   { echo -e "${RED}✗${NC} $*"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       TuringPi Homelab — Workstation Setup               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Prompt for BMC password ───────────────────────────────────────────────────
BMC_PASSWORD=""
read -rsp "Enter BMC root password: " BMC_PASSWORD; echo ""

# ── Optional: paste existing token ────────────────────────────────────────────
echo ""
echo "If you have the BMC API token from another machine, paste it now."
echo "Press Enter to skip and fetch a new one automatically."
read -rp "BMC Token (or Enter to skip): " EXISTING_TOKEN

# ── Step 1: apt packages ──────────────────────────────────────────────────────
echo ""; echo "━━━ Step 1: Installing packages ━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo apt-get update -qq
sudo apt-get install -y ansible python3-pip sshpass nmap curl wget git jq xz-utils openssh-client 2>&1 | grep -E "Setting up|already installed" || true
success "Packages installed — $(ansible --version | head -1)"

# ── Step 2: tpi CLI ───────────────────────────────────────────────────────────
echo ""; echo "━━━ Step 2: Installing tpi v${TPI_VERSION} ━━━━━━━━━━━━━━━━━━━━━"
if command -v tpi &>/dev/null && tpi --version 2>/dev/null | grep -q "$TPI_VERSION"; then
  success "tpi ${TPI_VERSION} already installed"
else
  TPI_URL="https://github.com/turing-machines/tpi/releases/download/${TPI_VERSION}/tpi-x86_64-unknown-linux-musl.tar.gz"
  info "Downloading tpi from GitHub..."
  wget -q --show-progress -O /tmp/tpi.tar.gz "$TPI_URL"
  tar -xzf /tmp/tpi.tar.gz -C ~ ./usr/bin/tpi
  sudo mv ~/usr/bin/tpi /usr/local/bin/tpi
  sudo chmod +x /usr/local/bin/tpi
  rm -rf ~/usr /tmp/tpi.tar.gz
  success "tpi $(tpi --version) installed"
fi

# ── Step 3: Ansible Galaxy collections ───────────────────────────────────────
echo ""; echo "━━━ Step 3: Ansible Galaxy collections ━━━━━━━━━━━━━━━━━━━"
ansible-galaxy collection install \
  ansible.posix \
  community.general \
  community.docker \
  kubernetes.core
success "Ansible collections installed"

# ── Step 4: BMC credentials ───────────────────────────────────────────────────
echo ""; echo "━━━ Step 4: Saving BMC credentials ━━━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$EXISTING_TOKEN" ]]; then
  TOKEN="$EXISTING_TOKEN"
  info "Using provided token"
else
  info "Fetching new BMC token..."
  TOKEN=$(curl -sk -X POST "https://${BMC_IP}/api/bmc/authenticate" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${BMC_USER}\",\"password\":\"${BMC_PASSWORD}\"}" \
    | grep -o '"token":"[^"]*"' | cut -d'"' -f4 || true)
  [[ -z "$TOKEN" ]] && warn "Could not fetch token — check BMC connectivity" && TOKEN="FETCH_FAILED"
fi

cat > "$HOME/.turingpi" << EOF
# TuringPi Homelab Credentials — $(date)
# DO NOT commit this file to git
export BMC_IP="${BMC_IP}"
export BMC_USER="${BMC_USER}"
export BMC_PASSWORD="${BMC_PASSWORD}"
export BMC_TOKEN="${TOKEN}"
EOF
chmod 600 "$HOME/.turingpi"

grep -q "source ~/.turingpi" "$HOME/.bashrc" 2>/dev/null || echo 'source ~/.turingpi' >> "$HOME/.bashrc"
source "$HOME/.turingpi"
success "Credentials saved to ~/.turingpi (chmod 600)"

# ── Step 5: SSH keypair ───────────────────────────────────────────────────────
echo ""; echo "━━━ Step 5: SSH keypair ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -f "${SSH_KEY_PATH}" ]]; then
  success "SSH key exists: ${SSH_KEY_PATH}"
else
  ssh-keygen -t ed25519 -C "turingpi-homelab" -f "$SSH_KEY_PATH" -N ""
  success "SSH key generated: ${SSH_KEY_PATH}"
fi
echo ""; info "Public key:"; cat "${SSH_KEY_PATH}.pub"

# ── Step 6: BMC connectivity check ───────────────────────────────────────────
echo ""; echo "━━━ Step 6: BMC connectivity check ━━━━━━━━━━━━━━━━━━━━━━"
if tpi --host "$BMC_IP" --user "$BMC_USER" --password "$BMC_PASSWORD" power status 2>/dev/null; then
  success "BMC reachable and tpi working"
else
  warn "Cannot reach BMC at ${BMC_IP} — ensure you are on the same network"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ Workstation setup complete                            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Next step — flash the RK1 nodes:"
echo "  source ~/.turingpi"
echo "  make flash"
echo ""
