#!/usr/bin/env bash
# scripts/secrets/setup-api-keys.sh
# ─────────────────────────────────────────────────────────────────────────────
# Securely stores LLM API keys and other secrets as Kubernetes Secrets.
# Run this after the Kubernetes cluster is up, before deploying the AI stack.
#
# Stores:
#   - Anthropic API key  (for Claude via LiteLLM)
#   - Google Gemini key  (for Gemini via LiteLLM)
#   - LiteLLM master key (to authenticate apps calling the gateway)
#   - MinIO credentials  (S3 admin credentials)
#
# Usage:
#   ./scripts/secrets/setup-api-keys.sh
#   make secrets
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/turingpi-cluster1.conf}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       TuringPi Homelab — Secrets Setup                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Keys are stored as Kubernetes Secrets — encrypted at rest."
echo "They never touch disk on your workstation."
echo "Press Enter to skip any key you don't have yet."
echo ""

# ── Collect secrets ───────────────────────────────────────────────────────────
read -rsp "Anthropic API key (sk-ant-...): " ANTHROPIC_KEY; echo ""
read -rsp "Google Gemini API key (AIza...): " GEMINI_KEY; echo ""
read -rsp "LiteLLM master key (create any strong password): " LITELLM_KEY; echo ""
read -rsp "MinIO admin password (default: minioadmin123): " MINIO_PASSWORD; echo ""
MINIO_PASSWORD="${MINIO_PASSWORD:-minioadmin123}"

echo ""

# ── Create namespaces ─────────────────────────────────────────────────────────
for ns in litellm minio; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
done

# ── LLM API keys Secret ───────────────────────────────────────────────────────
info "Storing LLM API keys in namespace 'litellm'..."

KUBECTL_ARGS=()
[[ -n "$ANTHROPIC_KEY" ]] && KUBECTL_ARGS+=(--from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_KEY")
[[ -n "$GEMINI_KEY" ]]    && KUBECTL_ARGS+=(--from-literal=GEMINI_API_KEY="$GEMINI_KEY")
[[ -n "$LITELLM_KEY" ]]   && KUBECTL_ARGS+=(--from-literal=LITELLM_MASTER_KEY="$LITELLM_KEY")

if [[ ${#KUBECTL_ARGS[@]} -gt 0 ]]; then
  kubectl create secret generic llm-api-keys \
    "${KUBECTL_ARGS[@]}" \
    --namespace litellm \
    --dry-run=client -o yaml | kubectl apply -f -
  success "LLM API keys stored"
else
  echo "  No LLM API keys provided — skipping"
fi

# ── MinIO credentials ─────────────────────────────────────────────────────────
info "Storing MinIO credentials in namespace 'minio'..."
kubectl create secret generic minio-credentials \
  --from-literal=rootUser=minioadmin \
  --from-literal=rootPassword="$MINIO_PASSWORD" \
  --namespace minio \
  --dry-run=client -o yaml | kubectl apply -f -
success "MinIO credentials stored"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓ Secrets stored in Kubernetes                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "To verify:"
echo "  kubectl get secret llm-api-keys -n litellm"
echo "  kubectl get secret minio-credentials -n minio"
echo ""
echo "To update a key later, re-run this script — it is idempotent."
echo ""
echo "Next step: deploy the AI stack"
echo "  make ai-stack"
echo ""
