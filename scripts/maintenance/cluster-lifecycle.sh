#!/usr/bin/env bash
# scripts/maintenance/cluster-lifecycle.sh
# Graceful whole-cluster shutdown/startup and an extended health check.
# Usage: cluster-lifecycle.sh {shutdown|startup|health-check} [--dry-run]
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/turingpi-cluster1.conf}"
export KUBECONFIG
SSH_KEY="$HOME/.ssh/turingpi_homelab"
SSH_OPTS=(-i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

[[ -f "$HOME/.turingpi" ]] && source "$HOME/.turingpi"
TPI="tpi --host ${BMC_IP:-} --user ${BMC_USER:-} --password ${BMC_PASSWORD:-}"

declare -A NODE_IP=( [rk1-control]=10.0.0.11 [rk1-worker-1]=10.0.0.12 [rk1-worker-2]=10.0.0.13 )
declare -A NODE_SLOT=( [rk1-control]=1 [rk1-worker-1]=2 [rk1-worker-2]=4 )
WORKERS=(rk1-worker-1 rk1-worker-2)

MODE="${1:-}"
DRY_RUN=false
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=true; done

FAILURES=0
WARNINGS=0

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { log "✗ FAIL: $*"; FAILURES=$((FAILURES + 1)); }
warn() { log "⚠ WARN: $*"; WARNINGS=$((WARNINGS + 1)); }
ok() { log "✓ $*"; }

# Executes state-changing commands for real, or prints them under --dry-run.
# Read-only checks should call their underlying command directly, not run().
redact() {
  local s="$*"
  [[ -n "${BMC_PASSWORD:-}" ]] && s="${s//${BMC_PASSWORD}/********}"
  printf '%s' "$s"
}

run() {
  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would run: $(redact "$@")"
  else
    log "running: $(redact "$@")"
    "$@"
  fi
}

ssh_node() {
  local ip="$1"; shift
  ssh "${SSH_OPTS[@]}" "ubuntu@${ip}" "$@"
}

wait_for_ssh() {
  local name="$1" ip="${NODE_IP[$1]}" timeout=180 elapsed=0
  log "Waiting for $name ($ip) to be SSH-reachable..."
  while ! ssh_node "$ip" true 2>/dev/null; do
    elapsed=$((elapsed + 5))
    if [[ $elapsed -ge $timeout ]]; then
      fail "$name did not become SSH-reachable within ${timeout}s"
      return 1
    fi
    sleep 5
  done
  ok "$name is SSH-reachable"
}

wait_for_nodes_ready() {
  local timeout=300 elapsed=0
  log "Waiting for all 3 nodes to show Ready..."
  while true; do
    local not_ready
    not_ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l)
    local total
    total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [[ "$not_ready" -eq 0 && "$total" -eq 3 ]]; then
      ok "All 3 nodes Ready"
      return 0
    fi
    elapsed=$((elapsed + 10))
    if [[ $elapsed -ge $timeout ]]; then
      fail "Not all nodes Ready within ${timeout}s"
      kubectl get nodes 2>/dev/null || true
      return 1
    fi
    log "  ...not all nodes Ready yet (${elapsed}s elapsed), retrying"
    sleep 10
  done
}

wait_for_pods_running() {
  local ns="$1" timeout=300 elapsed=0
  local ns_flag=(-n "$ns"); [[ "$ns" == "-A" ]] && ns_flag=(-A)
  log "Waiting for pods in ${ns} to be Running/Completed..."
  while true; do
    local bad
    bad=$(kubectl get pods "${ns_flag[@]}" --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"' | wc -l)
    if [[ "$bad" -eq 0 ]]; then
      ok "All pods in ${ns} Running/Completed"
      return 0
    fi
    elapsed=$((elapsed + 10))
    if [[ $elapsed -ge $timeout ]]; then
      fail "Pods in ${ns} not all Running/Completed within ${timeout}s"
      kubectl get pods "${ns_flag[@]}" --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"' || true
      return 1
    fi
    log "  ...${bad} pod(s) in ${ns} not ready yet (${elapsed}s elapsed), retrying"
    sleep 10
  done
}

check_longhorn_volumes() {
  local want_state="$1" # "detached" or "" (means: check robustness=healthy instead)
  local timeout="${2:-180}" elapsed=0
  while true; do
    local rows
    rows=$(kubectl get volumes -n longhorn-system --no-headers 2>/dev/null || true)
    if [[ -z "$rows" ]]; then
      ok "No Longhorn volumes found (nothing to check)"
      return 0
    fi
    local bad
    if [[ "$want_state" == "detached" ]]; then
      bad=$(echo "$rows" | awk '$3!="detached"' | wc -l)
    else
      bad=$(echo "$rows" | awk '$4!="healthy"' | wc -l)
    fi
    if [[ "$bad" -eq 0 ]]; then
      ok "All Longhorn volumes ${want_state:-healthy}"
      return 0
    fi
    elapsed=$((elapsed + 10))
    if [[ $elapsed -ge $timeout ]]; then
      fail "Not all Longhorn volumes ${want_state:-healthy} within ${timeout}s"
      echo "$rows"
      return 1
    fi
    log "  ...${bad} volume(s) not ${want_state:-healthy} yet (${elapsed}s elapsed), retrying"
    sleep 10
  done
}

check_pvcs_bound_or_not_failed() {
  local mode="$1" # "bound" = all must be Bound; "not-failed" = none Failed/Lost
  local rows
  rows=$(kubectl get pvc -A --no-headers 2>/dev/null || true)
  if [[ -z "$rows" ]]; then
    ok "No PVCs found (nothing to check)"
    return 0
  fi
  if [[ "$mode" == "bound" ]]; then
    local bad
    bad=$(echo "$rows" | awk '$3!="Bound"')
    if [[ -z "$bad" ]]; then
      ok "All PVCs Bound"
    else
      fail "Some PVCs are not Bound:"
      echo "$bad"
    fi
  else
    local bad
    bad=$(echo "$rows" | awk '$3=="Failed" || $3=="Lost"')
    if [[ -z "$bad" ]]; then
      ok "No PVCs in Failed/Lost state"
    else
      fail "Some PVCs are Failed/Lost:"
      echo "$bad"
    fi
  fi
}

wait_no_terminating_pods() {
  local timeout=120 elapsed=0
  log "Checking for pods stuck Terminating..."
  while true; do
    local terminating
    terminating=$(kubectl get pods -A -o json 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d['items'] if i['metadata'].get('deletionTimestamp')))" 2>/dev/null || echo 0)
    if [[ "$terminating" -eq 0 ]]; then
      ok "No pods stuck Terminating"
      return 0
    fi
    elapsed=$((elapsed + 10))
    if [[ $elapsed -ge $timeout ]]; then
      warn "${terminating} pod(s) still Terminating after ${timeout}s — proceeding anyway"
      return 0
    fi
    log "  ...${terminating} pod(s) still Terminating (${elapsed}s elapsed), retrying"
    sleep 10
  done
}

wait_power_state() {
  local slot="$1" want="$2" timeout=60 elapsed=0
  while true; do
    local state
    state=$($TPI power status 2>/dev/null | awk -v n="node${slot}:" 'tolower($1)==tolower(n) {print tolower($2)}')
    if [[ "$want" == "off" && "$state" == "off" ]]; then return 0; fi
    if [[ "$want" == "on" && ( "$state" == "on" ) ]]; then return 0; fi
    elapsed=$((elapsed + 5))
    if [[ $elapsed -ge $timeout ]]; then
      fail "Node in slot ${slot} did not reach power state '${want}' within ${timeout}s (last seen: ${state:-unknown})"
      return 1
    fi
    sleep 5
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# SHUTDOWN
# ─────────────────────────────────────────────────────────────────────────────
do_shutdown() {
  log "=== Cluster shutdown starting (dry-run=${DRY_RUN}) ==="

  log "Step 1/9: Cordoning nodes (workers first, then control)"
  run kubectl cordon "${WORKERS[@]}"
  run kubectl cordon rk1-control

  log "Step 2/9: Draining workers"
  run kubectl drain "${WORKERS[@]}" --ignore-daemonsets --delete-emptydir-data --timeout=300s

  if [[ "$DRY_RUN" == true ]]; then
    # Steps 3-5 poll real cluster state (Terminating pods, Longhorn detach,
    # PVC health) that can only meaningfully pass once the cordon/drain above
    # has actually happened. Under --dry-run that never ran, so these checks
    # would just spin until their timeouts and always report failure —
    # describe them instead of blocking on them.
    log "Step 3/9: [DRY-RUN] would check for pods stuck Terminating"
    log "Step 4/9: [DRY-RUN] would check all Longhorn volumes are detached"
    log "Step 5/9: [DRY-RUN] would check no PVCs are Failed/Lost"
  else
    log "Step 3/9: Checking for pods stuck Terminating"
    wait_no_terminating_pods

    log "Step 4/9: Checking all Longhorn volumes are detached"
    check_longhorn_volumes detached 180

    log "Step 5/9: Checking no PVCs are Failed/Lost"
    check_pvcs_bound_or_not_failed not-failed

    if [[ $FAILURES -gt 0 ]]; then
      log "Aborting before touching power — ${FAILURES} critical check(s) failed above."
      log "=== Shutdown ABORTED (${FAILURES} failures, ${WARNINGS} warnings) ==="
      exit 1
    fi
  fi

  log "Step 6/9: Stopping k3s-agent on workers via SSH"
  for name in "${WORKERS[@]}"; do
    run ssh_node "${NODE_IP[$name]}" "sudo systemctl stop k3s-agent"
  done

  log "Step 7/9: Stopping k3s on control plane via SSH"
  run ssh_node "${NODE_IP[rk1-control]}" "sudo systemctl stop k3s"

  log "Step 8/9: Powering off nodes via BMC (slot 4, then 2, then 1)"
  run $TPI power off --node 4
  [[ "$DRY_RUN" == false ]] && wait_power_state 4 off
  run $TPI power off --node 2
  [[ "$DRY_RUN" == false ]] && wait_power_state 2 off
  run $TPI power off --node 1
  [[ "$DRY_RUN" == false ]] && wait_power_state 1 off

  log "Step 9/9: Confirming all nodes show off"
  if [[ "$DRY_RUN" == false ]]; then
    $TPI power status
  else
    log "[DRY-RUN] would confirm: \$TPI power status shows nodes 1, 2, 4 off"
  fi

  log "=== Shutdown complete (${FAILURES} failures, ${WARNINGS} warnings) ==="
  [[ $FAILURES -gt 0 ]] && exit 1
  exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# STARTUP
# ─────────────────────────────────────────────────────────────────────────────
do_startup() {
  log "=== Cluster startup starting (dry-run=${DRY_RUN}) ==="

  log "Step 1/8: Powering on rk1-control (slot 1)"
  run $TPI power on --node 1
  if [[ "$DRY_RUN" == false ]]; then
    wait_power_state 1 on
    wait_for_ssh rk1-control
  fi

  log "Step 2/8: Powering on workers (slot 2, then slot 4)"
  run $TPI power on --node 2
  if [[ "$DRY_RUN" == false ]]; then
    wait_power_state 2 on
    wait_for_ssh rk1-worker-1
  fi
  run $TPI power on --node 4
  if [[ "$DRY_RUN" == false ]]; then
    wait_power_state 4 on
    wait_for_ssh rk1-worker-2
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] would wait for: nodes Ready, system pods Running, Longhorn healthy, PVCs Bound"
    run kubectl uncordon rk1-control "${WORKERS[@]}"
    log "=== Startup dry-run complete ==="
    exit 0
  fi

  log "Step 3/8: Waiting for all 3 nodes to be Ready"
  wait_for_nodes_ready

  log "Step 4/8: Waiting for system pods to be Running (kube-system, longhorn-system)"
  wait_for_pods_running kube-system
  wait_for_pods_running longhorn-system

  log "Step 5/8: Checking all Longhorn volumes are healthy"
  check_longhorn_volumes "" 180

  log "Step 6/8: Checking all PVCs are Bound"
  check_pvcs_bound_or_not_failed bound

  log "Step 7/8: Uncordoning all nodes"
  run kubectl uncordon rk1-control "${WORKERS[@]}"

  log "Step 8/8: Final health sweep — kubectl get pods -A"
  local bad
  bad=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"')
  if [[ -z "$bad" ]]; then
    ok "All pods Running/Completed"
  else
    warn "Some pods not yet Running/Completed (may still be settling post-uncordon):"
    echo "$bad"
  fi

  log "=== Startup complete (${FAILURES} failures, ${WARNINGS} warnings) ==="
  [[ $FAILURES -gt 0 ]] && exit 1
  exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH-CHECK
# ─────────────────────────────────────────────────────────────────────────────
do_health_check() {
  log "=== Cluster health check ==="

  echo ""; echo "═══ Nodes ═══"
  kubectl get nodes -o wide 2>/dev/null || fail "Cannot reach K8s API"
  local not_ready
  not_ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l)
  [[ "$not_ready" -eq 0 ]] && ok "All nodes Ready" || fail "${not_ready} node(s) not Ready"

  echo ""; echo "═══ Pods (non-Running/Completed) ═══"
  local bad_pods
  bad_pods=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"')
  if [[ -z "$bad_pods" ]]; then
    ok "All pods Running/Completed"
  else
    echo "$bad_pods"
    fail "Some pods are not Running/Completed"
  fi

  echo ""; echo "═══ PVCs ═══"
  check_pvcs_bound_or_not_failed bound

  echo ""; echo "═══ Longhorn Volumes ═══"
  kubectl get volumes -n longhorn-system 2>/dev/null || echo "(none)"
  check_longhorn_volumes "" 1

  echo ""; echo "═══ MetalLB Pool Usage ═══"
  local pool_range
  pool_range=$(kubectl get ipaddresspool -n metallb-system -o jsonpath='{.items[0].spec.addresses[0]}' 2>/dev/null || echo "")
  if [[ -n "$pool_range" ]]; then
    local start_ip end_ip start_last end_last pool_size
    start_ip="${pool_range%-*}"; end_ip="${pool_range#*-}"
    start_last="${start_ip##*.}"; end_last="${end_ip##*.}"
    pool_size=$((end_last - start_last + 1))
    local used
    used=$(kubectl get svc -A --no-headers 2>/dev/null | awk '$3=="LoadBalancer" && $4!="<none>" && $4!="<pending>"' | wc -l)
    log "MetalLB pool ${pool_range}: ${used}/${pool_size} IPs used"
  else
    warn "Could not read MetalLB IPAddressPool"
  fi

  echo ""; echo "═══ Swap (should be disabled on all nodes) ═══"
  for name in rk1-control "${WORKERS[@]}"; do
    local ip="${NODE_IP[$name]}"
    local svc_state
    svc_state=$(ssh_node "$ip" "systemctl is-active disable-swap" 2>/dev/null || echo "unreachable")
    local swap_out
    swap_out=$(ssh_node "$ip" "swapon --show" 2>/dev/null || echo "ERROR")
    if [[ "$svc_state" == "active" && -z "$swap_out" ]]; then
      ok "$name: disable-swap active, no swap on"
    else
      fail "$name: disable-swap=${svc_state}, swapon --show='${swap_out}'"
    fi
  done

  echo ""; echo "═══ eMMC Usage ═══"
  for name in rk1-control "${WORKERS[@]}"; do
    local ip="${NODE_IP[$name]}"
    local df_line
    df_line=$(ssh_node "$ip" "df -h /dev/mmcblk0p2" 2>/dev/null | tail -1 || echo "")
    if [[ -z "$df_line" ]]; then
      fail "$name: could not read eMMC usage"
      continue
    fi
    local use_pct
    use_pct=$(echo "$df_line" | awk '{print $5}' | tr -d '%')
    log "$name: eMMC $(echo "$df_line" | awk '{print $3"/"$2" ("$5")"}')"
    if [[ "$use_pct" -gt 70 ]]; then
      warn "$name: eMMC usage ${use_pct}% is above 70%"
    fi
  done

  echo ""; echo "═══ Summary ═══"
  log "Failures: ${FAILURES}, Warnings: ${WARNINGS}"
  if [[ $FAILURES -gt 0 ]]; then
    log "=== HEALTH CHECK: FAIL ==="
    exit 1
  else
    log "=== HEALTH CHECK: PASS ==="
    exit 0
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
case "$MODE" in
  shutdown) do_shutdown ;;
  startup) do_startup ;;
  health-check) do_health_check ;;
  *)
    echo "Usage: $0 {shutdown|startup|health-check} [--dry-run]"
    exit 1
    ;;
esac
