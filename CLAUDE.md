# TuringPi Homelab — Claude Code Context

This file provides context for Claude Code to understand the project,
current state, and how to continue the build. Read this before executing
any commands or making any changes.

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

### Cluster 1 — TuringPi 2.5 (PRIMARY — currently being built)

| Device | Hostname | IP | Slot | Status |
|---|---|---|---|---|
| BMC | tpi1-bmc | 10.0.0.10 | — | ✅ Static IP configured |
| RK1 | rk1-control | 10.0.0.11 | 1 | ✅ Ubuntu 22.04, static IP, hardened |
| RK1 | rk1-worker-1 | 10.0.0.12 | 2 | ✅ Ubuntu 22.04, static IP, hardened (moved from slot 3 after hardware fault; NFS SATA SSD re-homed via mini-PCIe adapter, device path unverified) |
| RK1 | rk1-worker-2 | 10.0.0.13 | 4 | ✅ Ubuntu 22.04, static IP, hardened |
| — | (slot 3) | — | 3 | ⛔ EMPTY / FAULTY — RK1 NIC/switch-silicon fault, never assign a node here |

> **Orin NX module removed from the board entirely** (was slot 2) — Jetson Orin setup
> (Step 15) is deferred indefinitely until the module is reinstalled somewhere.

### Standalone Nodes

| Device | Hostname | IP | Status |
|---|---|---|---|
| Jetson Nano | jetson-nano | 10.0.0.15 | ⬜ Not yet configured |

### Cluster 2 — TuringPi 2 + CM4 (FUTURE — do not build yet)

| Device | Hostname | IP |
|---|---|---|
| BMC | tpi2-bmc | 10.0.0.20 |
| CM4 Node 1 | cm4-node-1 | 10.0.0.21 |
| CM4 Node 2 | cm4-node-2 | 10.0.0.22 |
| CM4 Node 3 | cm4-node-3 | 10.0.0.23 |
| CM4 Node 4 | cm4-node-4 | 10.0.0.24 |

### TrueNAS (FUTURE — do not configure yet)

| Device | Hostname | IP |
|---|---|---|
| TrueNAS Core (FreeBSD) | truenas | 10.0.0.5 |

---

## Network

```
10.0.0.1          Router / gateway
10.0.0.5          TrueNAS (future)
10.0.0.10         Cluster 1 BMC (tpi1-bmc)
10.0.0.11         rk1-control  (slot 1)
10.0.0.12         rk1-worker-1 (slot 2, moved from slot 3) — also NFS server (mini-PCIe SATA adapter, path unverified)
10.0.0.13         rk1-worker-2 (slot 4)
                  slot 3 — EMPTY / FAULTY, never assign a node here
10.0.0.15         jetson-nano  (standalone)
10.0.0.20-24      Cluster 2 (future)
10.0.0.30-49      MetalLB LoadBalancer pool (Cluster 1)
10.0.0.50-69      MetalLB LoadBalancer pool (Cluster 2, future)
10.0.0.100-199    DHCP pool (router managed)
```

---

## Build Order (overall project)

> ⚠️ **REBUILD IN PROGRESS** — a hardware fault at slot 3 forced a physical rework
> (rk1-worker-1 moved to slot 2, Orin NX removed, slot 3 retired). Taking this as an
> opportunity to also replace kubeadm+Flannel with K3s+Cilium. Steps 6 and 8 below are
> reset to reflect the in-progress rebuild; a full data wipe (Vault/Gitea/Longhorn/MinIO)
> was accepted, so steps 9-14 will need to be re-run against the new cluster even though
> the roles themselves aren't changing.

1. ✅ Cluster 1 — Workstation setup
2. ✅ Cluster 1 — BMC static IP + credentials
3. ✅ Cluster 1 — Flash Ubuntu 22.04 on RK1 nodes (originally slots 1, 3, 4 — module now in slot 2)
4. ✅ Cluster 1 — Bootstrap (SSH keys, hostnames, static IPs)
5. ✅ Cluster 1 — Common hardening (UFW, fail2ban, NTP, packages)
6. ⬜ Cluster 1 — K3s cluster (server + agents)   ← NEXT STEP
7. ⬜ Cluster 1 — Storage (Longhorn + NFS + MinIO) — re-run after rebuild; verify NFS SATA device path first (see Storage Architecture note)
7b. ⬜ Cluster 1 — Longhorn NVMe migration
8. ⬜ Cluster 1 — Cluster add-ons incl. Cilium CNI (MetalLB, ingress, Prometheus)
9. ⬜ Cluster 1 — Vault + External Secrets Operator — re-run, data wiped
10. ⬜ Cluster 1 — Secrets setup (API keys into Vault) — re-enter via `make secrets`
11. ⬜ Cluster 1 — AI stack (LiteLLM; Qdrant/JupyterHub/LangGraph/Prefect still stub roles)
12. ⬜ Cluster 1 — Developer tools (Gitea + CI/CD) — re-run, repos wiped
13. ⬜ Cluster 1 — Tailscale (remote access) — re-run against new cluster
14. ⬜ Cluster 1 — Cloudflare Tunnel (web UIs at kloud-worx.com) — re-run against new cluster
15. ⬜ Jetson Orin NX — deferred indefinitely (module removed from board)
16. ⬜ Jetson Nano — JetPack 4.6 flash (manual) + Ansible setup
17. ⬜ TrueNAS — SMB + NFS + Jellyfin (FreeBSD Core)
18. ⬜ Cluster 2 — CM4 cluster + Pi-hole + dev sandbox

---

## Repository Structure

```
turingpi-homelab/
├── CLAUDE.md                              ← YOU ARE HERE
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
│   │   ├── 04-cluster-addons.yml          ← make addons
│   │   ├── 05-ai-stack.yml                ← make ai-stack
│   │   ├── 06-dev-tools.yml               ← make dev-tools
│   │   ├── 07-jetson-orin.yml             ← make jetson-orin
│   │   ├── 08-jetson-nano.yml             ← make jetson-nano
│   │   ├── 09-vault.yml                   ← make vault
│   │   ├── 10-tailscale.yml               ← make tailscale
│   │   └── 11-cloudflare-tunnel.yml       ← make cloudflare
│   └── roles/
│       ├── common/                        ← hardening, packages, NTP, UFW
│       ├── k3s-server/                    ← K3s server install, node-token, kubeconfig
│       ├── k3s-agent/                     ← K3s agent install/join
│       ├── longhorn/                      ← replicated block storage (NVMe)
│       ├── nfs-server/                    ← shared filesystem (SATA SSD)
│       ├── minio/                         ← S3-compatible object storage
│       ├── litellm/                       ← AI gateway (routes to Ollama + cloud)
│       ├── qdrant/                        ← vector database
│       ├── jupyterhub/                    ← notebook environment
│       ├── langraph-server/               ← production agent runtime
│       ├── prefect/                       ← agent orchestration
│       ├── mcp-servers/                   ← MCP tool servers (postgres, qdrant, minio)
│       ├── gitea/                         ← self-hosted Git + CI/CD
│       ├── vault/                         ← HashiCorp Vault secrets management
│       ├── external-secrets/              ← syncs Vault → K8s Secrets
│       ├── tailscale/                     ← remote access mesh VPN
│       ├── cloudflare-tunnel/             ← expose web UIs at kloud-worx.com
│       ├── jetson-orin/                   ← Orin NX LLM setup
│       └── jetson-nano/                   ← Nano embedding server setup
├── scripts/
│   ├── workstation/setup.sh               ← new machine setup
│   ├── bmc/bmc-power.sh                   ← node power control
│   ├── os-flash/flash-rk1.sh             ← automated OS flash
│   ├── os-flash/discover-nodes.sh        ← find node IPs after flash
│   ├── secrets/setup-api-keys.sh         ← store API keys in Vault
│   └── maintenance/
│       ├── health-check.sh               ← cluster health check
│       └── teardown.sh                   ← reset kubernetes
├── kubernetes/
│   ├── manifests/                         ← raw K8s YAML
│   └── helm-values/
│       └── prometheus-stack.yml           ← ARM64-tuned Prometheus values
├── cluster2/                              ← CM4 cluster (future — do not touch)
└── docs/
    ├── day0-runbook.md                    ← complete setup guide
    └── git-setup.md                       ← GitHub setup instructions
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
ollama_port: 11434
litellm_service_ip: "10.0.0.40"
```

### SSH Access
```bash
# Key-based auth works on all 3 RK1 nodes
ssh ubuntu@10.0.0.11   # rk1-control
ssh ubuntu@10.0.0.12   # rk1-worker-1
ssh ubuntu@10.0.0.13   # rk1-worker-2

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
| NFS | SSD on rk1-worker-1 (slot 2, 476.4G) via mini-PCIe SATA adapter — **device path unverified**, confirm with `lsblk`/`fdisk -l` before `make storage`; may not still be `/dev/sda2` | /mnt/sata → /mnt/sata/k8s | nfs-shared | Shared files, ML models, artifacts |
| MinIO | Longhorn PVC 200Gi | — | — | S3-compatible object storage |

---

## AI/ML Stack Architecture

```
Your apps / agents / notebooks
        │
        ▼ OpenAI-compatible API
LiteLLM Gateway (http://10.0.0.40/v1)
        │
        ├── model="gemma3"     → Orin NX Ollama — DEFERRED, module removed from board
        ├── model="mistral"    → Orin NX Ollama — DEFERRED, module removed from board
        ├── model="openchat"   → Orin NX Ollama — DEFERRED, module removed from board
        ├── model="claude-*"   → Anthropic API (key in Vault)
        ├── model="gemini-*"   → Google AI API (key in Vault)
        ├── model="phi3-mini"  → Jetson Nano Ollama (10.0.0.15:11434)
        └── model="all-minilm" → Jetson Nano Ollama (embeddings)
```

---

## Secrets Management

- **Vault:** HashiCorp Vault running in Kubernetes (namespace: vault)
- **ESO:** External Secrets Operator syncs Vault → K8s Secrets every 60s
- **Init file:** `~/.vault-init.json` — contains unseal keys and root token
- **Credentials file:** `~/.turingpi` — BMC credentials only (not in repo)

### Vault secret paths
```
secret/llm-keys      ANTHROPIC_API_KEY, GEMINI_API_KEY, LITELLM_MASTER_KEY
secret/minio         rootUser, rootPassword
secret/postgres      POSTGRES_USER, POSTGRES_PASSWORD
secret/tailscale     AUTH_KEY
secret/cloudflare    TUNNEL_TOKEN, API_TOKEN, ZONE_ID, ACCOUNT_ID
```

---

## Remote Access

- **Tailscale:** mesh VPN, subnet routing via rk1-control exposes 10.0.0.0/24
- **Cloudflare Tunnel:** exposes web UIs at kloud-worx.com (no port forwarding)
- **Domain:** kloud-worx.com (on Cloudflare, nameservers pointing from GoDaddy)

### Service URLs (after full deployment)
```
https://vault.kloud-worx.com      HashiCorp Vault UI
https://grafana.kloud-worx.com    Grafana monitoring
https://jupyter.kloud-worx.com    JupyterHub notebooks
https://gitea.kloud-worx.com      Self-hosted Git
https://llm.kloud-worx.com        Open WebUI (chat with local models)
https://litellm.kloud-worx.com    LiteLLM API gateway
https://minio.kloud-worx.com      MinIO S3 console
https://prefect.kloud-worx.com    Prefect orchestration UI
https://headlamp.kloud-worx.com   Headlamp K8s UI
https://portainer.kloud-worx.com  Portainer multi-cluster UI
https://truenas.kloud-worx.com    TrueNAS admin (future)
```

---

## Make Targets Reference

```bash
# Verification
make check            # verify tools + BMC connectivity
make health           # cluster health check (nodes, pods, Ollama, services)
make power-status     # show all node power states

# Build sequence (run in this order)
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
make ai-stack         # LiteLLM, Qdrant, JupyterHub, LangGraph, Prefect, MCP servers
make dev-tools        # Gitea + Actions runner
make tailscale        # Tailscale on all nodes
make cloudflare       # Cloudflare Tunnel for kloud-worx.com

# GPU nodes (manual JetPack flash required first — see docs/)
make jetson-orin      # Orin NX: Ollama, Open WebUI, ML stack
make jetson-nano      # Jetson Nano: embeddings, small models

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

---

## Current State Summary

As of the last session: **mid-rebuild.** A hardware fault localized to slot 3 (confirmed via
live incident investigation — kernel-level ICMP counters on rk1-worker-1 proved the node's own
stack was healthy, so the packet loss was in transit, pointing to the RK1 module's NIC/PHY or
the TuringPi board's slot-3 switch silicon) forced a physical rework:

- rk1-worker-1's RK1 module moved from slot 3 → slot 2.
- Slot 3 retired — empty, never to be assigned a node again.
- Orin NX module removed from the board entirely (was slot 2) — Step 15 deferred indefinitely.
- NFS SATA SSD being re-homed via a mini-PCIe SATA adapter card in slot 2 — **unverified**,
  node 2 was still being reflashed as of this writing; confirm device path before `make storage`.

Taking the rebuild as an opportunity to also replace kubeadm+Flannel with K3s+Cilium
(`ansible/roles/k3s-server`, `ansible/roles/k3s-agent`, `ansible/playbooks/02b-cilium.yml`).
A full data wipe was accepted — no backup was taken of the previous cluster's Vault secrets,
Gitea repos, Longhorn volumes, or MinIO data before rebuilding.

**Still valid from before the rebuild (not being redone):**
- BMC configured with static IP 10.0.0.10, password changed
- tpi v1.0.7 installed on WSL workstation, all credentials in ~/.turingpi
- SSH key-based auth working on all 3 RK1 nodes; common hardening applied (UFW, fail2ban,
  SSH hardening, NTP)
- Repo at github.com/p-rajesh50/turingpi-homelab

**Reset by the rebuild (need to be re-run from scratch against the new cluster):**
- Kubernetes: was kubeadm 1.30.14 + Flannel — now being rebuilt as K3s + Cilium (Steps 6, 8)
- Storage (Longhorn/NFS/MinIO), Vault + ESO, secrets, AI stack, dev tools (Gitea), Tailscale,
  Cloudflare Tunnel — all previously complete (Steps 7, 9-14) but wiped along with the old
  cluster; re-run in order once the new K3s+Cilium cluster is verified healthy
- ~/.vault-init.json from the old cluster is stale once Vault is reinitialized — a fresh one
  will be generated by `make vault`; back up the new one once created
- Manual Tailscale follow-ups (key-expiry disable, subnet-route approval in the admin console)
  will need to be redone once Tailscale is redeployed

**Next immediate step:**
Verify rk1-worker-1 comes up cleanly in slot 2 (`make bootstrap`, `make common`), then
`make kubernetes` (K3s server → agents → Cilium). Confirm `kubectl get nodes` shows all 3
Ready and `cilium status` is clean before checking the NFS SATA device path and proceeding
to `make storage`.

---

## Agentic App Development Stack (once cluster is running)

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
        model="claude-sonnet",          # or "gemma3" for local/free
        api_base="http://10.0.0.40/v1"
    ),
    tools=[postgres_tool, qdrant_tool, web_search_tool]
)
```

---

## Important Reminders for Claude Code

1. **Never modify cluster2/ directory** — CM4 cluster is future work
2. **Never assign a node to slot 3** — hardware fault (RK1 NIC/switch silicon); Orin NX
   module has been removed from the board entirely, no slot currently assigned to it
3. **group_vars path** is `ansible/inventory/group_vars/all/vars.yml`
4. **Secrets** go into Vault via `make secrets`, never hardcoded in files
5. **Kubeconfig** path is `~/.kube/turingpi-cluster1.conf`
6. **BMC credentials** are in `~/.turingpi` — source it before BMC commands
7. **Netplan template** uses `{{ node_static_ip }}`, NOT `{{ ansible_host }}` — the two are
   deliberately decoupled so that a bootstrap-time `-e "ansible_host=<dhcp-ip>"` override
   (needed to reach a freshly flashed node still on DHCP) can't clobber the static IP that
   gets written to disk. `node_static_ip` is set per-host in `hosts.yml`.
8. **Storage devices:** NVMe=`/dev/nvme0n1` (Longhorn, slot 2+4), SATA (NFS, rk1-worker-1
   in slot 2 via mini-PCIe adapter — device path **unverified**, don't assume `/dev/sda2`
   until confirmed with `lsblk`/`fdisk -l` post-reflash)
