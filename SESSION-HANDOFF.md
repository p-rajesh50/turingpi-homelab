# TuringPi Homelab — Session Handoff Document
# Date: July 7, 2026
# Use this to start a new Claude chat session with full context

---

## Project Overview

Building a fully automated multi-cluster homelab on TuringPi hardware.
GitHub: https://github.com/p-rajesh50/turingpi-homelab
Local repo: ~/projects/turingpi-homelab (WSL2 Ubuntu 24.04 on Windows 11, machine: parani-laptop)

---

## Hardware — Cluster 1 (TuringPi 2.5)

| Device | Hostname | IP | Slot | Status |
|---|---|---|---|---|
| BMC | tpi1-bmc | 10.0.0.10 | — | ✅ Static IP, password changed |
| RK1 | rk1-control | 10.0.0.11 | 1 | ✅ K3s control-plane, Ready |
| RK1 | rk1-worker-1 | 10.0.0.12 | 2 | ✅ K3s agent, Ready (MOVED from slot 3) |
| EMPTY | — | — | 3 | ❌ FAULTY DSA switch port — never use |
| RK1 | rk1-worker-2 | 10.0.0.13 | 4 | ✅ K3s agent, Ready |
| Orin NX | orin-nx | 10.0.0.14 | — | ⬜ Removed from board entirely, deferred indefinitely |
| Jetson Nano | jetson-nano | 10.0.0.15 | — | ⬜ Not yet configured |

### CRITICAL HARDWARE NOTES:
- **Slot 3 DSA switch port is FAULTY** — nodes in slot 3 cannot communicate
  with other nodes. Diagnosed via systematic elimination of all software causes.
  ARP works but all unicast IP traffic from slot 3 is dropped by the internal switch.
  Contact TuringPi support for potential RMA.
- **rk1-worker-1 was physically moved from slot 3 to slot 2** to work around the fault.
- **Orin NX module was physically removed from the board** — Jetson Orin setup is
  deferred indefinitely until it's reinstalled somewhere.
- **NFS SATA SSD** (previously wired to slot 3's carrierboard SATA port) is now
  re-homed via a mini-PCIe SATA adapter card in slot 2. **Device path confirmed**
  (`lsblk`/`fdisk -l` on rk1-worker-1) — still `/dev/sda2`, no `vars.yml`/`hosts.yml`
  changes needed.

---

## Network Layout

```
10.0.0.1          Router (Xfinity XB8 gateway)
10.0.0.10         Cluster 1 BMC (tpi1-bmc) — static IP configured
10.0.0.11         rk1-control (slot 1)
10.0.0.12         rk1-worker-1 (slot 2, MOVED from slot 3)
10.0.0.13         rk1-worker-2 (slot 4)
10.0.0.14         orin-nx (removed from board, future re-add)
10.0.0.15         jetson-nano (future)
10.0.0.20         Cluster 2 BMC (future, CM4 cluster)
10.0.0.21-24      Cluster 2 CM4 nodes (future)
10.0.0.30-49      MetalLB pool Cluster 1
10.0.0.50-69      MetalLB pool Cluster 2 (future)
10.0.0.100-199    DHCP pool (router managed)
```

---

## Current Cluster State (as of session end, July 7 2026)

### K3s + CILIUM CLUSTER IS LIVE AND VERIFIED HEALTHY

```
NAME           STATUS   ROLES                  VERSION
rk1-control    Ready    control-plane,master   v1.30.5+k3s1
rk1-worker-1   Ready    <none>                 v1.30.5+k3s1
rk1-worker-2   Ready    <none>                 v1.30.5+k3s1
```

- Cilium: `OK` (agent/operator/envoy all 3/3), CoreDNS/local-path-provisioner/metrics-server
  all `Running`.
- Cross-node pod-to-pod connectivity directly verified (test pods pinned to different
  nodes, 0% packet loss).
- kubeconfig at `~/.kube/turingpi-cluster1.conf`, server IP correctly points to
  `10.0.0.11:6443` (not `127.0.0.1`).
- Swap disabled permanently via systemd unit on all 3 nodes (`disable-swap.service`,
  in the `common` role) — verified `swapon --show` empty and `disable-swap` active
  across a full BMC power-cycle of all 3 nodes.
- fail2ban on all 3 nodes now whitelists `10.0.0.0/24` (`ignoreip`) so the Ansible
  controller can never self-ban again.

### This is a FULL REBUILD from the previous kubeadm+Flannel cluster
All application data from the prior cluster (Vault secrets, Gitea repos, Longhorn
volumes, MinIO buckets) was wiped as part of this rebuild — this was an accepted
tradeoff, not an accident. Everything from `make storage` onward needs to be
re-deployed and re-populated (see "Next Steps" below).

---

## What Was Accomplished This Session (July 7 2026)

1. **Fixed a real bootstrap bug**: the Netplan template used `ansible_host` (the
   connection variable) for the static IP, so overriding `ansible_host` to reach a
   node still on DHCP during initial bootstrap also corrupted the static IP written
   to disk. Added a dedicated `node_static_ip` inventory variable, decoupled from
   `ansible_host`, and fixed the template.
2. **Moved swap-disable into the `common` role** as a permanent systemd unit
   (`disable-swap.service`) — previously it was a one-shot task only in the
   Kubernetes playbook, so `make common` alone never actually disabled swap, and
   nothing guaranteed it stayed off across reboots. Verified across a full power-cycle
   of all 3 nodes.
3. **Whitelisted the LAN in fail2ban** (`ignoreip = 127.0.0.1/8 ::1 10.0.0.0/24`) after
   fail2ban banned the Ansible controller mid-run (triggered by stale failed-auth log
   entries from an earlier manual bootstrap workaround) — and that ban **persisted
   across a BMC power-cycle** because fail2ban's ban database lives on disk.
4. **Tore down the old, still-running kubeadm cluster** on rk1-control and
   rk1-worker-2 (kube-apiserver was still bound to :6443, kubelet still active,
   MetalLB/CoreDNS/Flannel pods still running) via `scripts/maintenance/teardown.sh`
   — this had never actually been run; only the Ansible playbooks had been rewritten
   for K3s. rk1-worker-1 had nothing to tear down (its module was freshly reflashed
   when moved to slot 2, no old kubeadm state).
5. **Found and removed stale `flannel.1`/`cni0` interfaces** left behind by
   `kubeadm reset` (which explicitly doesn't clean up CNI interfaces) — these were
   squatting on VXLAN's UDP 8472 port on rk1-control and rk1-worker-2, silently
   breaking Cilium's own VXLAN device on those two nodes only (rk1-worker-1, with no
   Flannel history, worked fine immediately). This is exactly the interface-cleanup
   step `teardown.sh` documents but never reached in step 4 (it aborts early since
   rk1-worker-1 legitimately has no kubeadm binary).
6. **Fixed the K3s+Cilium Ansible code itself** (bugs surfaced by this being the
   first real deployment run):
   - `Makefile`'s `k3s-agents` target referenced a non-existent `rk1_workers`
     inventory group (the real group is `k8s_workers`).
   - The node-token handoff from `k3s-server` to `k3s-agent` relied on an Ansible
     fact set via `delegate_facts` — but `make kubernetes` runs `k3s-server` and
     `k3s-agents` as **separate `ansible-playbook` processes**, and facts don't
     persist across processes. Fixed by having `k3s-agent` fetch the token directly
     from rk1-control itself (`delegate_to` + `slurp`).
   - Cilium CLI install used `sudo` targeting `/usr/local/bin`, but there's no
     passwordless sudo on the workstation — switched to installing into `~/bin`
     (already on PATH, user-writable).
   - `cilium status --wait` was called with an invalid `timeout` parameter on the
     `command` module — fixed to use Cilium's own `--wait-duration` flag.
7. Deployed a throwaway `cilium connectivity test` to validate the fix, found a
   leftover `CiliumNetworkPolicy` from killing that test mid-run (5-minute timeout)
   was blocking traffic — cleaned up the test namespaces, then verified connectivity
   cleanly with minimal ad hoc pods instead.

All of the above is committed to `main` (not yet pushed — see below).

---

## Workstation Setup (parani-laptop)

```bash
# BMC credentials
source ~/.turingpi  # loads BMC_IP, BMC_USER, BMC_PASSWORD, BMC_TOKEN, TAILSCALE_AUTH_KEY

# Tools installed
tpi v1.0.7          # BMC control CLI
ansible 2.16.3      # automation
kubectl             # at ~/.kube/turingpi-cluster1.conf
cilium CLI          # installed at ~/bin/cilium (no sudo needed)

# SSH key for cluster
~/.ssh/turingpi_homelab

# Tailscale IPs (stale — Tailscale not yet redeployed on the new cluster)
rk1-control:  100.96.0.102 (pre-rebuild, will change on redeploy)
rk1-worker-1: 100.81.77.8  (pre-rebuild, will change on redeploy)
rk1-worker-2: 100.111.182.46 (pre-rebuild, will change on redeploy)

# Vault init file — STALE, from the destroyed cluster. A new one will be
# generated by `make vault` and must be freshly backed up.
~/.vault-init.json
```

---

## Repository Structure

```
~/projects/turingpi-homelab/
├── CLAUDE.md                    ← Primary context file for Claude Code (kept current)
├── SESSION-HANDOFF.md           ← This file
├── Makefile                     ← All operations as make targets (k3s-server/k3s-agents/cilium added)
├── ansible.cfg
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml            ← Node definitions (slot 2 for worker-1, node_static_ip added)
│   │   └── group_vars/all/vars.yml  ← All variables (k3s_version, k3s_server_ip)
│   ├── playbooks/
│   │   ├── 00-bootstrap.yml     ← Fixed: node_static_ip vs ansible_host
│   │   ├── 01-common.yml        ← Includes permanent swap disable + fail2ban ignoreip
│   │   ├── 02-kubernetes.yml    ← K3s server + agent plays (kubeadm removed)
│   │   ├── 02b-cilium.yml       ← NEW — Cilium CNI install
│   │   ├── 03-storage.yml       ← Longhorn + NFS + MinIO — LIVE, verified healthy
│   │   ├── 03b-longhorn-nvme.yml ← Longhorn NVMe migration — LIVE, verified healthy
│   │   ├── 04-cluster-addons.yml ← MetalLB, Ingress, Grafana, Headlamp, Portainer — NEXT STEP
│   │   ├── 05-ai-stack.yml      ← LiteLLM etc. (needs re-deploy, data wiped)
│   │   ├── 06-dev-tools.yml     ← Gitea (needs re-deploy, data wiped)
│   │   ├── 07-jetson-orin.yml   ← Deferred (module removed from board)
│   │   ├── 08-jetson-nano.yml
│   │   ├── 09-vault.yml         ← Needs re-deploy + re-init + re-unseal
│   │   ├── 10-tailscale.yml     ← Needs re-deploy
│   │   └── 11-cloudflare-tunnel.yml ← Needs re-deploy
│   └── roles/
│       ├── common/              ← disable-swap systemd service + fail2ban ignoreip
│       ├── k3s-server/          ← Live, verified working
│       ├── k3s-agent/           ← Live, verified working (token fetched via delegate_to)
│       ├── longhorn/            ← NVMe-backed on rk1-worker-1/2 — live, verified
│       ├── nfs-server/          ← /dev/sda2 on rk1-worker-1 — live, verified
│       ├── minio/               ← live, verified (NVMe-backed PVC, pod Running)
│       ├── litellm/             ← Needs re-deploy
│       ├── vault/               ← Needs re-deploy
│       ├── external-secrets/
│       ├── tailscale/
│       ├── cloudflare-tunnel/
│       └── gitea/               ← Needs re-deploy
```

---

## Pre-Rebuild Deployment State (HISTORICAL — all data wiped, needs re-deployment)

These were working before the rebuild. All underlying data (Vault secrets, Gitea
repos, Longhorn volumes, MinIO buckets) was wiped as part of the K3s migration.
Once `make storage` → `make addons` → `make vault` → `make secrets` → etc. are
re-run, these will need to be reconfigured (IPs below are the previous MetalLB
allocations and may be reused, but nothing currently exists at them):

| Service | Previous IP | Notes |
|---|---|---|
| MetalLB | pool 10.0.0.30-49 | Needs re-deploy via `make addons` |
| Ingress-NGINX | 10.0.0.30 | Needs re-deploy |
| Grafana | 10.0.0.37 | Needs re-deploy |
| Headlamp | 10.0.0.38 | Needs re-deploy |
| Portainer | 10.0.0.39 | Needs re-deploy |
| LiteLLM | 10.0.0.40 | Needs re-deploy |
| MinIO | 10.0.0.35 | Needs re-deploy via `make storage` |
| Gitea | 10.0.0.36 | Needs re-deploy via `make dev-tools` |
| Vault | in-cluster | Needs re-deploy + re-init + re-unseal via `make vault` |
| Cloudflare Tunnel | — | Needs re-deploy via `make cloudflare` |
| Tailscale | — | Needs re-deploy via `make tailscale` |

### Secrets that will need to be re-entered into the new Vault (`make secrets`):
- secret/llm-keys: ANTHROPIC_API_KEY, GEMINI_API_KEY, LITELLM_MASTER_KEY
- secret/minio: rootUser, rootPassword
- secret/postgres: POSTGRES_USER, POSTGRES_PASSWORD
- secret/tailscale: AUTH_KEY
- secret/cloudflare: TUNNEL_TOKEN, API_TOKEN, ZONE_ID, ACCOUNT_ID
- secret/gitea: GITEA_ADMIN_USER, GITEA_ADMIN_PASSWORD, GITEA_ADMIN_EMAIL
- secret/grafana: ADMIN_PASSWORD

### Cloudflare Setup (reference, tunnel will need recreating):
- Domain: kloud-worx.com (on Cloudflare, nameservers from GoDaddy)
- Team domain: rapid-tooth-42c2.cloudflareaccess.com
- Google IdP configured for Access policies
- Allowed email: rajesh.pamulapati@gmail.com

---

## STORAGE IS LIVE AND VERIFIED HEALTHY (July 7 2026, later session)

`make storage` and `make longhorn-nvme` have both been run successfully:

- **NFS**: live on rk1-worker-1 (`/dev/sda2` → `/mnt/sata/k8s`), export mounted.
- **Longhorn**: NVMe-backed on rk1-worker-1 + rk1-worker-2 (`/var/lib/longhorn-nvme`),
  default StorageClass. rk1-control's eMMC disk is intentionally not used for
  scheduling (matches the Storage Architecture table below).
- **MinIO**: `1/1 Running`, both replicas on NVMe, LoadBalancer IP `10.0.0.35`.
- **StorageClasses**: `longhorn` (default, replicated) and `nfs-shared` (SATA,
  shared) both present and working.

### Two real bugs found and fixed this pass:

1. **Stale kubeconfig on rk1-control** (`/home/ubuntu/.kube/config`) was left over
   from the pre-rebuild kubeadm cluster (different CA) — nothing in the K3s rebuild
   ever recreated it, but `longhorn`/`minio`/`vault`/`gitea`/`litellm`/
   `external-secrets`/`cloudflare-tunnel`/addons roles all point Helm/kubectl at
   exactly that path. Caused `helm upgrade --install longhorn ...` to fail with
   `x509: certificate signed by unknown authority`. **Fixed** in
   `ansible/roles/k3s-server/tasks/main.yml`: added a task that copies the live
   `/etc/rancher/k3s/k3s.yaml` to `/home/{{ admin_user }}/.kube/config` on
   rk1-control right after the K3s server installs. This fixes every downstream role
   that reads that path, not just longhorn — re-ran `make kubernetes --tags
   k3s-server` once to lay down the fresh file before retrying `make storage`.
2. **Longhorn defaulted to the eMMC disk** (`/var/lib/longhorn`, ~30GB) on initial
   install, which is far too small for MinIO's 200Gi PVC — its engine/replicas never
   attached ("volume is not ready for workloads"). This is the known, already-planned
   Step 7b (`make longhorn-nvme` / `03b-longhorn-nvme.yml`), which migrates Longhorn
   to the NVMe disks and reinstalls MinIO. First run of it hung on the eviction-poll
   step because an ad hoc `test-longhorn-pvc` (created for verification) had a
   replica pinned to rk1-control's eMMC disk, which that playbook intentionally never
   touches (NVMe Longhorn is worker-only by design). Deleted the test PVC and re-ran
   — completed cleanly in ~90s.

### NEXT STEP: `make addons`

Continue in order: `make addons` (MetalLB, ingress-nginx, Prometheus, Grafana,
Dashboard) → `make vault` → `make secrets` → `make ai-stack` → `make dev-tools` →
`make tailscale` → `make cloudflare`.

---

## Key Learnings / Things NOT to Repeat

1. **Swap issue — FIXED**: swap-disable now lives in the `common` role as a
   systemd unit, verified to survive a full power-cycle on all 3 nodes.

2. **Slot 3 is FAULTY**: Never put a node in slot 3. Use slots 1, 2, 4 only.

3. **Longhorn must use NVMe**: Default path /var/lib/longhorn goes to eMMC (30GB).
   Must configure to use /var/lib/longhorn-nvme on /dev/nvme0n1.

4. **`node_static_ip` vs `ansible_host` — FIXED**: Netplan now renders from a
   dedicated `node_static_ip` var, not the connection-time `ansible_host`, so
   bootstrapping a node still on DHCP (`-e ansible_host=<dhcp-ip>`) can't corrupt
   its assigned static IP anymore.

5. **fail2ban can self-ban the Ansible controller — FIXED**: `ignoreip` now covers
   the whole LAN subnet on all 3 nodes. Remember: fail2ban bans persist across
   reboots (its ban database is on disk) — a power-cycle does NOT clear a ban.

6. **Tearing down an old cluster is not automatic**: rewriting Ansible playbooks for
   a new stack (K3s) does NOT touch already-running state on the actual hardware.
   `scripts/maintenance/teardown.sh` must be run explicitly, and its interface
   cleanup step (`ip link delete flannel.1/cni0`) matters — leftover Flannel VXLAN
   interfaces silently break a new CNI's own VXLAN by squatting on UDP 8472.

7. **Ansible facts set via `delegate_facts` don't survive across separate
   `ansible-playbook` process invocations** — only within one run. If a Makefile
   target splits a playbook into multiple `--limit`-scoped invocations (as
   `k3s-server`/`k3s-agents` do), any cross-host fact sharing needs to happen via a
   live fetch (`delegate_to` + `slurp`), not a fact set in an earlier process.

8. **Deploy incrementally**: Verify cluster stability after EACH phase before
   proceeding. Power cycle nodes to verify recovery before adding services.

9. **K3s vs kubeadm**: K3s is TuringPi's recommended stack. More stable on ARM64,
   less memory overhead, simpler recovery, built-in swap tolerance.

10. **Cilium vs Flannel**: Cilium is more stable on ARM64 RK1 nodes than Flannel and
    supports Network Policies. Verified working with real cross-node connectivity.

11. **CLAUDE.md**: Always update CLAUDE.md at the end of each session so
    Claude Code has accurate context for the next session.

---

## Storage Devices (confirmed, except where flagged)

| Node | Device | Size | Type | Use |
|---|---|---|---|---|
| rk1-control | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn |
| rk1-control | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS only |
| rk1-worker-1 | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn |
| rk1-worker-1 | /dev/sda2 (confirmed) | 476.4GB | SATA partition via mini-PCIe adapter | NFS export |
| rk1-worker-2 | /dev/nvme0n1 | 931.5GB | NVMe | Longhorn |
| rk1-worker-2 | /dev/sda | 57.8GB | USB | Ignore for now |

NFS export path: /mnt/sata/k8s (on rk1-worker-1 at 10.0.0.12) — device path confirmed

---

## Future Cluster 2 (CM4) — Not Started

```
cluster2/ansible/ exists in repo with basic structure
BMC: tpi2-bmc at 10.0.0.20 (not yet configured)
Nodes: cm4-node-1 through cm4-node-4 at 10.0.0.21-24
Plan: Pi-hole (primary 10.0.0.21, secondary 10.0.0.22),
      dev sandbox, databases, GraphQL, CI/CD learning
```

---

## TrueNAS — Not Started

```
FreeBSD (TrueNAS Core), planned at 10.0.0.5
Media: SMB + NFS + Jellyfin
Backup target for Longhorn
Not started yet — after CM4 cluster
```

---

## Standalone Jetson Nano — Not Started

```
10.0.0.15
Role: Embedding server (nomic-embed-text, all-minilm)
Small model experimentation (phi3:mini, tinyllama)
JetPack 4.6 — manual SDK Manager flash required
LiteLLM already configured to route to it
```

---

## Recommended Starting Prompt for New Session

```
I am continuing a TuringPi homelab build project.
Please read the SESSION-HANDOFF.md file I am about
to paste for full context, then help me continue
from where we left off.

[paste this entire document]

Current immediate task: the K3s+Cilium cluster is live and verified
healthy on all 3 nodes. The NFS SATA device path on rk1-worker-1 is
confirmed (/dev/sda2, no vars.yml changes needed). Next step is
`make storage` (Longhorn + NFS + MinIO), then verify it's healthy
before proceeding further.
```
