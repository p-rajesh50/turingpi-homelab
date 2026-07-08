# TuringPi Homelab — Session Handoff Document
# Date: July 8, 2026
# Use this to start a new Claude chat session with full context

---

## Project Overview

Building a fully automated multi-cluster homelab on TuringPi hardware.
GitHub: https://github.com/p-rajesh50/turingpi-homelab
Local repo: ~/projects/turingpi-homelab (WSL2 Ubuntu 24.04 on Windows 11, machine: parani-laptop)

---

## STATUS: FULL STACK LIVE AND VERIFIED END-TO-END

Every phase of the K3s+Cilium rebuild's build order is now complete and verified
live on the cluster — Cluster 1 is fully operational:

- ✅ K3s + Cilium cluster (3 nodes `Ready`, Cilium healthy)
- ✅ Storage (Longhorn NVMe-backed, NFS, MinIO)
- ✅ Cluster add-ons (MetalLB, ingress-nginx, Prometheus/Grafana, Headlamp, Portainer)
- ✅ Vault + External Secrets Operator
- ✅ Secrets populated in Vault (`make secrets`)
- ✅ AI stack (LiteLLM gateway — Qdrant/JupyterHub/LangGraph/Prefect/MCP servers
  remain stub roles, not yet implemented)
- ✅ Dev tools (Gitea + Actions runner)
- ✅ Tailscale — **control-plane only** (see below), key expiry disabled, subnet
  route approved in the admin console
- ✅ Cloudflare Tunnel — healthy, all 6 primary services live at kloud-worx.com,
  Google OAuth verified working

This is the first time the full stack has been live simultaneously since the
K3s+Cilium rebuild began.

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
  with other nodes. Contact TuringPi support for potential RMA.
- **rk1-worker-1 was physically moved from slot 3 to slot 2** to work around the fault.
- **Orin NX module was physically removed from the board** — Jetson Orin setup is
  deferred indefinitely until it's reinstalled somewhere.
- **NFS SATA SSD** re-homed via a mini-PCIe SATA adapter card in slot 2. Device
  path confirmed `/dev/sda2`.

---

## Network Layout

```
10.0.0.1          Router (Xfinity XB8 gateway)
10.0.0.10         Cluster 1 BMC (tpi1-bmc) — static IP configured
10.0.0.11         rk1-control (slot 1) — also Tailscale subnet router
10.0.0.12         rk1-worker-1 (slot 2, MOVED from slot 3)
10.0.0.13         rk1-worker-2 (slot 4)
10.0.0.14         orin-nx (removed from board, future re-add)
10.0.0.15         jetson-nano (future)
10.0.0.20         Cluster 2 BMC (future, CM4 cluster)
10.0.0.21-24      Cluster 2 CM4 nodes (future)
10.0.0.30         Ingress-NGINX
10.0.0.35         MinIO
10.0.0.36         Gitea
10.0.0.37         Grafana
10.0.0.38         Headlamp
10.0.0.39         Portainer
10.0.0.40         LiteLLM Gateway
10.0.0.30-49      MetalLB pool Cluster 1
10.0.0.50-69      MetalLB pool Cluster 2 (future)
10.0.0.100-199    DHCP pool (router managed)
```

---

## What Was Accomplished This Session (July 7-8, 2026)

This was a long session that took the cluster from "storage just deployed" all the
way through the complete build order. Highlights:

1. **Storage completed and verified**: Longhorn migrated to NVMe, NFS live,
   MinIO live. Found and fixed a stale kubeconfig bug (`ansible/roles/k3s-server`
   now copies the live K3s kubeconfig to the admin user's default path, fixing
   Helm/kubectl for every downstream role) and a Longhorn eMMC-vs-NVMe default
   disk issue.
2. **Full kubeadm-artifact cleanup pass**: swept the whole repo for leftover
   kubeadm/Flannel references from before the K3s migration — fixed a stale
   kubeconfig path in `11-cloudflare-tunnel.yml`, rewrote
   `scripts/maintenance/teardown.sh` to use K3s's own `k3s-uninstall.sh` instead
   of `kubeadm reset`, removed dangling `node_ips.orin_nx` references in
   `litellm`/`cloudflare-tunnel` roles, and synced `CLAUDE.md` to current state.
3. **`make addons`**: MetalLB, ingress-nginx, Prometheus/Grafana, Headlamp,
   Portainer all deployed. Found `multipathd` (no physical multipath storage in
   this homelab) was grabbing Longhorn's iSCSI-backed virtual disks and locking
   them — disabled+masked it in the `common` role.
4. **`make vault` + `make secrets`**: Vault + External Secrets Operator live,
   secrets populated (Anthropic/Gemini keys currently **placeholders** — see
   Follow-ups below).
5. **`make ai-stack`**: LiteLLM gateway live and verified (health endpoint
   responds `200`). Qdrant/JupyterHub/LangGraph/Prefect/MCP-servers remain
   empty stub roles by design — Ansible silently no-ops them.
6. **Grafana Vault secret wiring fixed**: no `ExternalSecret` existed for
   Grafana's admin password, so it was silently using the chart's default
   "changeme". Added the `ExternalSecret` (`ansible/roles/external-secrets`),
   wired Helm values to `existingSecret`, and along the way found + fixed a
   `RollingUpdate`-on-`ReadWriteOnce`-PVC deadlock (new pod scheduled to a
   different node than the old one, can't attach the volume, old pod never
   killed) — switched Grafana to `deploymentStrategy: Recreate`. Verified login
   works with the Vault-sourced password (had to also run Grafana's own
   `grafana cli admin reset-admin-password`, since changing the secret alone
   doesn't retroactively update an already-initialized Grafana database).
7. **`make dev-tools`**: Gitea + Actions runner live. This role's author had
   already anticipated the same RollingUpdate/RWO-PVC deadlock and set
   `strategy.type=Recreate` — no fix needed.
8. **Tailscale incident and fix**: `make tailscale` (originally targeting all 3
   nodes) caused a real production incident — advertising `10.0.0.0/24` from
   rk1-control combined with `--accept-routes` on the workers (already directly
   on that same subnet) hijacked their return-traffic routing. Plain LAN/SSH/
   kubelet-to-apiserver traffic broke on both workers while Tailscale's own
   tunnel kept working; rk1-worker-1 went `NotReady` and Grafana's pod had to
   reschedule. Root-caused, then **decided to run Tailscale on the control
   plane only**: `ansible/playbooks/10-tailscale.yml` now targets `k8s_control`
   instead of `rk1_nodes`, and Tailscale was fully `apt remove --purge`'d from
   both workers (iptables chains cleaned up too). Verified LAN connectivity,
   `kubectl get nodes`, and both web services recovered afterward. Also fixed a
   real bug along the way: `--snat-subnet-routes=false` was missing from
   rk1-control's advertised route (this was the root cause of LAN routing
   issues in the *previous* cluster build too). Key expiry has been disabled and
   the `10.0.0.0/24` subnet route approved in the Tailscale admin console.
9. **`make cloudflare`**: deployed in 3 checkpointed phases (added `tunnel`/
   `credentials`/`dns`/`access` task tags to the `cloudflare-tunnel` role to
   allow this, given the recent incident warranted extra caution) — connector
   pods live, DNS records provisioned for all 10 hostnames, Cloudflare Access +
   Google OAuth policies provisioned for 8 of them. **Verified**: tunnel shows
   "Healthy" in the dashboard, all 6 primary services
   (grafana/headlamp/portainer/gitea/litellm/minio.kloud-worx.com) load and
   redirect through Cloudflare Access, and Google OAuth login confirmed working
   on Grafana.

All of the above is committed and pushed to `origin/main`.

---

## Workstation Setup (parani-laptop)

```bash
# BMC credentials
source ~/.turingpi   # loads BMC_IP, BMC_USER, BMC_PASSWORD, BMC_TOKEN, TAILSCALE_AUTH_KEY

# Tools installed
tpi v1.0.7          # BMC control CLI
ansible 2.16.3      # automation
kubectl             # at ~/.kube/turingpi-cluster1.conf
cilium CLI          # installed at ~/bin/cilium (no sudo needed)

# SSH key for cluster
~/.ssh/turingpi_homelab

# Tailscale — control-plane only now
rk1-control: 100.96.0.102 (subnet router, advertises 10.0.0.0/24,
             --snat-subnet-routes=false)
# Workers do NOT run Tailscale — see "Key Learnings" below for why.

# Vault init file — back this up!
~/.vault-init.json
```

---

## Repository Structure

```
~/projects/turingpi-homelab/
├── CLAUDE.md                    ← Primary context file for Claude Code (kept current)
├── SESSION-HANDOFF.md           ← This file
├── Makefile                     ← All operations as make targets
├── ansible.cfg
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml            ← Node definitions
│   │   └── group_vars/all/vars.yml  ← All variables
│   ├── playbooks/
│   │   ├── 00-bootstrap.yml
│   │   ├── 01-common.yml        ← swap disable, fail2ban, multipathd disabled
│   │   ├── 02-kubernetes.yml    ← K3s server + agents
│   │   ├── 02b-cilium.yml       ← Cilium CNI install
│   │   ├── 03-storage.yml       ← Longhorn + NFS + MinIO — LIVE
│   │   ├── 03b-longhorn-nvme.yml ← Longhorn NVMe migration — LIVE
│   │   ├── 04-cluster-addons.yml ← MetalLB, Ingress, Grafana, Headlamp, Portainer — LIVE
│   │   ├── 05-ai-stack.yml      ← LiteLLM — LIVE (others are stub roles)
│   │   ├── 06-dev-tools.yml     ← Gitea — LIVE
│   │   ├── 07-jetson-orin.yml   ← Deferred (module removed from board)
│   │   ├── 08-jetson-nano.yml   ← Not yet run
│   │   ├── 09-vault.yml         ← Vault + ESO — LIVE
│   │   ├── 10-tailscale.yml     ← control-plane only — LIVE
│   │   └── 11-cloudflare-tunnel.yml ← LIVE, tagged for phased runs
│   └── roles/
│       ├── common/              ← swap disable, fail2ban, multipathd disabled
│       ├── k3s-server/          ← Live (copies kubeconfig to admin_user's ~/.kube/config)
│       ├── k3s-agent/           ← Live
│       ├── longhorn/            ← NVMe-backed on rk1-worker-1/2 — live
│       ├── nfs-server/          ← /dev/sda2 on rk1-worker-1 — live
│       ├── minio/               ← live
│       ├── litellm/              ← live
│       ├── vault/               ← live
│       ├── external-secrets/    ← live (includes grafana-admin-credentials)
│       ├── tailscale/           ← rk1-control only
│       ├── cloudflare-tunnel/   ← live, tagged tunnel/credentials/dns/access
│       └── gitea/               ← live
├── scripts/maintenance/
│   ├── health-check.sh
│   └── teardown.sh              ← K3s-native (k3s-uninstall.sh), not kubeadm
└── kubernetes/helm-values/prometheus-stack.yml  ← Grafana existingSecret + Recreate strategy
```

---

## Live Service URLs

```
https://vault.kloud-worx.com      HashiCorp Vault UI (Access-protected)
https://grafana.kloud-worx.com    Grafana monitoring (Access-protected, Google OAuth verified)
https://gitea.kloud-worx.com      Self-hosted Git (Access-protected)
https://litellm.kloud-worx.com    LiteLLM API gateway (Access-protected)
https://minio.kloud-worx.com      MinIO S3 console (Access-protected)
https://headlamp.kloud-worx.com   Headlamp K8s UI (Access-protected)
https://portainer.kloud-worx.com  Portainer multi-cluster UI (Access-protected)
https://prefect.kloud-worx.com    Prefect UI (Access-protected, not deployed yet)
https://jupyter.kloud-worx.com    JupyterHub (not deployed yet, no Access policy)
https://llm.kloud-worx.com        Open WebUI (deferred, Orin NX removed from board)
```

Local/direct (MetalLB, LAN only):
```
http://10.0.0.37      Grafana        http://10.0.0.36:3000  Gitea
http://10.0.0.38      Headlamp       http://10.0.0.39       Portainer
http://10.0.0.40/v1   LiteLLM        http://10.0.0.35       MinIO
```

---

## Follow-Up Items for Future Sessions

1. **Add real Anthropic and Gemini API keys to Vault** — `secret/llm-keys`
   currently holds placeholder values (added just to unblock LiteLLM's
   `ExternalSecret` sync during this session). Claude/Gemini model routes in
   LiteLLM won't actually authenticate until real keys replace them.
2. **eMMC space — rk1-worker-2 is urgent**: measured this session at **95% full**
   (29G total, 26G used, 1.5G available — worse than previously estimated).
   rk1-control is at 52%, rk1-worker-1 at 47%. Plan: move
   `/var/lib/rancher`/containerd storage to NVMe via symlinks on all 3 nodes,
   prioritizing rk1-worker-2 first given how close it is to actually running out
   of space (which would start failing pod scheduling/image pulls on that node).
3. **Deploy PostgreSQL for LiteLLM UI** — Bitnami Helm chart, Longhorn PVC.
   LiteLLM UI currently returns "not connected to DB" (spend tracking, user/team
   management unavailable without it). Tracked as item 8 in CLAUDE.md's Future
   Enhancements Backlog.
4. **Implement `cluster-lifecycle.sh`** — a graceful shutdown/startup script
   (doesn't exist yet — checked `scripts/maintenance/`, only `health-check.sh`
   and `teardown.sh` currently exist). Needed for safely power-cycling the whole
   cluster (e.g., before a house power outage) without leaving Longhorn
   volumes/etcd in a bad state.
5. **See `CLAUDE.md`'s Future Enhancements Backlog** for the full ranked list
   (ArgoCD, RK1 NPU device plugin, Loki, Flyte, Chroma, Nvidia device plugin +
   Jetson exporter, Local Coding Assistant, PostgreSQL for LiteLLM).

Not yet started (unchanged from before): Jetson Nano flash + config, Jetson Orin
NX (deferred, module removed from board), TrueNAS, Cluster 2 (CM4).

---

## Key Learnings / Things NOT to Repeat

1. **Swap issue — FIXED**: swap-disable lives in the `common` role as a systemd
   unit, survives power-cycles.
2. **Slot 3 is FAULTY**: Never put a node in slot 3. Use slots 1, 2, 4 only.
3. **Longhorn must use NVMe**: default path `/var/lib/longhorn` goes to eMMC
   (30GB, already tight — see Follow-ups). Configure `/var/lib/longhorn-nvme`.
4. **`multipathd` conflicts with Longhorn**: no physical multipath storage in
   this homelab — `multipathd` running will grab Longhorn's iSCSI-backed
   virtual disks (vendor string `IET`) and lock them, breaking volume
   formatting. Disabled+masked in the `common` role.
5. **`RollingUpdate` + single-replica + ReadWriteOnce PVC = deadlock risk**: if
   the new pod schedules to a different node than the old one, it can never
   attach the volume while the old pod (never killed under `RollingUpdate`)
   still holds it. Use `deploymentStrategy: Recreate` for any single-replica
   workload on an RWO Longhorn PVC (Grafana and Gitea both need/have this).
6. **Changing a Helm `existingSecret` password doesn't retroactively change an
   already-initialized app's own database** (Grafana specifically) — the env
   var only applies on a fresh DB bootstrap. Use the app's own admin-reset
   mechanism (`grafana cli admin reset-admin-password`) after wiring up a new
   secret if the app was already running.
7. **Tailscale subnet routing + `--accept-routes` on nodes already on that same
   LAN subnet is dangerous**: advertising a subnet that tailnet peers are
   already directly, natively connected to can hijack their return-traffic
   routing for that subnet, breaking plain LAN/SSH/kubelet connectivity while
   Tailscale's own tunnel keeps working (misleadingly looks "up"). This is why
   Tailscale now runs on rk1-control only, not the workers. If Tailscale is
   ever needed on workers again, this conflict must be solved first (e.g. by
   not overlapping the advertised subnet, or running workers in a genuinely
   separate subnet).
8. **Ansible facts (`set_fact`/`register`) don't survive across separate
   `ansible-playbook` process invocations** — only within one run.
9. **Tearing down an old cluster is not automatic**: rewriting playbooks for a
   new stack doesn't touch already-running state on the hardware.
   `scripts/maintenance/teardown.sh` is now K3s-native (uses K3s's own
   `k3s-uninstall.sh`/`k3s-agent-uninstall.sh`), not kubeadm.
10. **Deploy incrementally, checkpoint after incidents**: after the Tailscale
    incident, `make cloudflare` was deliberately run in 3 tagged phases
    (tunnel/DNS/Access) with a report after each, rather than one shot. Worth
    doing for any future change to shared network/routing configuration.
11. **CLAUDE.md**: always kept current at the end of each session.

---

## Storage Devices

| Node | Device | Size | Type | Use |
|---|---|---|---|---|
| rk1-control | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn |
| rk1-control | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS — 52% used |
| rk1-worker-1 | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn |
| rk1-worker-1 | /dev/sda2 | 476.4GB | SATA (mini-PCIe adapter) | NFS export |
| rk1-worker-1 | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS — 47% used |
| rk1-worker-2 | /dev/nvme0n1 | 931.5GB | NVMe | Longhorn |
| rk1-worker-2 | /dev/sda | 57.8GB | USB | Ignore for now |
| rk1-worker-2 | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS — **95% used, urgent** |

NFS export path: /mnt/sata/k8s (on rk1-worker-1 at 10.0.0.12)

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

Current state: the full stack is live and verified end-to-end (K3s+Cilium,
storage, addons, Vault/secrets, AI stack, dev tools, Tailscale control-plane-only,
Cloudflare Tunnel with Google OAuth). See "Follow-Up Items for Future Sessions"
above for what's next — eMMC space on rk1-worker-2 (95% full) is the most urgent.
```
