#!/usr/bin/env bash
# scripts/maintenance/health-check.sh
set -euo pipefail
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/turingpi-cluster1.conf}"

echo "═══ Kubernetes Nodes ════════════════════════════════════"
kubectl --kubeconfig="$KUBECONFIG" get nodes -o wide 2>/dev/null || echo "Cannot reach K8s API"

echo ""; echo "═══ Unhealthy Pods ══════════════════════════════════════"
kubectl --kubeconfig="$KUBECONFIG" get pods -A \
  --field-selector='status.phase!=Running' 2>/dev/null | grep -v Completed || echo "All pods healthy"

echo ""; echo "═══ Storage ═════════════════════════════════════════════"
kubectl --kubeconfig="$KUBECONFIG" get pv,pvc -A 2>/dev/null || echo "(none)"

echo ""; echo "═══ Ollama — Orin NX (10.0.0.14) ═══════════════════════"
curl -sf http://10.0.0.14:11434/api/tags --max-time 5 | \
  python3 -c "import sys,json; [print(f'  • {m[\"name\"]}') for m in json.load(sys.stdin).get('models',[])]" \
  2>/dev/null || echo "  Ollama not reachable"

echo ""; echo "═══ Ollama — Jetson Nano (10.0.0.15) ════════════════════"
curl -sf http://10.0.0.15:11434/api/tags --max-time 5 | \
  python3 -c "import sys,json; [print(f'  • {m[\"name\"]}') for m in json.load(sys.stdin).get('models',[])]" \
  2>/dev/null || echo "  Ollama not reachable"

echo ""; echo "═══ Services ════════════════════════════════════════════"
kubectl --kubeconfig="$KUBECONFIG" get svc -A --field-selector='spec.type=LoadBalancer' 2>/dev/null | \
  awk 'NR>1 {printf "  %-20s %-20s %s\n", $1, $2, $5}'

echo ""; echo "Checked at: $(date)"
