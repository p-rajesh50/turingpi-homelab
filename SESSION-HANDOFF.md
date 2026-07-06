# TuringPi Homelab — Session Handoff Document
# Date: July 6, 2026
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
| RK1 | rk1-control | 10.0.0.11 | 1 | ✅ Ubuntu 22.04 installed |
| RK1 | rk1-worker-1 | 10.0.0.12 | 2 | ✅ Ubuntu 22.04 (MOVED from slot 3) |
| EMPTY | — | — | 3 | ❌ FAULTY DSA switch port — do not use |
| RK1 | rk1-worker-2 | 10.0.0.13 | 4 | ✅ Ubuntu 22.04 installed |
| Orin NX | orin-nx | 10.0.0.14 | — | ⬜ JetPack 7 not yet flashed |
| Jetson Nano | jetson-nano | 10.0.0.15 | — | ⬜ Not yet configured |

### CRITICAL HARDWARE NOTES:
- **Slot 3 DSA switch port is FAULTY** — nodes in slot 3 cannot communicate 
  with other nodes. Diagnosed via systematic elimination of all software causes.
  ARP works but all unicast IP traffic from slot 3 is dropped by the internal switch.
  Contact TuringPi support for potential RMA.
- **rk1-worker-1 was physically moved from slot 3 to slot 2** to work around the fault.
- The NVMe SSD for slot 2 (Orin NX) was physically installed on the back of the board.

---

## Network Layout

```
10.0.0.1          Router (Xfinity XB8 gateway)
10.0.0.10         Cluster 1 BMC (tpi1-bmc) — static IP configured
10.0.0.11         rk1-control (slot 1)
10.0.0.12         rk1-worker-1 (slot 2, MOVED from slot 3)
10.0.0.13         rk1-worker-2 (slot 4)
10.0.0.14         orin-nx (future)
10.0.0.15         jetson-nano (future)
10.0.0.20         Cluster 2 BMC (future, CM4 cluster)
10.0.0.21-24      Cluster 2 CM4 nodes (future)
10.0.0.30-49      MetalLB pool Cluster 1
10.0.0.50-69      MetalLB pool Cluster 2 (future)
10.0.0.100-199    DHCP pool (router managed)
```

---

## Current Cluster State (as of session end)

### CLUSTER IS DEGRADED — FULL REBUILD IN PROGRESS

The cluster is being rebuilt from scratch with these changes:
1. **Switching from kubeadm to K3s** (TuringPi recommended for RK1)
2. **Switching CNI from Flannel to Cilium** (better ARM64 stability)
3. **Fresh Ubuntu flash on all 3 RK1 nodes**
4. **Incremental stability-first approach** — verify at each phase

### Why rebuild:
- Swap issue on Ubuntu kept crashing kubelet on worker reboots
- Slot 3 hardware fault caused 2 days of networking debugging
- Tailscale + Flannel interaction caused routing issues
- Too many services deployed at once without stability verification
- K3s is TuringPi's recommended stack, better suited for RK1

### Known Issues to Fix:
- Swap file (/swapfile) keeps coming back on worker nodes
  → Fixed in Ansible roles (disable-swap systemd service) but needs deployment
- Longhorn was on eMMC instead of NVMe (already fixed in roles)
- Flannel had DSA/VXLAN interaction issues on ARM64

---

## Workstation Setup (parani-laptop)

```bash
# BMC credentials
source ~/.turingpi  # loads BMC_IP, BMC_USER, BMC_PASSWORD, BMC_TOKEN, TAILSCALE_AUTH_KEY

# Tools installed
tpi v1.0.7          # BMC control CLI
ansible 2.16.3      # automation
kubectl             # at ~/.kube/turingpi-cluster1.conf
cilium CLI          # to be installed

# SSH key for cluster
~/.ssh/turingpi_homelab

# Tailscale IPs (for SSH when LAN fails)
rk1-control:  100.96.0.102
rk1-worker-1: 100.81.77.8
rk1-worker-2: 100.111.182.46

# Vault init file (CRITICAL - backed up to Google Drive and D: drive)
~/.vault-init.json
```

---

## Repository Structure

```
~/projects/turingpi-homelab/
├── CLAUDE.md                    ← Primary context file for Claude Code
├── Makefile                     ← All operations as make targets
├── ansible.cfg
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml            ← Node definitions (slot 2 for worker-1)
│   │   └── group_vars/all/vars.yml  ← All variables
│   ├── playbooks/
│   │   ├── 00-bootstrap.yml
│   │   ├── 01-common.yml        ← Includes permanent swap disable
│   │   ├── 02-kubernetes.yml    ← BEING REWRITTEN for K3s
│   │   ├── 03-storage.yml       ← Longhorn + NFS + MinIO
│   │   ├── 04-cluster-addons.yml ← MetalLB, Ingress, Grafana, Headlamp, Portainer
│   │   ├── 05-ai-stack.yml      ← LiteLLM (deployed)
│   │   ├── 06-dev-tools.yml     ← Gitea (deployed)
│   │   ├── 07-jetson-orin.yml
│   │   ├── 08-jetson-nano.yml
│   │   ├── 09-vault.yml         ← HashiCorp Vault (deployed)
│   │   ├── 10-tailscale.yml     ← Tailscale (deployed but caused issues)
│   │   ├── 11-cloudflare-tunnel.yml ← Cloudflare (deployed)
│   │   └── 12-authentik.yml     ← Authentik SSO (planned, not deployed)
│   └── roles/
│       ├── common/              ← Includes disable-swap systemd service
│       ├── k3s-server/          ← NEW - being created
│       ├── k3s-agent/           ← NEW - being created
│       ├── longhorn/            ← NVMe only (fixed)
│       ├── nfs-server/          ← /dev/sda2 on rk1-worker-1
│       ├── minio/
│       ├── litellm/             ← Deployed, at 10.0.0.40
│       ├── vault/               ← Deployed (needs unseal after rebuild)
│       ├── external-secrets/
│       ├── tailscale/           ← Has --snat-subnet-routes=false fix
│       ├── cloudflare-tunnel/   ← Has DNS + Access policies
│       ├── authentik/           ← Planned but not deployed
│       └── gitea/               ← Deployed at 10.0.0.36
```

---

## What Was Successfully Deployed (before rebuild decision)

| Service | IP | Status | Notes |
|---|---|---|---|
| MetalLB | pool 10.0.0.30-49 | ✅ | Working |
| Ingress-NGINX | 10.0.0.30 | ✅ | Working |
| Grafana | 10.0.0.37 | ✅ | grafana.kloud-worx.com |
| Headlamp | 10.0.0.38 | ✅ | headlamp.kloud-worx.com |
| Portainer | 10.0.0.39 | ✅ | portainer.kloud-worx.com |
| LiteLLM | 10.0.0.40 | ✅ | litellm.kloud-worx.com |
| MinIO | 10.0.0.35 | ✅ | minio.kloud-worx.com |
| Gitea | 10.0.0.36 | ✅ | gitea.kloud-worx.com |
| Vault | in-cluster | ✅ | vault.kloud-worx.com |
| Cloudflare Tunnel | — | ✅ | All services at kloud-worx.com |
| Cloudflare Access | — | ✅ | Google OAuth + MFA |
| Tailscale | — | ✅ | All nodes connected |
| Longhorn | NVMe | ✅ | Migrated from eMMC |
| NFS | /dev/sda2 on worker-1 | ✅ | /mnt/sata/k8s |

### Secrets in Vault (will need to be re-entered after rebuild):
- secret/llm-keys: ANTHROPIC_API_KEY, GEMINI_API_KEY, LITELLM_MASTER_KEY
- secret/minio: rootUser, rootPassword
- secret/postgres: POSTGRES_USER, POSTGRES_PASSWORD
- secret/tailscale: AUTH_KEY (expires Oct 1, 2026)
- secret/cloudflare: TUNNEL_TOKEN, API_TOKEN, ZONE_ID, ACCOUNT_ID
- secret/gitea: GITEA_ADMIN_USER, GITEA_ADMIN_PASSWORD, GITEA_ADMIN_EMAIL
- secret/grafana: ADMIN_PASSWORD
- secret/authentik: (planned but not yet stored)

### Cloudflare Setup:
- Domain: kloud-worx.com (on Cloudflare, nameservers from GoDaddy)
- Tunnel name: turingpi-homelab
- Team domain: rapid-tooth-42c2.cloudflareaccess.com
- Google IdP configured for Access policies
- Allowed email: rajesh.pamulapati@gmail.com
- All 8 services protected with Cloudflare Access

---

## Rebuild Plan (K3s-based, incremental)

### Phase 0 — Repo Updates (Claude Code doing this now)
- [ ] Update inventory (slot 2 for worker-1)
- [ ] Rewrite kubernetes playbook for K3s
- [ ] Create k3s-server and k3s-agent roles
- [ ] Create cilium playbook
- [ ] Update Makefile with K3s targets
- [ ] Update CLAUDE.md

### Phase 1 — Flash (manual via BMC web UI)
- [ ] Flash slot 1 (rk1-control) with Ubuntu 22.04
- [ ] Flash slot 2 (rk1-worker-1) with Ubuntu 22.04
- [ ] Flash slot 4 (rk1-worker-2) with Ubuntu 22.04
- [ ] NOTE: Use BMC web UI, upload .img.xz directly (no decompression needed)
- [ ] NOTE: ~90 min per node, can be done in parallel

### Phase 2 — Bootstrap (Ansible)
- [ ] make bootstrap
- [ ] make common (deploys permanent swap disable)
- [ ] VERIFY: power cycle all nodes, confirm swap stays off
- [ ] VERIFY: all nodes SSH accessible after reboot
- [ ] Do NOT proceed until nodes survive reboot

### Phase 3 — K3s + Cilium
- [ ] make k3s-server
- [ ] make k3s-agents
- [ ] make cilium
- [ ] VERIFY: kubectl get nodes shows all Ready
- [ ] VERIFY: power cycle workers, confirm they rejoin
- [ ] Do NOT proceed until workers auto-rejoin after reboot

### Phase 4 — Storage
- [ ] make storage (Longhorn + NFS + MinIO)
- [ ] VERIFY: volumes survive node reboot

### Phase 5 — Core networking
- [ ] make addons (MetalLB + Ingress-NGINX + Grafana + Headlamp + Portainer)

### Phase 6 — Secrets
- [ ] make vault
- [ ] make secrets (re-enter all credentials)

### Phase 7 — Remote access
- [ ] make cloudflare
- [ ] VERIFY web UIs work before Tailscale

### Phase 8 — Tailscale
- [ ] make tailscale
- [ ] IMMEDIATELY verify inter-node ping still works
- [ ] If broken, rollback Tailscale

### Phase 9 — AI stack + remaining services
- [ ] make ai-stack
- [ ] make dev-tools
- [ ] make authentik (SSO)

---

## Key Learnings / Things NOT to Repeat

1. **Swap issue**: Ubuntu 22.04 creates /swapfile. Must disable permanently 
   via systemd service BEFORE installing K3s/Kubernetes. Verify survives reboot.

2. **Slot 3 is FAULTY**: Never put a node in slot 3. Use slots 1, 2, 4 only.

3. **Longhorn must use NVMe**: Default path /var/lib/longhorn goes to eMMC (30GB).
   Must configure to use /var/lib/longhorn-nvme on /dev/nvme0n1.

4. **Tailscale + CNI interaction**: Tailscale subnet routing can conflict with 
   overlay network CNI. Always verify inter-node ping after Tailscale install.
   Use --snat-subnet-routes=false on the subnet router node.

5. **Deploy incrementally**: Verify cluster stability after EACH phase before 
   proceeding. Power cycle nodes to verify recovery before adding services.

6. **Kubelet port 10250**: kubectl exec/logs requires port 10250 reachable from 
   workstation. Tailscale routing can block this. Use SSH via Tailscale IPs as 
   fallback for node-level operations.

7. **Longhorn volumes**: When a node goes down, volumes get stuck. Set 
   node-down-pod-deletion-policy in Longhorn to auto-recover faster.

8. **K3s vs kubeadm**: K3s is TuringPi's recommended stack. More stable on ARM64,
   less memory overhead, simpler recovery, built-in swap tolerance.

9. **Cilium vs Flannel**: Use Cilium. Flannel had DSA/VXLAN interaction issues 
   on ARM64 RK1 nodes. Cilium is more stable and supports Network Policies.

10. **CLAUDE.md**: Always update CLAUDE.md at the end of each session so 
    Claude Code has accurate context for the next session.

---

## Storage Devices (confirmed)

| Node | Device | Size | Type | Use |
|---|---|---|---|---|
| rk1-control | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn |
| rk1-control | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS only |
| rk1-worker-1 | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn |
| rk1-worker-1 | /dev/sda | 476.9GB | SATA SSD | NFS server |
| rk1-worker-1 | /dev/sda2 | 476.4GB | SATA partition | NFS export |
| rk1-worker-2 | /dev/nvme0n1 | 931.5GB | NVMe | Longhorn |
| rk1-worker-2 | /dev/sda | 57.8GB | USB | Ignore for now |

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

Current immediate task: Claude Code is rewriting 
the Kubernetes playbooks for K3s. Once that is done,
I need to flash the 3 RK1 nodes via BMC web UI and
then run the bootstrap and K3s installation.
```
