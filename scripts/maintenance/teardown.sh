#!/usr/bin/env bash
# scripts/maintenance/teardown.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARD_MODE=false; [[ "${1:-}" == "--hard" ]] && HARD_MODE=true

echo "This will reset the K3s+Cilium cluster on all RK1 nodes."
read -rp "Type 'yes' to continue: " confirm
[[ "$confirm" != "yes" ]] && { echo "Aborted."; exit 0; }

# K3s's own installer drops an uninstaller on each node type — use those instead
# of manually unwinding cluster state.
ansible k8s_control -i "$REPO_ROOT/ansible/inventory/hosts.yml" -m shell -a \
  'test -x /usr/local/bin/k3s-uninstall.sh && /usr/local/bin/k3s-uninstall.sh; rm -rf $HOME/.kube' \
  --become

ansible k8s_workers -i "$REPO_ROOT/ansible/inventory/hosts.yml" -m shell -a \
  'test -x /usr/local/bin/k3s-agent-uninstall.sh && /usr/local/bin/k3s-agent-uninstall.sh; rm -rf $HOME/.kube' \
  --become

# k3s-uninstall.sh cleans up the iptables rules and CNI config K3s itself created,
# but Cilium is a separately-installed add-on and leaves its own interfaces behind.
ansible rk1_nodes -i "$REPO_ROOT/ansible/inventory/hosts.yml" -m shell -a \
  'for i in cilium_vxlan cilium_host cilium_net; do ip link delete "$i" 2>/dev/null || true; done; rm -f /etc/cni/net.d/05-cilium.conflist' \
  --become

rm -f "$HOME/.kube/turingpi-cluster1.conf"

[[ "$HARD_MODE" == true ]] && "$REPO_ROOT/scripts/bmc/bmc-power.sh" off all
echo "✓ Teardown complete. Run 'make build' to rebuild."
