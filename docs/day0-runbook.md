# Day 0 Runbook — Complete Setup Guide

## Where we are right now

- ✅ TuringPi 2.5 board powered up in Mini-ITX case
- ✅ BMC static IP set to 10.0.0.10
- ✅ BMC password changed from default
- ✅ tpi v1.0.7 installed (on original machine)
- ⬜ New workstation needs setup
- ⬜ RK1 nodes need Ubuntu flashed (slots 1, 2, 4 — slot 3 is retired/faulty)
- ⬜ Orin NX deferred indefinitely (module removed from the board)
- ⬜ Kubernetes cluster not yet deployed

## Phase 0 — New Workstation Setup ← START HERE

```bash
# In WSL Ubuntu terminal on new machine:

# 1. Clone the repo
git clone git@github.com:p-rajesh50/turingpi-homelab.git ~/turingpi-homelab
cd ~/turingpi-homelab

# 2. Run one-shot workstation setup
# This installs tpi, ansible, saves BMC credentials, generates SSH key
chmod +x scripts/workstation/setup.sh
./scripts/workstation/setup.sh

# 3. Verify everything works
source ~/.turingpi
make check
```

## Phase 1 — Flash Ubuntu 22.04 on RK1 Nodes

```bash
# Flashes slots 1, 3, 4 — downloads image automatically
make flash

# Wait ~60 seconds for nodes to boot, then find their IPs
make discover
```

After `make discover`, note the IPs. They will be on DHCP temporarily.
Update `ansible/inventory/hosts.yml` if the IPs shown differ from:
- rk1-control:   10.0.0.11
- rk1-worker-1:  10.0.0.12
- rk1-worker-2:  10.0.0.13

(The bootstrap playbook will apply the static IPs from inventory.)

## Phase 2 — Bootstrap Nodes

```bash
# Pushes SSH key, sets hostnames, applies static IPs
# You will be prompted for the node password (default: ubuntu)
make bootstrap
```

After bootstrap, nodes will have static IPs and key-based SSH.
Verify: `ansible rk1_nodes -m ping`

## Phase 3 — Common Hardening

```bash
make common
```

Applies to all 3 RK1 nodes: UFW, fail2ban, SSH hardening, NTP, packages.

## Phase 4 — Kubernetes Cluster

```bash
make kubernetes
```

- Installs K3s server on rk1-control (10.0.0.11), with the bundled containerd and
  kubelet — `--flannel-backend=none` since Cilium replaces Flannel
- Joins rk1-worker-1 and rk1-worker-2 as K3s agents
- Installs Cilium CNI
- Fetches kubeconfig to ~/.kube/turingpi-cluster1.conf

Verify:
```bash
export KUBECONFIG=~/.kube/turingpi-cluster1.conf
kubectl get nodes -o wide
```

## Phase 5 — Storage

```bash
make storage
```

- Formats /dev/sda on rk1-worker-2 (512GB SATA SSD) → NFS export
- Deploys Longhorn on NVMe drives across all 3 nodes
- Deploys NFS StorageClass provisioner
- Deploys MinIO (S3-compatible object storage)

StorageClasses after this step:
- `longhorn` (default) — replicated block storage on NVMe
- `nfs-shared`         — shared filesystem on SATA SSD

## Phase 6 — Cluster Add-ons

```bash
make addons
```

Deploys: MetalLB, Ingress-NGINX, Prometheus + Grafana, Kubernetes Dashboard

Services after this step:
- Grafana:     http://10.0.0.37
- MetalLB pool: 10.0.0.30 – 10.0.0.49

## Phase 7 — Store API Keys

```bash
make secrets
```

Interactive prompt for:
- Anthropic API key (Claude)
- Google Gemini API key
- LiteLLM master key
- MinIO admin password

Keys stored as Kubernetes Secrets — never written to disk.

## Phase 8 — AI Stack

```bash
make ai-stack
```

Deploys:
- LiteLLM Gateway at http://10.0.0.30  (OpenAI-compatible API)
- Qdrant vector database
- Postgres + pgvector
- JupyterHub
- LangGraph Server
- Prefect orchestration
- MCP servers (postgres, qdrant, minio, web-search)

## Phase 9 — Developer Tools

```bash
make dev-tools
```

Deploys: Gitea (self-hosted Git) + Gitea Actions runner

## Phase 10 — Jetson Orin NX (slot 2)

JetPack 7 must be flashed manually. See `docs/jetson-orin-flash.md`.

After flashing and setting static IP to 10.0.0.14:
```bash
make jetson-orin
```

## Phase 11 — Jetson Nano (standalone)

JetPack 4.6 must be flashed manually. See `docs/jetson-nano-flash.md`.

After flashing and setting static IP to 10.0.0.15:
```bash
make jetson-nano
```

## Quick Reference — Service URLs

| Service          | URL                        |
|------------------|----------------------------|
| LiteLLM Gateway  | http://10.0.0.30/v1        |
| Open WebUI       | http://10.0.0.14:3000      |
| Grafana          | http://10.0.0.37           |
| MinIO Console    | http://10.0.0.35:9001      |
| MinIO S3 API     | http://10.0.0.35:9000      |
| Gitea            | http://10.0.0.36            |
| Ollama (Orin NX) | http://10.0.0.14:11434     |
| Ollama (Nano)    | http://10.0.0.15:11434     |
| BMC              | https://10.0.0.10          |
