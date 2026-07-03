#!/usr/bin/env bash
# scripts/secrets/setup-api-keys.sh
# Stores all homelab secrets in HashiCorp Vault.
# External Secrets Operator syncs them to K8s Secrets automatically.
# Usage: make secrets
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/turingpi-cluster1.conf}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       TuringPi Homelab — Secrets Setup (Vault)           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Secrets are stored in HashiCorp Vault — encrypted at rest."
echo "External Secrets Operator syncs them to K8s Secrets automatically."
echo "Press Enter to skip any key you don't have yet."
echo ""

if [[ ! -f "$HOME/.vault-init.json" ]]; then
  warn "~/.vault-init.json not found. Run 'make vault' first."
  exit 1
fi

VAULT_TOKEN=$(python3 -c "import sys,json; print(json.load(open('$HOME/.vault-init.json'))['root_token'])")

info "Opening Vault port-forward..."
kubectl port-forward -n vault svc/vault 8200:8200 &>/dev/null &
PF_PID=$!
sleep 3
trap "kill $PF_PID 2>/dev/null || true" EXIT

export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# ── Collect secrets ───────────────────────────────────────────────────────────
echo "── LLM API Keys ──────────────────────────────────────────────"
read -rsp "Anthropic API key (sk-ant-...): "    ANTHROPIC_KEY;    echo ""
read -rsp "Google Gemini API key (AIza...): "   GEMINI_KEY;       echo ""
read -rsp "LiteLLM master key (any password): " LITELLM_KEY;      echo ""

echo ""
echo "── Storage ───────────────────────────────────────────────────"
read -rsp "MinIO admin password: "  MINIO_PASSWORD;  echo ""
read -rsp "Postgres password: "     POSTGRES_PASS;   echo ""

echo ""
echo "── Remote Access ─────────────────────────────────────────────"
read -rsp "Tailscale auth key (tskey-auth-...): "  TAILSCALE_KEY;   echo ""
read -rsp "Cloudflare tunnel token: "               CF_TUNNEL;       echo ""
read -rsp "Cloudflare API token: "                  CF_API_TOKEN;    echo ""
read -rsp "Cloudflare Zone ID: "                    CF_ZONE_ID;      echo ""
read -rsp "Cloudflare Account ID: "                 CF_ACCOUNT_ID;   echo ""

echo ""
info "Writing secrets to Vault..."

[[ -n "$ANTHROPIC_KEY" ]] && vault kv put secret/llm-keys \
  ANTHROPIC_API_KEY="$ANTHROPIC_KEY" \
  GEMINI_API_KEY="${GEMINI_KEY:-placeholder}" \
  LITELLM_MASTER_KEY="${LITELLM_KEY:-changeme}" \
  && success "LLM keys → secret/llm-keys"

[[ -n "$MINIO_PASSWORD" ]] && vault kv put secret/minio \
  rootUser="minioadmin" rootPassword="$MINIO_PASSWORD" \
  && success "MinIO → secret/minio"

[[ -n "$POSTGRES_PASS" ]] && vault kv put secret/postgres \
  POSTGRES_USER="postgres" POSTGRES_PASSWORD="$POSTGRES_PASS" \
  && success "Postgres → secret/postgres"

[[ -n "$TAILSCALE_KEY" ]] && vault kv put secret/tailscale \
  AUTH_KEY="$TAILSCALE_KEY" \
  && success "Tailscale → secret/tailscale" \
  && echo "export TAILSCALE_AUTH_KEY='$TAILSCALE_KEY'" >> "$HOME/.turingpi"

[[ -n "$CF_TUNNEL" ]] && \
  vault kv put secret/cloudflare \
    TUNNEL_TOKEN="$CF_TUNNEL" \
    API_TOKEN="${CF_API_TOKEN:-}" \
    ZONE_ID="${CF_ZONE_ID:-}" \
    ACCOUNT_ID="${CF_ACCOUNT_ID:-}" \
  && success "Cloudflare → secret/cloudflare" \
  && kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f - \
  && kubectl create secret generic cloudflare-secrets \
      --from-literal=TUNNEL_TOKEN="$CF_TUNNEL" \
      --namespace cloudflare-tunnel \
      --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ All secrets stored in Vault                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "To rotate any key:"
echo "  vault kv patch secret/llm-keys ANTHROPIC_API_KEY=new-key"
echo "  # K8s Secret updates automatically within 60 seconds"
echo ""
echo "Next: make ai-stack → make tailscale → make cloudflare"
