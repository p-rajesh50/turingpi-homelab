# TuringPi Homelab — Claude Code Context

This file provides context for Claude Code to understand the project,
current state, and how to continue the build. Read this before executing
any commands or making any changes. This is a snapshot of **current
state** — for dated history of how things got here (incidents, decisions,
investigations), see `SESSION-HANDOFF.md`.

*Last verified against live cluster + Vault state: 2026-08-30.*

---

## Project Overview

A fully automated multi-cluster homelab built on TuringPi hardware,
managed through Ansible, with Kubernetes, local LLM inference, AI gateway,
agentic app runtime, secrets management, and remote access.

**GitHub:** https://github.com/p-rajesh50/turingpi-homelab
**Local path:** ~/projects/turingpi-homelab
**Workstation:** WSL2 Ubuntu 24.04 on Windows 11

---

## Hardware

### Cluster 1 — TuringPi 2.5 (PRIMARY — fully live)

| Device | Hostname | IP | Slot | Status |
|---|---|---|---|---|
| BMC | tpi1-bmc | 10.0.0.10 | — | ✅ Static IP configured |
| RK1 | rk1-control | 10.0.0.11 | 1 | ✅ K3s control-plane, Ready |
| RK1 | rk1-worker-1 | 10.0.0.12 | 2 | ✅ K3s agent, Ready (moved from slot 3 after hardware fault; NFS SATA SSD re-homed via mini-PCIe adapter, device path confirmed `/dev/sda2`) |
| RK1 | rk1-worker-2 | 10.0.0.13 | 4 | ✅ K3s agent, Ready |
| — | (slot 3) | — | 3 | ⛔ EMPTY for K3s purposes — RK1 NIC/switch-silicon fault, never assign an RK1 node here. **Physically occupied by the standalone Orin NX** (see below), which doesn't use this fabric. |

### Standalone nodes (not part of K3s)

| Device | Hostname | IP | Status |
|---|---|---|---|
| Orin NX | orin-nx | 10.0.0.14 | ✅ Physically installed in Slot 3 (tried Slot 1, then 2, before settling here). Runs standalone, `jetson_llm` inventory group, `llama-server` (llama.cpp, CUDA). Currently active: `gemma4-12b`; `qwen3-8b` installed but not started (hedge). |
| Jetson Orin Nano | orin-nano | 10.0.0.50 | ✅ Standalone, `jetson_llm` inventory group, `llama-server`. Currently active: `gemma4-e2b` (promoted 2026-08-27 over `qwen3.5-4b`/`gemma4-e4b` per the tool-calling harness comparison — see `tools/tool-calling-harness/results/SUMMARY.md`); both alternates installed but not started. |

**Note**: there is no "Jetson Nano" device — a device once planned for 10.0.0.15 was upgraded to a Super Developer Kit and reassigned as `orin-nano` (10.0.0.50) before ever being deployed at the old IP. 10.0.0.15 was never used in the live topology; the `jetson_nano` inventory group was removed 2026-08-30. The `jetson_orin` inventory group (for the original in-cluster Ollama/Open-WebUI plan, `07-jetson-orin.yml`) is kept empty/reserved — that plan was superseded by the standalone `jetson_llm`/llama.cpp approach above.

### Cluster 2 — TuringPi 2 + CM4

| Device | Hostname | IP |
|---|---|---|
| BMC | tpi2-bmc | 10.0.0.20 |
| CM4 Node 1 | cm4-node-1 | 10.0.0.21 |
| CM4 Node 2 | cm4-node-2 | 10.0.0.22 |
| CM4 Node 3 | cm4-node-3 | 10.0.0.23 |
| CM4 Node 4 | cm4-node-4 | 10.0.0.24 |

**Status**: all 4 nodes flashed, reachable, and stable (survived a full power-cycle test). K3s bring-up is **code-complete** (forked `k3s-server-cm4`/`k3s-agent-cm4` roles, isolated `cm4_nodes`/`cluster2` inventory groups, playbooks `20-22-cluster2-*.yml`) but **not yet run against the live nodes** — no live K3s cluster exists here yet. Known gap once run: no UFW/fail2ban/chrony hardening forked in yet (only swap-disable).

### TrueNAS

| Device | Hostname | IP | Status |
|---|---|---|---|
| TrueNAS Core (FreeBSD) | truenas | 10.0.0.5 (static, confirmed) | ✅ Admin UI accessible at https://truenas.kloud-worx.com via Cloudflare Tunnel. Longhorn backup target configured (NFSv3 forced). SMB/NFS media exports not yet configured. |

---

## Network

```
10.0.0.1          Router / gateway
10.0.0.5          TrueNAS (static, confirmed) — https://truenas.kloud-worx.com via Cloudflare Tunnel
10.0.0.10         Cluster 1 BMC (tpi1-bmc)
10.0.0.11         rk1-control  (slot 1)
10.0.0.12         rk1-worker-1 (slot 2, moved from slot 3) — also NFS server (mini-PCIe SATA adapter, path confirmed /dev/sda2)
10.0.0.13         rk1-worker-2 (slot 4)
                  slot 3 — EMPTY for K3s, physically occupied by standalone orin-nx (see Hardware)
10.0.0.14         orin-nx      (standalone, jetson_llm group, llama.cpp)
10.0.0.20-24      Cluster 2 (code-complete, not yet live — see Hardware)
10.0.0.30-49      MetalLB LoadBalancer pool (Cluster 1)
10.0.0.50         orin-nano    (standalone, jetson_llm group, llama.cpp)
10.0.0.50-69      MetalLB LoadBalancer pool (Cluster 2, future) — ⚠️ CONFLICT: orin-nano's IP sits at the start of this range; re-check before Cluster 2's MetalLB pool is actually provisioned.
10.0.0.100-199    DHCP pool (router managed)
```

---

## Current State Summary

**Cluster 1 is fully live and has been for some time** — confirmed via
live `kubectl get pods -A` (2026-08-30): K3s+Cilium (3 nodes `Ready`),
Longhorn+NFS+MinIO storage, MetalLB+ingress-nginx, Prometheus+Grafana+
Alertmanager (namespace `monitoring`), Headlamp, Portainer, Vault+External
Secrets Operator, Gitea+Actions runners+package-cleanup CronJob, LiteLLM+
PostgreSQL, Cloudflare Tunnel — all running, pod ages ranging 6-53 days.
Two client apps are also live via Gitea CI/CD: `research-forum-app` and
`rf-pre-event-app` (their own namespaces).

**Phase 0/1 (standalone llama.cpp on orin-nx/orin-nano)** is also live —
see the Hardware table above and `ansible/roles/llama-cpp-jetson/README.md`
for the full model/port/systemd-unit reference, and
`tools/tool-calling-harness/` for the comparison harness that picked the
current default models.

**LiteLLM model_list** (`ansible/roles/litellm/tasks/main.yml`, live as of
2026-08-30): `claude-sonnet` (`anthropic/claude-sonnet-5`), `claude-haiku`
(`anthropic/claude-haiku-4-5`), `gpt-4.1-mini` (Azure Foundry),
`orin-nx-gemma4-12b`, `orin-nano-gemma4-e2b`. There are no Ollama-backed
routes anymore — the previous `all-minilm`/`phi3-mini` entries (pointed at
the nonexistent Jetson Nano) were removed 2026-08-30. **`claude-opus`,
`gemini-pro`, and `gemini-flash` were also removed 2026-08-30**:
`claude-opus` to prevent accidental high-cost usage against a small fixed
Anthropic credit ($20) with no per-model spend guard yet; `gemini-pro`/
`gemini-flash` because `GEMINI_API_KEY` is still a placeholder (superseded
by the Azure Foundry work this session) and both would fail if selected
regardless. `ANTHROPIC_API_KEY` and `AZURE_FOUNDRY_API_KEY`/
`AZURE_FOUNDRY_API_BASE` are real (confirmed live in Vault);
`GEMINI_API_KEY` remains an unused placeholder — re-add Gemini routes once
it's replaced via `make secrets`.

**Open WebUI is NOT deployed anywhere** — confirmed live, no such
workload exists in any namespace. `llm.kloud-worx.com` has no backing
service; do not present it as live in any doc.

**Not yet done**: Cluster 2 live bring-up (code exists, not run), TrueNAS
SMB/NFS media exports, Whisper speech-to-text, LiteLLM teams/budgets for
the client FinOps demo, benchmarking Phase 1 inference throughput/latency
(the harness measured correctness, not speed).

Full session-by-session detail (incidents, root causes, investigations,
verification steps) lives in `SESSION-HANDOFF.md` — treat that file as
the authoritative running log and this section as a current-state
summary only.

---

## Repository Structure

```
turingpi-homelab/
├── CLAUDE.md                              ← YOU ARE HERE
├── README.md                              ← public-facing repo overview / quick start
├── SESSION-HANDOFF.md                     ← dated chronological session log
├── Makefile                               ← all operations as make targets
├── ansible.cfg                            ← Ansible config
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml                      ← node definitions and IPs
│   │   └── group_vars/
│   │       └── all/
│   │           └── vars.yml               ← ALL variables live here
│   ├── playbooks/
│   │   ├── 00-bootstrap.yml               ← make bootstrap
│   │   ├── 01-common.yml                  ← make common
│   │   ├── 02-kubernetes.yml              ← make k3s-server / make k3s-agents
│   │   ├── 02b-cilium.yml                 ← make cilium
│   │   ├── 03-storage.yml                 ← make storage
│   │   ├── 03b-longhorn-nvme.yml          ← make longhorn-nvme
│   │   ├── 04-cluster-addons.yml          ← make addons
│   │   ├── 05-ai-stack.yml                ← make ai-stack (LiteLLM; others stub roles)
│   │   ├── 06-dev-tools.yml               ← make dev-tools
│   │   ├── 07-jetson-orin.yml             ← make jetson-orin (unused — see Hardware note)
│   │   ├── 08-jetson-nano.yml             ← make jetson-nano (unused — no target host, reusable scaffolding, see role comment)
│   │   ├── 09-vault.yml                   ← make vault
│   │   ├── 10-tailscale.yml               ← make tailscale
│   │   ├── 11-cloudflare-tunnel.yml       ← make cloudflare
│   │   ├── 16-llama-cpp-jetson.yml        ← make llama-cpp-jetson (Phase 0/1, orin-nx + orin-nano)
│   │   ├── 20-cluster2-kubernetes.yml     ← make cluster2-k3s (code-complete, not yet run live)
│   │   ├── 21-cluster2-longhorn.yml       ← make cluster2-longhorn (code-complete, not yet run live)
│   │   └── 22-cluster2-metallb.yml        ← make cluster2-metallb (code-complete, not yet run live)
│   └── roles/
│       ├── common/                        ← hardening, packages, NTP, UFW
│       ├── k3s-server/ k3s-agent/         ← K3s install/join
│       ├── longhorn/ nfs-server/ minio/   ← storage
│       ├── litellm/                       ← AI gateway (see model_list above)
│       ├── qdrant/ jupyterhub/ langraph-server/ prefect/ mcp-servers/  ← stub roles, not deployed
│       ├── gitea/                         ← self-hosted Git + CI/CD + package-registry retention CronJob
│       ├── vault/ external-secrets/       ← secrets
│       ├── tailscale/ cloudflare-tunnel/  ← remote access
│       ├── jetson-orin/                   ← unused (see Hardware note)
│       ├── jetson-nano/                   ← unused, reusable scaffolding (see role comment)
│       └── llama-cpp-jetson/              ← Phase 0/1: llama.cpp build + server mode on orin-nx/orin-nano — has its own README.md
├── scripts/
│   ├── workstation/setup.sh               ← new machine setup
│   ├── bmc/bmc-power.sh                   ← node power control
│   ├── os-flash/flash-rk1.sh              ← automated OS flash
│   ├── os-flash/discover-nodes.sh         ← find node IPs after flash
│   ├── secrets/setup-api-keys.sh          ← store API keys in Vault
│   └── maintenance/
│       ├── health-check.sh                ← cluster health check
│       ├── cluster-lifecycle.sh           ← shutdown / startup / health-check, --dry-run
│       ├── teardown.sh                    ← reset kubernetes
│       └── llama-serve-test.sh            ← smoke test for llama-server endpoints
├── tools/
│   └── tool-calling-harness/              ← standalone Python harness scoring tool-calling
│                                            reliability (not an Ansible role) — has its own
│                                            README.md and results/SUMMARY.md
├── kubernetes/
│   ├── manifests/                         ← raw K8s YAML
│   └── helm-values/
│       └── prometheus-stack.yml           ← ARM64-tuned Prometheus values
├── cluster2/                              ← CM4 cluster (future — do not touch)
└── docs/
    ├── day0-runbook.md                    ← day-0 hardware/software bring-up checklist
    ├── git-setup.md                       ← GitHub repo init instructions
    ├── jetson-orin-flash.md               ← JetPack flash guide (predates the standalone llama.cpp approach — verify relevance before following)
    ├── medium-series-outline.md           ← content-planning doc, unrelated to cluster ops
    └── runbook.md                         ← main severity-ordered troubleshooting playbook
```

---

## Critical Ansible Notes

### Variable Loading
- **group_vars location:** `ansible/inventory/group_vars/all/vars.yml`
- This is next to the inventory file so Ansible loads it automatically
- If a playbook fails with `undefined variable`, check vars are loading:
  ```bash
  ansible-inventory -i ansible/inventory/hosts.yml --list | grep admin_user
  ```
- Do NOT add `vars_files` to playbooks — fix the root cause instead

### Key Variables (from vars.yml)
```yaml
admin_user: ubuntu
cluster_subnet: "10.0.0.0/24"
cluster_gateway: "10.0.0.1"
cluster_dns: "10.0.0.1"
pod_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
metallb_ip_range_cluster1: "10.0.0.30-10.0.0.49"
k3s_version: "v1.30.5+k3s1"
k3s_server_ip: "10.0.0.11"
longhorn_version: "1.6.2"
nfs_server_ip: "10.0.0.12"
nfs_export_path: "/mnt/sata/k8s"
nfs_sata_device: "/dev/sda2"
litellm_service_ip: "10.0.0.40"
llama_cpp_version: "<pinned commit SHA — see ansible/roles/llama-cpp-jetson/defaults/main.yml>"
llama_active_model_nx: gemma4-12b
llama_active_model_nano: gemma4-e2b
```

### SSH Access
```bash
# Key-based auth works on all 3 RK1 nodes and both standalone Jetsons
ssh ubuntu@10.0.0.11   # rk1-control
ssh ubuntu@10.0.0.12   # rk1-worker-1
ssh ubuntu@10.0.0.13   # rk1-worker-2
ssh raj@10.0.0.14      # orin-nx
ssh raj@10.0.0.50      # orin-nano

# SSH key location
~/.ssh/turingpi_homelab
```

### BMC Control
```bash
source ~/.turingpi   # loads BMC_IP, BMC_USER, BMC_PASSWORD, BMC_TOKEN
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power status
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power on --node 1
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power off --node 1
```

---

## Storage Architecture

| Storage | Device | Mount | StorageClass | Used For |
|---|---|---|---|---|
| Longhorn | /dev/nvme0n1 on rk1-worker-1 + rk1-worker-2 | /var/lib/longhorn-nvme | longhorn (default) | Databases, stateful apps — replicated |
| NFS | SSD on rk1-worker-1 (slot 2, 476.4G) via mini-PCIe SATA adapter — device path confirmed `/dev/sda2` | /mnt/sata → /mnt/sata/k8s | nfs-shared | Shared files, ML models, artifacts |
| MinIO | Longhorn PVC 200Gi | — | — | S3-compatible object storage |

---

## AI/ML Stack Architecture

```
Your apps / agents / notebooks
        │
        ▼ OpenAI-compatible API
LiteLLM Gateway (http://10.0.0.40/v1)
        │
        ├── model="claude-sonnet"          → Anthropic API (anthropic/claude-sonnet-5)
        ├── model="claude-haiku"           → Anthropic API (anthropic/claude-haiku-4-5)
        ├── model="gpt-4.1-mini"           → Azure Foundry
        ├── model="orin-nx-gemma4-12b"     → orin-nx llama-server, no auth (10.0.0.14:8081)
        └── model="orin-nano-gemma4-e2b"   → orin-nano llama-server, no auth (10.0.0.50:8082)
```
LiteLLM's built-in response caching (`litellm_settings.cache`) is backed by
a small Redis instance (`redis.litellm:6379`, `ansible/roles/redis/`,
`make redis`) — identical repeated requests are served from cache instead
of hitting the upstream model again.

See `ansible/roles/llama-cpp-jetson/README.md` for the full model/port
table on both Jetsons (including the non-default alternates and the
systemd `Conflicts=` mutual-exclusion mechanism), and
`ansible/roles/litellm/tasks/main.yml`'s `model_list` comments for
per-model operational caveats (reasoning-token overhead, uncapped
context-window risk on the two local models).

---

## Secrets Management

- **Vault:** HashiCorp Vault running in Kubernetes (namespace: vault)
- **ESO:** External Secrets Operator syncs Vault → K8s Secrets every 60s
- **Init file:** `~/.vault-init.json` — contains unseal keys and root token
- **Credentials file:** `~/.turingpi` — BMC credentials only (not in repo)

### Vault secret paths (confirmed live 2026-08-30)
```
secret/llm-keys               ANTHROPIC_API_KEY (real), AZURE_FOUNDRY_API_KEY (real),
                               AZURE_FOUNDRY_API_BASE (real), GEMINI_API_KEY (still
                               placeholder, AND unused — gemini-pro/gemini-flash were
                               removed from model_list 2026-08-30; ExternalSecret wiring
                               kept for a future real key), LITELLM_MASTER_KEY
secret/minio                  rootUser, rootPassword
secret/postgres                POSTGRES_PASSWORD
secret/redis                   REDIS_PASSWORD
secret/tailscale               AUTH_KEY
secret/cloudflare              TUNNEL_TOKEN, API_TOKEN, ZONE_ID, ACCOUNT_ID
secret/gitea                   GITEA_ADMIN_USER, GITEA_ADMIN_PASSWORD, GITEA_ADMIN_EMAIL
secret/gitea-package-cleanup   TOKEN, TOKEN_NAME (read:package,write:package scope only)
secret/alertmanager            GMAIL_USER, GMAIL_APP_PASSWORD
secret/grafana                 (admin credentials)
secret/headlamp                (admin credentials)
secret/portainer               (admin credentials)
secret/truenas                 (credentials)
```

---

## Remote Access

- **Tailscale:** control-plane only (rk1-control), subnet routing exposes 10.0.0.0/24
  to the tailnet. **Not installed on the worker nodes** — running it there
  repeatedly hijacked their LAN routing (advertising 10.0.0.0/24 from rk1-control
  combined with `--accept-routes` on workers that are already directly on that
  same subnet redirected their return traffic through tailscale0, breaking plain
  ICMP/SSH/kubelet-to-apiserver connectivity and taking them `NotReady`). Tailscale
  was fully removed (`apt remove --purge`) from both workers; do not re-add it
  without solving the overlapping-subnet routing conflict first.
- **Cloudflare Tunnel:** exposes web UIs at kloud-worx.com (no port forwarding)
- **Domain:** kloud-worx.com (on Cloudflare, nameservers pointing from GoDaddy)
- **Alertmanager notifications:** Gmail SMTP (`smtp.gmail.com:587`, credentials in
  Vault at `secret/alertmanager`) is a **temporary** notification channel — plan is
  to replace it with self-hosted `ntfy` once Cluster 2 (CM4) is live (see Future
  Enhancements Backlog).

### Service URLs (confirmed live 2026-08-30 via kubectl)
```
https://vault.kloud-worx.com      HashiCorp Vault UI — LIVE
https://grafana.kloud-worx.com    Grafana monitoring — LIVE
https://gitea.kloud-worx.com      Self-hosted Git — LIVE
https://litellm.kloud-worx.com    LiteLLM API gateway — LIVE
https://minio.kloud-worx.com      MinIO S3 console — LIVE
https://headlamp.kloud-worx.com   Headlamp K8s UI — LIVE
https://portainer.kloud-worx.com  Portainer multi-cluster UI — LIVE
https://truenas.kloud-worx.com    TrueNAS admin — LIVE
https://research-forum.kloud-worx.com  Client app (Gitea CI-deployed) — LIVE
https://rf-pre-event.kloud-worx.com    Client app (Gitea CI-deployed) — LIVE
https://prefect.kloud-worx.com    Reserved — no workload deployed (Prefect is a stub role)
https://jupyter.kloud-worx.com    Reserved — no workload deployed (JupyterHub is a stub role)
https://llm.kloud-worx.com        NOT LIVE — no Open WebUI deployment exists anywhere in the
                                   cluster (confirmed via kubectl). Do not present this as
                                   live/wired in any doc or demo.
```

---

## Make Targets Reference

```bash
# Verification
make check            # verify tools + BMC connectivity
make health           # cluster health check (nodes, pods, services) — lighter/older
make cluster-health    # fuller check: + PVCs, Longhorn volume health, MetalLB, swap, eMMC
make power-status     # show all node power states

# Build sequence (run in this order — all done on Cluster 1 already)
make bootstrap        # SSH keys, hostnames, static IPs (needs --ask-pass first time)
make common           # hardening, packages, NTP, UFW
make kubernetes       # K3s cluster (server + agents) + Cilium CNI — or run individually:
make k3s-server       #   K3s server on rk1-control
make k3s-agents       #   K3s agent join on rk1_workers
make cilium           #   Cilium CNI install (from workstation)
make storage          # Longhorn + NFS + MinIO
make addons           # MetalLB, ingress-nginx, Prometheus, Grafana, Dashboard
make vault            # HashiCorp Vault + External Secrets Operator
make secrets          # store API keys interactively into Vault
make ai-stack         # LiteLLM (others are stub roles, not deployed)
make postgresql       # PostgreSQL for LiteLLM budget/team tracking
make redis            # Redis for LiteLLM response caching
make dev-tools        # Gitea + Actions runner

# Remote access
make tailscale        # Tailscale on rk1-control only (see Remote Access section)
make cloudflare       # Cloudflare Tunnel for kloud-worx.com

# Standalone Jetsons (JetPack pre-flash required; SSH key already provisioned)
make llama-cpp-jetson  # Phase 0/1: build llama.cpp w/ CUDA + deploy llama-server on orin-nx + orin-nano
make llama-serve-test  # smoke test the active llama-server endpoints
make jetson-orin       # UNUSED — original Ollama/Open-WebUI in-cluster plan, no target host
make jetson-nano       # UNUSED — no target host configured, kept as reusable scaffolding

# Cluster 2 (code-complete, not yet run live)
make cluster2-k3s      # K3s cluster (server + agents, default Flannel CNI)
make cluster2-longhorn # Longhorn storage, scoped to cm4-node-3 only
make cluster2-metallb  # MetalLB with its own IP pool (10.0.0.60-69)

# Shortcuts
make build            # common + kubernetes + storage + addons
make build-all        # build + ai-stack + dev-tools

# Power control
make power-on-node N=1    # power on specific BMC slot
make power-off-node N=1   # power off specific BMC slot
make cycle-node N=1        # power cycle specific BMC slot

# Maintenance
make teardown         # reset Kubernetes (keeps OS)
make teardown-hard    # reset Kubernetes + power off nodes
make update           # apt upgrade all nodes
make cluster-shutdown # graceful node power-down (cordons/drains, verifies Longhorn detach)
make cluster-startup  # power-up + re-verify health

# Git
make save MSG="..."   # commit and push
make sync             # pull latest
```

---

## Common Issues and Fixes

### "variable is undefined" in playbook
Ansible isn't finding group_vars. Check:
```bash
# Verify group_vars location
ls ansible/inventory/group_vars/all/vars.yml

# Test variable loading
ansible-inventory -i ansible/inventory/hosts.yml --list | python3 -m json.tool | grep admin_user
```

### BMC token expired
```bash
TOKEN=$(curl -sk -X POST https://10.0.0.10/api/bmc/authenticate \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"root\",\"password\":\"${BMC_PASSWORD}\"}" \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
sed -i "s/export BMC_TOKEN=.*/export BMC_TOKEN=\"$TOKEN\"/" ~/.turingpi
source ~/.turingpi
```

### Node unreachable after Netplan change
The node may still be booting or Netplan didn't apply. Power cycle via BMC:
```bash
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power off --node <slot>
sleep 5
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power on --node <slot>
sleep 60
ping -c 3 10.0.0.1<slot_ip_last_octet>
```

### Vault sealed after restart
```bash
make vault-unseal
```

### Check K8s cluster health
```bash
export KUBECONFIG=~/.kube/turingpi-cluster1.conf
kubectl get nodes -o wide
kubectl get pods -A
make health
```

### Longhorn NFS backups stuck/hung after a node reboot
Check `rpc-statd` is enabled (not just running) on all 3 RK1 nodes:
`systemctl is-enabled rpc-statd`. Also confirm the `backup-target` Setting CR's
`nfsOptions` includes `nolock` — `longhorn-manager` pods have no hostNetwork/
rpcbind, so NFSv3 lock registration fails inside the pod regardless of host
state. Full incident writeup: `SESSION-HANDOFF.md`, "August 16, 2026" entry.

### cloudflared CrashLoopBackOff
Root cause is almost always QUIC/UDP failing on that pod/node's network path
(`kubectl logs -n cloudflare-tunnel <pod>` shows `UDP Connectivity FAIL` /
`QUIC connection failed` while `TCP Connectivity PASS`), racing against the
`livenessProbe`'s ~40s grace window (`/ready` on port 2000) — cloudflared gets
killed before it falls through to its own HTTP2 fallback. **Not a
probe-tuning issue** — fix is `protocol: http2` in cloudflared's
`config.yaml` (`ansible/roles/cloudflare-tunnel/tasks/main.yml`), which skips
QUIC negotiation entirely. Full incident writeup: `SESSION-HANDOFF.md`,
"August 22, 2026" entry.

### Prometheus disk-full CrashLoopBackOff
Check for `no space left on device` in `kubectl logs --previous`. Root cause
is a missing size-based retention backstop — `retention: <time>` alone lets
ingestion overshoot the PVC before the time window naturally cycles data
out. Fix is `retentionSize` (e.g. `"15GB"` on a 20Gi PVC, ~25% headroom) in
`kubernetes/helm-values/prometheus-stack.yml`'s `prometheus.prometheusSpec`
block — **always pair `retention` with `retentionSize`**, never one alone.
To wipe a full PVC for a clean restart: patch the **`Prometheus` CR**'s
`spec.replicas` to `0` (not `kubectl scale statefulset` — the operator
reconciles the StatefulSet from the CR and will silently restore it), then
`kubectl delete pvc`; patch `replicas` back to `1` to let the
`volumeClaimTemplate` recreate a fresh PVC. If a replica then fails to start
on `rk1-control` with `open /var/log/instances/<name>.log: no such file or
directory` (a recurring Longhorn quirk on that node, see the eMMC-migration
entry below), try restarting the `instance-manager` pod on that node first —
often a stale mount, not a missing directory. Full incident writeup:
`SESSION-HANDOFF.md`, "August 23, 2026" entry.

### Gitea package-registry retention (research-forum-app, rf-pre-event-app)
Enforced by a CronJob (`gitea-package-cleanup`, namespace `gitea`, daily
`0 3 * * *`), not native Gitea cleanup rules — this Gitea version (1.27.0)
has no cleanup-rules REST API at all, and the UI-only feature is documented
upstream as unreliable for container-type packages specifically. Policy:
keep newest 10 versions per package, plus a hardcoded live-tag exclusion.
**To change retention count or the live-tag allowlist**: edit
`gitea_package_keep_count` / `gitea_package_live_tags` in
`ansible/inventory/group_vars/all/vars.yml`, then re-run
`ansible-playbook ansible/playbooks/06-dev-tools.yml`. `gitea_package_live_tags`
is a static list — **it must be updated by hand whenever either app's live
deployed tag changes**, or a future cleanup run could delete the
currently-deployed image; this isn't automated. Script:
`ansible/roles/gitea/files/package-cleanup.sh`. Deleting a package version
via the API doesn't free disk immediately — Gitea's built-in
`cleanup_packages` cron task (`@midnight`, 24h grace) sweeps orphaned blobs
automatically; to force it on demand: `POST /api/v1/admin/cron/cleanup_packages`
(needs an `admin`-scoped token — temporary/one-off use only, see below).
**Token in Vault (`secret/gitea-package-cleanup`, key `TOKEN`) is scoped
`read:package,write:package` only** — no `admin` — since the CronJob's
actual job (list + delete versions) never needs it. The one-time backlog
cleanup temporarily used an admin-scoped token for the forced-GC call above;
that token was deleted from Gitea entirely once the one-time work was done
(confirmed revoked: retesting the old token string returned `401`) — no
admin-scoped token persists anywhere for this job. Full incident writeup:
`SESSION-HANDOFF.md`,
"August 23, 2026" entry (includes a process-mistake note on safely dry-running
a CronJob via `kubectl create job --from=cronjob` — override risky env vars
explicitly, its template's live-action defaults get copied verbatim).

### llama-cpp-jetson role re-run re-downloads models / re-triggers a full rebuild
Two separate idempotency gaps, both fixed: model downloads now use
`get_url`'s `checksum:` param (was unconditionally re-fetching multi-GB
files every run); `llama_cpp_version` is pinned to a known-good commit
instead of floating `master` (was triggering full CUDA rebuilds from
unrelated upstream commits landing mid-session). See
`ansible/roles/llama-cpp-jetson/defaults/main.yml` comments and
`SESSION-HANDOFF.md`'s August 23-27, 2026 entry for the full investigation
and verification.

---

## Agentic App Development Stack

```python
# All LLM calls go through LiteLLM — swap models by changing one string
from anthropic import Anthropic

client = Anthropic(
    base_url="http://10.0.0.40/v1",   # LiteLLM gateway
    api_key="your-litellm-master-key"
)

# Google ADK works the same way
from google.adk.agents import Agent
from google.adk.models.lite_llm import LiteLlm

agent = Agent(
    name="homelab-agent",
    model=LiteLlm(
        model="claude-sonnet",              # or "orin-nano-gemma4-e2b" for local/free
        api_base="http://10.0.0.40/v1"
    ),
    tools=[postgres_tool, qdrant_tool, web_search_tool]
)
```

---

## Important Reminders for Claude Code

1. **Never modify cluster2/ directory** — CM4 cluster live bring-up is future work (code exists, not yet run)
2. **Never assign an RK1 node to slot 3** — hardware fault (RK1 NIC/switch silicon). The Orin NX physically occupies this slot but runs standalone, unaffected by the fault.
3. **group_vars path** is `ansible/inventory/group_vars/all/vars.yml`
4. **Secrets** go into Vault via `make secrets`, never hardcoded in files
5. **Kubeconfig** path is `~/.kube/turingpi-cluster1.conf`
6. **BMC credentials** are in `~/.turingpi` — source it before BMC commands
7. **Netplan template** uses `{{ node_static_ip }}`, NOT `{{ ansible_host }}` — the two are
   deliberately decoupled so that a bootstrap-time `-e "ansible_host=<dhcp-ip>"` override
   (needed to reach a freshly flashed node still on DHCP) can't clobber the static IP that
   gets written to disk. `node_static_ip` is set per-host in `hosts.yml`.
8. **Storage devices:** NVMe=`/dev/nvme0n1` (Longhorn, slot 2+4), SATA (NFS, rk1-worker-1
   in slot 2 via mini-PCIe adapter — device path confirmed `/dev/sda2`)
9. **Do not present `llm.kloud-worx.com`/Open WebUI as live** in any doc, demo, or
   summary — confirmed no such deployment exists.
10. **`GEMINI_API_KEY` is still a placeholder** — Gemini routes in LiteLLM will not
    authenticate until `make secrets` is re-run with a real key.

---

## Future Enhancements Backlog

Not scheduled — ideas to revisit once bandwidth allows. Ranked by priority.

1. **ArgoCD** — GitOps operator for self-healing Helm deployments and automated upgrades;
   would replace/complement the current Ansible push model.

2. **RK1 NPU Device Plugin** — exposes the RK3588's built-in NPU to Kubernetes pods for
   on-device inference without a GPU. Reference implementation for the same hardware:
   https://github.com/tylertitsworth/ai-cluster.
   *Prerequisite:* K3s+Cilium cluster stable (done).

3. **Loki** — log aggregation to complement the existing Prometheus+Grafana stack, completing
   the observability triad (metrics, logs, traces). Planned migration target is the CM4
   cluster (Cluster 2), alongside Grafana/Alertmanager, once it's live — frees RK1 resources.

4. **Flyte** — ML pipeline orchestration for distributed training and experiment tracking.
   *Prerequisite:* RK1 NPU workloads active.

5. **Chroma** — vector database for RAG applications.
   *Prerequisite:* LiteLLM gateway serving local models (done — see AI/ML Stack Architecture).

6. **Nvidia Device Plugin + Jetson Exporter** — GPU scheduling and metrics for orin-nx/orin-nano.

7. **Local Coding Assistant** — Open WebUI + Continue.dev VS Code extension wired to the
   existing Phase 1 llama-server endpoints. Self-hosted GitHub Copilot alternative with no
   token limits. Partially superseded by Phase 1's direct llama-server approach — evaluate
   whether Open WebUI adds enough value to deploy, or whether direct LiteLLM routing (already
   live) is sufficient.

8. **Whisper large-v3 speech-to-text** on the Phase 1 Jetson hardware — not yet started.

9. **Self-hosted `ntfy` for Alertmanager notifications** — replaces the current Gmail
   SMTP receiver (`kubernetes/helm-values/prometheus-stack.yml`), which is a temporary
   bridge. Push notifications instead of email, no dependency on a third-party mail
   provider.
   *Prerequisite:* Cluster 2 (CM4) live.

10. **Benchmark Phase 1 inference performance** — the tool-calling harness measured
    correctness, not throughput/latency.

11. **LiteLLM teams/budgets for the client FinOps demo** ($40/mo standard, $200/mo developer)
    — PostgreSQL backend is live and ready (spend tracking, user/team management unblocked);
    the teams/budgets themselves haven't been built yet.
