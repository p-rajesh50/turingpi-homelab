# Operational Runbook — TuringPi Homelab Cluster 1

Severity-ordered playbook for common cluster problems. Each entry covers:
how to detect it, why it happens on this cluster specifically, how to fix
it, how to confirm the fix worked, and how to stop it recurring.

## Cluster constants (referenced throughout)

```bash
KUBECONFIG=~/.kube/turingpi-cluster1.conf
SSH_KEY=~/.ssh/turingpi_homelab          # ssh -i $SSH_KEY ubuntu@<ip>
source ~/.turingpi                        # BMC_IP, BMC_USER, BMC_PASSWORD

# Nodes
rk1-control   10.0.0.11   BMC slot 1
rk1-worker-1  10.0.0.12   BMC slot 2
rk1-worker-2  10.0.0.13   BMC slot 4
# Slot 3 is PERMANENTLY FAULTY (DSA switch port) — never assign a node there.

# Vault CLI access requires a port-forward first:
kubectl port-forward -n vault svc/vault 8200:8200
# then, in another shell: export VAULT_ADDR=http://127.0.0.1:8200

# fail2ban's jail.local (ansible/roles/common) whitelists 127.0.0.1/8, ::1,
# and 10.0.0.0/24 only — a workstation connecting from outside the LAN
# (e.g. over Tailscale/VPN, or a different subnet) is NOT whitelisted.

# Tailscale runs on rk1-control ONLY. Never install/enable it on the
# workers — see HIGH: "Tailscale breaking LAN connectivity" below for why.

# scripts/maintenance/cluster-lifecycle.sh health-check (make cluster-health)
# automates a large chunk of the detection steps below in one pass.
```

---

## CRITICAL (immediate action required)

### Node NotReady

**Detect**
```bash
kubectl get nodes
# STATUS column shows NotReady
kubectl describe node <name> | grep -A5 Conditions
```

**Root cause (this cluster)**
The #1 historical cause here was a Tailscale subnet-routing conflict:
`rk1-control` advertising `10.0.0.0/24` combined with `--accept-routes` on
a worker that's already natively on that same subnet hijacked the worker's
return-traffic routing, breaking kubelet→apiserver connectivity while the
Tailscale tunnel itself stayed "up" (misleading). This can only happen again
if Tailscale is ever reinstalled on a worker — it must not be. Other causes:
node powered off/rebooting, `k3s`/`k3s-agent` service stopped or crashed,
eMMC full enough to block writes (see HIGH: eMMC >80%).

**Remediation**
```bash
# 1. Confirm it's not just a Tailscale problem on that node:
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo tailscale status 2>&1; systemctl is-active tailscaled 2>&1"
# If tailscaled is active on a WORKER, that's the bug — remove it:
ssh -i $SSH_KEY ubuntu@<worker-ip> "sudo tailscale down; sudo systemctl disable --now tailscaled; sudo apt remove --purge -y tailscale"

# 2. Check the k3s/k3s-agent service itself:
ssh -i $SSH_KEY ubuntu@<node-ip> "systemctl status k3s 2>&1; systemctl status k3s-agent 2>&1"
# rk1-control runs k3s (server); workers run k3s-agent.

# 3. If stopped, restart it:
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo systemctl start k3s"       # rk1-control
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo systemctl start k3s-agent" # workers

# 4. If unreachable over SSH at all, check power via BMC:
$TPI power status   # ($TPI = tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD)
```

**Verify**
```bash
kubectl get nodes   # target node back to Ready
kubectl get pods -A | grep -v -E "Running|Completed"   # nothing stuck on that node
```

**Prevent**
Never install Tailscale on `rk1-worker-1`/`rk1-worker-2`. Run
`make cluster-health` periodically — it checks node readiness alongside
swap/eMMC/Longhorn/PVC state in one pass.

---

### Longhorn volume Faulted/Degraded

**Detect**
```bash
kubectl get volumes -n longhorn-system
# ROBUSTNESS column: faulted or degraded instead of healthy
kubectl -n longhorn-system get replicas -l longhornvolume=<volume-name> \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeID,STATE:.status.currentState
```

**Root cause (this cluster)**
`degraded` during a replica rebuild (e.g. after a node reboot, or a
Longhorn-native eviction) is expected and usually self-heals — Longhorn
schedules a new replica on another disk and rebuilds it. `faulted` means a
replica actually failed; on this cluster specifically, watch for a
recurrence of a bug hit during the eMMC-reclaim work: replica processes can
fail to start with `open /var/log/instances/<name>.log: no such file or
directory` inside the `instance-manager` pod on the target node — an
internal Longhorn cleanup race, not something caused by normal cluster
operation. Also check whether `/var/lib/longhorn` on the target node was
recently deleted/recreated — it hosts `engine-binaries/`, not just replica
data; wiping it removes the engine binary Longhorn needs to spawn new
replica processes there.

**Remediation**
```bash
# 1. Check if it's an in-progress, expected rebuild (see MEDIUM section below)
#    before assuming it's broken — give it a few minutes first.

# 2. If faulted and stuck, check the instance-manager on the replica's node:
kubectl -n longhorn-system get pods -o wide | grep instance-manager
kubectl -n longhorn-system logs <instance-manager-pod> --tail=100 | grep -i "<volume-name>\|FailedStarting"

# 3. If you see the /var/log/instances error above, confirm the binary exists
#    on that node (replace <node-ip>):
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo find /var/lib/longhorn/engine-binaries/ -type f"
# If empty/missing, force the engine-image DaemonSet pod on that node to
# re-extract it:
kubectl -n longhorn-system get pods -o wide | grep engine-image   # find the pod on that node
kubectl -n longhorn-system delete pod <engine-image-pod-on-that-node>
# It's DaemonSet-managed and will recreate itself; re-check the binary after.

# 4. Do NOT `rm -rf /var/lib/longhorn` on any node to "fix" this — check
#    scheduled replicas first (see MEDIUM: multipathd section for the same
#    caution) — it can hold live data other volumes still depend on.
```

**Verify**
```bash
kubectl -n longhorn-system get volumes   # ROBUSTNESS back to healthy
kubectl -n longhorn-system get replicas -l longhornvolume=<volume-name>   # all running
```

**Prevent**
Never `rm -rf` a node's `/var/lib/longhorn` without first confirming
`kubectl -n longhorn-system get nodes.longhorn.io <node> -o jsonpath='{.status.diskStatus.*.scheduledReplica}'`
is empty. Prefer Longhorn's own eviction (`allowScheduling: false` +
`evictionRequested: true` on the disk) over any raw filesystem deletion.

---

### Vault Sealed

**Detect**
```bash
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200
kubectl exec vault-0 -n vault -- vault status 2>/dev/null
# "Sealed: true" — or ExternalSecrets across the cluster start failing sync
kubectl get externalsecrets -A   # SecretSynced condition flips to False
```

**Root cause (this cluster)**
Vault re-seals on every pod restart (rescheduled pod, node reboot, Helm
upgrade) — this is expected Vault behavior, not a bug. The unseal keys live
in `~/.vault-init.json` on the workstation only — **back this file up**,
losing it means losing access to every secret in Vault permanently.

**Remediation**
```bash
make vault-unseal
# equivalent to:
#   VAULT_KEYS=$(python3 -c "import json; d=json.load(open('$HOME/.vault-init.json')); [print(k) for k in d['unseal_keys_b64'][:3]]")
#   for key in $VAULT_KEYS; do kubectl exec vault-0 -n vault -- vault operator unseal $key; done
```

**Verify**
```bash
make vault-status
# "Sealed: false"
kubectl get externalsecrets -A   # all back to SecretSynced=True within ~60s (ESO refresh interval)
```

**Prevent**
Keep `~/.vault-init.json` backed up somewhere off this single workstation.
Run `make vault-unseal` proactively right after any Vault pod restart
(`kubectl get pods -n vault -w`) rather than waiting for downstream
ExternalSecret failures to surface it.

---

### PVC in Lost/Failed state

**Detect**
```bash
kubectl get pvc -A
# STATUS column: Lost or Failed instead of Bound
```

**Root cause (this cluster)**
Almost always downstream of the underlying Longhorn volume itself being
`faulted` (see above) rather than a PVC-layer problem — every PVC in this
cluster is backed by the `longhorn` StorageClass on NVMe-backed replicas
(rk1-worker-1/rk1-worker-2 only; rk1-control never hosts Longhorn data by
design). Fix the volume first.

**Remediation**
```bash
# 1. Find the backing volume and check its real state:
kubectl get pvc <name> -n <namespace> -o jsonpath='{.spec.volumeName}'
kubectl -n longhorn-system get volume <volume-name-from-above>

# 2. Work the Longhorn volume problem (CRITICAL section above) first.

# 3. Only if the volume is genuinely unrecoverable and this is a
#    non-critical workload (not Vault/Longhorn-system itself), the PVC/PV
#    pair may need to be deleted and recreated by its owning
#    Deployment/StatefulSet on next reconcile — this is destructive, confirm
#    no other recovery path exists first.
```

**Verify**
```bash
kubectl get pvc -A   # STATUS back to Bound
kubectl get pods -n <namespace>   # pod using it back to Running
```

**Prevent**
Same as Longhorn volume prevention above — never delete a node's
`/var/lib/longhorn` without confirming zero scheduled replicas first.

---

### All pods evicted

**Detect**
```bash
kubectl get pods -A -o wide | grep Evicted
kubectl get nodes   # check for NotReady or resource-pressure taints
```

**Root cause (this cluster)**
Either (a) a node went `NotReady` for longer than the default pod-eviction
grace period and the control plane rescheduled everything off it, or (b) a
manual `kubectl drain` (e.g. via `scripts/maintenance/cluster-lifecycle.sh
shutdown`) ran and pods couldn't reschedule anywhere because all 3 nodes
were being drained/powered off together. If this happened during a
`cluster-lifecycle.sh shutdown` run, that's expected — the script cordons
+ drains deliberately before power-off. If it happened unexpectedly, work
the Node NotReady entry above first.

**Remediation**
```bash
# 1. Clean up Evicted pod objects (they don't self-delete):
kubectl get pods -A --field-selector=status.phase=Failed -o json | \
  kubectl delete -f -

# 2. If nodes are back Ready and cordoned from a shutdown/drain, uncordon:
kubectl uncordon rk1-control rk1-worker-1 rk1-worker-2
# (cluster-lifecycle.sh startup does this automatically as its own last step)

# 3. Deployments/StatefulSets reschedule automatically once nodes are
#    schedulable again — watch:
kubectl get pods -A -w
```

**Verify**
```bash
kubectl get pods -A | grep -v -E "Running|Completed"   # empty
kubectl get nodes   # all Ready, none cordoned (STATUS has no SchedulingDisabled)
```

**Prevent**
Use `make cluster-shutdown`/`make cluster-startup` for any deliberate
full-cluster power cycle instead of ad hoc `kubectl drain`/BMC power
commands — it sequences cordon→drain→verify→power-off and the reverse
correctly, including the Longhorn-detached and PVC-not-Failed gating checks
before it ever touches power.

---

## HIGH (action within 1 hour)

### Pod CrashLoopBackOff

**Detect**
```bash
kubectl get pods -A | grep CrashLoopBackOff
kubectl logs <pod> -n <namespace> --previous
kubectl describe pod <pod> -n <namespace> | tail -20
```

**Root cause**
Generic Kubernetes failure mode — check `--previous` logs first (the
crashed container's output, not the fresh restart's empty log). Common
causes on this cluster specifically: a Helm `existingSecret` pointing at a
Secret that hasn't synced from Vault yet (see ExternalSecret sync failures
below), a `RollingUpdate` deadlock on an RWO Longhorn PVC (see MEDIUM
below — usually shows as `Pending`/`ContainerCreating`, not
CrashLoopBackOff, but can present this way if the app itself then fails
fast on a missing volume), or a genuine app misconfiguration.

**Remediation**
```bash
# 1. Read the actual crash reason:
kubectl logs <pod> -n <namespace> --previous

# 2. Check for a missing/unsynced secret if the app needs Vault-sourced config:
kubectl get externalsecrets -n <namespace>

# 3. Check recent events for scheduling/volume clues:
kubectl get events -n <namespace> --sort-by=.lastTimestamp | tail -20

# 4. If it's a bad rollout, roll back:
kubectl rollout undo deployment/<name> -n <namespace>
```

**Verify**
```bash
kubectl get pods -n <namespace>   # Running, RESTARTS count stops climbing
```

**Prevent**
Ensure any new Helm-deployed app whose password/config comes from Vault has
a working `ExternalSecret` applied *before* the app's own install task runs
(this repo's convention — see `ansible/roles/gitea`/`external-secrets` for
the pattern of applying the ExternalSecret and waiting for
`condition=Ready` before the Helm install).

---

### eMMC disk >80%

**Detect**
```bash
# Fast path — this is one of cluster-lifecycle.sh health-check's own checks:
make cluster-health   # warns automatically if any node's eMMC >70%

# Manual:
for ip in 10.0.0.11 10.0.0.12 10.0.0.13; do
  ssh -i $SSH_KEY ubuntu@$ip "hostname; df -h /dev/mmcblk0p2"
done
```

**Root cause (this cluster)**
Hit for real on `rk1-worker-2` at 86%. Two specific root causes found:
(1) a leftover, *actively running* standalone `containerd.service` from the
pre-K3s kubeadm cluster — K3s embeds its own containerd under
`/var/lib/rancher/k3s/agent/containerd` and never uses the system package;
the leftover one silently filled `/var/lib/containerd` (11G on
rk1-worker-2). (2) `/var/lib/rancher` (K3s's own live data — server/agent
state, embedded containerd images) growing on the 29G eMMC instead of the
much larger NVMe disk. Note: `/var/lib/kubelet` is **not** cruft on this
cluster — it's K3s's live kubelet root-dir (pod volume mounts, CSI
sockets) on every node; never delete it.

**Remediation**
```bash
# 1. Check for the leftover containerd.service (common on nodes that
#    predate the K3s migration):
ssh -i $SSH_KEY ubuntu@<node-ip> "systemctl is-active containerd 2>&1; systemctl is-enabled containerd 2>&1"
# If active/enabled, stop it (only after confirming K3s doesn't use it —
# check `ps aux | grep containerd` for the -address /run/k3s/containerd/... shim):
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo systemctl stop containerd; sudo systemctl disable containerd; sudo systemctl mask containerd; sudo rm -rf /var/lib/containerd"
# (ansible/roles/common now does this automatically on every `make common`
#  run going forward — this is only needed for a node that somehow regresses.)

# 2. If /var/lib/rancher is large and the node has a mounted NVMe at
#    /var/lib/longhorn-nvme, move it (STOP k3s/k3s-agent first):
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo systemctl stop k3s-agent"   # or k3s on rk1-control
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo mv /var/lib/rancher /var/lib/longhorn-nvme/rancher && sudo ln -s /var/lib/longhorn-nvme/rancher /var/lib/rancher"
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo systemctl start k3s-agent"
# rk1-control has NO NVMe filesystem mounted (physically present but
# unpartitioned) — do not attempt this move there; its eMMC has more
# headroom (46% as of this writing) and doesn't need it.
```

**Verify**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> "df -h /dev/mmcblk0p2"
kubectl get nodes   # still Ready throughout
make cluster-health   # no eMMC warning
```

**Prevent**
`ansible/roles/common/tasks/main.yml` now strips any leftover
`containerd.service` automatically. `ansible/roles/k3s-server` and
`k3s-agent` now pre-symlink `/var/lib/containerd` and `/var/lib/rancher`
into `/var/lib/longhorn-nvme/` before the K3s installer runs, whenever that
mount already exists — so a future reinstall on an already-NVMe-provisioned
node won't regress back onto eMMC.

---

### Tailscale breaking LAN connectivity on worker nodes

**Detect**
```bash
# LAN/kubelet connectivity breaks while Tailscale itself looks fine — the
# misleading part of this incident:
ping -c3 10.0.0.12   # or .13 — plain LAN ping fails/times out
ssh -i $SSH_KEY ubuntu@10.0.0.12 true   # SSH also fails
kubectl get nodes   # that worker shows NotReady
# But on the node itself (if still reachable another way), tailscale status
# shows the tunnel as "up" — do not trust that as a sign of health.
```

**Root cause (this cluster)**
Tailscale must run on `rk1-control` ONLY. `rk1-control` advertises
`10.0.0.0/24` as a subnet route (`--advertise-routes=10.0.0.0/24
--snat-subnet-routes=false`). If Tailscale is ever installed on a worker
with `--accept-routes` enabled, the worker — already natively on that same
`10.0.0.0/24` subnet — gets its return traffic for that subnet redirected
through `tailscale0` instead of its normal LAN interface, breaking plain
SSH/ICMP/kubelet-to-apiserver connectivity while the tunnel itself stays
up.

**Remediation**
```bash
# Full removal from the affected worker:
ssh -i $SSH_KEY ubuntu@<worker-ip> "sudo tailscale down"
ssh -i $SSH_KEY ubuntu@<worker-ip> "sudo systemctl disable --now tailscaled"
ssh -i $SSH_KEY ubuntu@<worker-ip> "sudo apt remove --purge -y tailscale"
ssh -i $SSH_KEY ubuntu@<worker-ip> "sudo iptables -F"   # clear any tailscale-added rules if connectivity still doesn't recover
```

**Verify**
```bash
ping -c3 <worker-ip>
kubectl get nodes   # worker back to Ready
```

**Prevent**
`ansible/playbooks/10-tailscale.yml` targets `k8s_control` only (not
`rk1_nodes`) — do not change this without solving the overlapping-subnet
routing conflict first (e.g. a genuinely non-overlapping advertised range).
`ansible/roles/tailscale` also documents the reusable-auth-key requirement
and the `--snat-subnet-routes=false` flag needed on rk1-control itself.

---

### ExternalSecret sync failures

**Detect**
```bash
kubectl get externalsecrets -A
# READY column False, or SecretSynced condition False
kubectl describe externalsecret <name> -n <namespace> | grep -A5 Status
```

**Root cause (this cluster)**
Hit for real with LiteLLM's `llm-api-keys` ExternalSecret: `cannot find
secret data for key: "ANTHROPIC_API_KEY"` — the source Vault path
(`secret/llm-keys`) was missing that key because `setup-api-keys.sh` only
writes it if the interactive prompt wasn't left blank. Also seen
transiently on Gitea/LiteLLM when the target namespace didn't exist yet at
apply time (self-heals once both the namespace and the Vault path exist —
External Secrets Operator retries on its own `refreshInterval`, typically
1m).

**Remediation**
```bash
# 1. Confirm the Vault path actually has the expected keys (read-only,
#    do NOT dump values — check keys only):
kubectl port-forward -n vault svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200
ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.vault-init.json'))['root_token'])")
kubectl exec vault-0 -n vault -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv get -field= secret/<path>" 2>&1 | head -1
# or just check which keys exist:
kubectl exec vault-0 -n vault -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv get secret/<path>" 2>&1

# 2. If a key is missing, re-run the interactive setup and fill it in:
make secrets

# 3. If the namespace didn't exist at ExternalSecret-apply time, just wait
#    one refreshInterval (~60s) or force a resync:
kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite
```

**Verify**
```bash
kubectl get externalsecrets -A   # READY=True
kubectl get secret <target-secret-name> -n <namespace>   # exists with expected keys
```

**Prevent**
Never leave a secret-setup prompt blank if a downstream app depends on it —
`make secrets` (`scripts/secrets/setup-api-keys.sh`) is the only sanctioned
way to populate Vault; never hardcode secrets into Ansible files.

---

### Metrics-server unable to scrape kubelet (port 10250 blocked)

**Detect**
```bash
kubectl top nodes   # a node shows <unknown> for CPU/MEMORY
kubectl -n kube-system logs deploy/metrics-server --tail=50 | grep -i timeout
# "Failed to scrape node ... dial tcp <node-ip>:10250: i/o timeout"
```

**Root cause (this cluster)**
Hit for real: `metrics-server` happened to be scheduled on `rk1-control`
itself. Cross-node scrapes get Cilium-masqueraded to the sending node's LAN
IP (matches the UFW allow rule for `10.0.0.0/24`), but a pod scraping its
*own* node's kubelet is not masqueraded — it arrives at the host's `INPUT`
chain with the pod's real CIDR IP (`10.244.0.0/16`), which had no matching
UFW rule and silently dropped. This will recur on ANY node if
metrics-server (or anything else that self-scrapes its own node) ever gets
rescheduled there, unless the pod-CIDR rule below is in place.

**Remediation**
```bash
# Confirm the pod-CIDR UFW rule exists on the affected node:
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo ufw status verbose | grep 10.244"
# Should show: Anywhere ALLOW IN 10.244.0.0/16

# If missing (e.g. a node reinstalled before this fix was in the common role):
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo ufw allow from 10.244.0.0/16"
```

**Verify**
```bash
kubectl top nodes   # all nodes show real CPU/MEMORY, none <unknown>
kubectl -n kube-system logs deploy/metrics-server --tail=20   # no new timeout errors after a minute
```

**Prevent**
`ansible/roles/common/tasks/main.yml` now includes a permanent
`community.general.ufw` rule allowing the pod CIDR (`{{ pod_cidr }}`,
`10.244.0.0/16`) on every node — applied automatically by `make common` /
any fresh node bootstrap.

---

### fail2ban banning the Ansible controller IP

**Detect**
```bash
# Symptom: Ansible/SSH suddenly can't reach a node it could reach minutes ago
ssh -i $SSH_KEY ubuntu@<node-ip> true   # "Connection refused" or times out
# Confirm via BMC-reachable diagnostics if SSH is fully blocked, or check
# fail2ban's own ban list if you can still reach the node another way:
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo fail2ban-client status sshd"
```

**Root cause (this cluster)**
`ansible/roles/common`'s `jail.local` whitelists
`127.0.0.1/8 ::1 10.0.0.0/24` — any workstation connecting from within that
LAN subnet is safe. This only bites if the workstation running Ansible/SSH
is connecting from *outside* that range — e.g. over Tailscale (which uses
`100.x.x.x` addresses, not `10.0.0.0/24`), a different physical network, or
after repeated failed SSH attempts (wrong key, wrong user) from a
whitelisted-looking but actually-different source.

**Remediation**
```bash
# From a still-reachable path (BMC doesn't help here — this is an SSH-layer
# block, not power) — if you have ANY working SSH session to the node:
sudo fail2ban-client set sshd unbanip <your-ip>
# or, nuclear option if no session is available: power-cycle via BMC and
# reconnect within the boot window before fail2ban re-bans (only works if
# the ban was IP-specific and you're now connecting from LAN):
$TPI power off --node <slot>; sleep 5; $TPI power on --node <slot>
```

**Verify**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> true   # succeeds
```

**Prevent**
Always run Ansible/SSH commands against this cluster from a machine on
`10.0.0.0/24` (the LAN), not over Tailscale or any other remote path — the
whitelist is LAN-subnet-based by design specifically so the Ansible
controller is never at risk during normal operation.

---

## MEDIUM (action within 24 hours)

### Longhorn replica rebuilding

**Detect**
```bash
kubectl -n longhorn-system get replicas -o wide | grep -v running
kubectl -n longhorn-system get volumes   # ROBUSTNESS: degraded (not faulted)
```

**Root cause**
Expected, self-healing behavior — happens after a node reboot, a Longhorn
disk eviction, or any event that took a replica offline while
`numberOfReplicas` (2 on this cluster's volumes) still has at least one
healthy copy. Longhorn schedules a replacement replica and rebuilds it from
the healthy copy automatically.

**Remediation**
Usually none needed — just watch it. If it doesn't progress after ~15-20
minutes for a volume under 20-30GB (this cluster's typical PVC sizes), treat
it as CRITICAL: Longhorn volume Faulted/Degraded above and investigate the
`instance-manager` logs for the target node.

**Verify**
```bash
kubectl -n longhorn-system get volumes   # ROBUSTNESS back to healthy
```

**Prevent**
Nothing to prevent — this is normal Longhorn self-healing. Just don't
interrupt it (e.g. don't power off a node mid-rebuild).

---

### MetalLB IP pool >80% utilized

**Detect**
```bash
# Fast path:
make cluster-health   # reports "MetalLB pool X/Y IPs used"

# Manual:
kubectl get ipaddresspool -n metallb-system -o jsonpath='{.items[0].spec.addresses[0]}'
kubectl get svc -A | awk '$3=="LoadBalancer"' | wc -l
```

**Root cause (this cluster)**
Pool is `10.0.0.30-10.0.0.49` (20 IPs, `metallb_ip_range_cluster1` in
`vars.yml`). Each new `LoadBalancer`-type Service (ingress-nginx, Grafana,
Gitea, MinIO, Headlamp, Portainer, LiteLLM today — 7/20 used as of this
writing) consumes one. Growth comes from adding new exposed services (e.g.
future Prefect/JupyterHub UIs).

**Remediation**
```bash
# If genuinely approaching exhaustion, widen the pool in vars.yml:
#   metallb_ip_range_cluster1: "10.0.0.30-10.0.0.59"   # example
# 04-cluster-addons.yml has no task tags, so re-running it does everything
# (MetalLB, ingress-nginx, Prometheus/Grafana, Headlamp, Portainer) again —
# safe/idempotent, but if you'd rather patch just the pool directly:
kubectl -n metallb-system patch ipaddresspool cluster1-pool --type merge \
  -p '{"spec":{"addresses":["10.0.0.30-10.0.0.59"]}}'
# Also confirm the widened range doesn't collide with the DHCP pool
# (10.0.0.100-199) or other static assignments in CLAUDE.md's Network table.
```

**Verify**
```bash
kubectl get ipaddresspool -n metallb-system -o yaml   # new range applied
kubectl get svc -A | grep LoadBalancer   # all still have assigned EXTERNAL-IPs
```

**Prevent**
Check pool usage before deploying any new `LoadBalancer` service —
`make cluster-health` surfaces this automatically.

---

### Certificate warnings

**Detect**
```bash
# This cluster has no in-cluster cert-manager — TLS for public URLs
# terminates at Cloudflare's edge via the Tunnel, not in-cluster. "Certificate
# warnings" here most likely means a Cloudflare Tunnel/Access cert issue,
# not a Kubernetes Secret of type kubernetes.io/tls.
# Check the tunnel's own health first:
# (Cloudflare dashboard → Zero Trust → Tunnels → status)
kubectl -n cloudflare-tunnel get pods   # connector pods Running?
kubectl -n cloudflare-tunnel logs -l app=cloudflared --tail=50 | grep -i "cert\|tls"
```

**Root cause**
If a browser shows a certificate warning on any `*.kloud-worx.com` URL,
it's almost always a Cloudflare-side DNS/proxy issue (orange-cloud proxying
disabled, or a DNS record pointing somewhere unexpected) rather than
anything generated inside this cluster.

**Remediation**
```bash
# Confirm DNS records are still proxied through Cloudflare (orange cloud):
# check via the Cloudflare dashboard, or:
dig +short <service>.kloud-worx.com
# should resolve to a Cloudflare anycast IP, not a direct 10.0.0.x address

# Re-apply the DNS/tunnel config if records drifted:
ansible-playbook ansible/playbooks/11-cloudflare-tunnel.yml -i ansible/inventory/hosts.yml --tags dns
```

**Verify**
Browser loads the URL with a valid Cloudflare-issued certificate, no
warning.

**Prevent**
Don't manually edit DNS records for `kloud-worx.com` outside of the
`cloudflare-tunnel` role/playbook — it's the source of truth for all 10
hostnames and their Access policies.

---

### multipathd grabbing Longhorn iSCSI devices

**Detect**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo multipath -ll"
# Any entry with vendor string "IET" means multipathd has claimed a
# Longhorn virtual disk
ssh -i $SSH_KEY ubuntu@<node-ip> "systemctl is-active multipathd"
```

**Root cause (this cluster)**
No physical multipath storage exists in this homelab — `multipathd`,
if running, will grab Longhorn's iSCSI-backed virtual disks and lock them,
which previously broke `mke2fs` formatting for a fresh Longhorn PVC
(surfaced as Grafana's initial PVC failing to format with "is apparently in
use by the system").

**Remediation**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo systemctl stop multipathd; sudo systemctl disable multipathd; sudo systemctl mask multipathd"
```

**Verify**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo multipath -ll"   # empty
ssh -i $SSH_KEY ubuntu@<node-ip> "systemctl is-active multipathd"   # inactive
```

**Prevent**
`ansible/roles/common/tasks/main.yml` disables and masks `multipathd`
automatically on every node — this should only ever recur on a node that
bypassed the `common` role (e.g. manual OS work outside Ansible).

---

## LOW (monitor, no immediate action)

### High memory on RK1 nodes

**Detect**
```bash
kubectl top nodes
ssh -i $SSH_KEY ubuntu@<node-ip> "free -h"
```

**Root cause**
RK1 modules are 4-8GB boards running a full K3s node plus whatever's
scheduled there (Longhorn instance-managers, MinIO, Prometheus, etc. — all
memory-hungrier workloads). Some headroom pressure is expected, especially
on the two workers that host all Longhorn replica data.

**Remediation**
Only act if a node is genuinely under memory pressure (`kubectl describe
node <name> | grep MemoryPressure`) or pods are being OOMKilled
(`kubectl get pods -A | grep OOMKilled`). Otherwise just note it and check
trend over time via `kubectl top nodes` / Grafana.

**Verify**
`kubectl top nodes` memory usage trending back down or stable.

**Prevent**
Set resource `requests`/`limits` on any new workload you add (see the
Gitea Actions runner role for an example) so the scheduler can make
sane placement decisions instead of overcommitting a single node.

---

### Unused container image accumulation

**Detect**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo k3s crictl images | wc -l"
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo du -sh /var/lib/rancher/k3s/agent/containerd 2>/dev/null || sudo du -sh /var/lib/longhorn-nvme/rancher/k3s/agent/containerd"
```

**Root cause**
Every Helm upgrade/image bump leaves the previous image cached locally;
K3s's embedded containerd runs its own garbage collection on a threshold
but won't aggressively prune while disk pressure is low.

**Remediation**
```bash
# Manual prune if it's grown large:
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo k3s crictl rmi --prune"
```

**Verify**
```bash
ssh -i $SSH_KEY ubuntu@<node-ip> "sudo k3s crictl images | wc -l"   # count dropped
```

**Prevent**
Covered indirectly by the eMMC >80% monitoring above — since `/var/lib/
rancher` (which contains this image cache) now lives on NVMe on the
workers, this is much less pressing than it was before the eMMC reclaim
work; still worth an occasional check on rk1-control, which has no NVMe.

---

### DNSConfigForming nameserver truncation warning

**Detect**
```bash
kubectl get events -A --field-selector reason=DNSConfigForming
kubectl describe pod <affected-pod> -n <namespace> | grep -A3 DNSConfigForming
```

**Root cause**
A well-known, generic kubelet/CoreDNS warning — not specific to any
incident on this cluster. It fires when a pod's effective `/etc/resolv.conf`
would exceed the kernel's search-domain or nameserver-count limits (glibc
caps at 6 search domains / 3 nameservers), so kubelet truncates the list
and emits this warning. Usually harmless — DNS still resolves via the
entries that fit — but worth knowing about if a pod intermittently fails to
resolve a less-common hostname.

**Remediation**
Only act if you see actual DNS resolution failures correlated with this
warning. Reduce the pod's `dnsConfig.searches` list, or check the node's
own `/etc/resolv.conf` (`ssh ... "cat /etc/resolv.conf"`) for an
unexpectedly long search-domain list inherited from the router/DHCP.

**Verify**
Warning stops appearing in `kubectl get events`; DNS resolution for
previously-failing hostnames succeeds.

**Prevent**
Keep any custom `dnsConfig` on workloads minimal; this is a monitor-only
item otherwise.
