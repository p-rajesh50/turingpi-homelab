#!/usr/bin/env bash
# scripts/maintenance/teardown.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARD_MODE=false; [[ "${1:-}" == "--hard" ]] && HARD_MODE=true

echo "This will reset the Kubernetes cluster on all RK1 nodes."
read -rp "Type 'yes' to continue: " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 0; }

ansible rk1_nodes -i "$REPO_ROOT/ansible/inventory/hosts.yml" -m shell -a \
  'kubeadm reset -f && rm -rf /etc/kubernetes /etc/cni /opt/cni /var/lib/etcd /var/lib/kubelet $HOME/.kube' \
  --become

ansible rk1_nodes -i "$REPO_ROOT/ansible/inventory/hosts.yml" -m shell -a \
  'iptables -F && iptables -t nat -F && ip link delete flannel.1 2>/dev/null || true && ip link delete cni0 2>/dev/null || true' \
  --become

[[ "$HARD_MODE" == true ]] && "$REPO_ROOT/scripts/bmc/bmc-power.sh" off all
echo "✓ Teardown complete. Run 'make build' to rebuild."
