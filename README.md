# TuringPi Homelab

Fully automated homelab cluster built on TuringPi 2.5 (Cluster 1) and TuringPi 2 (Cluster 2),
with Kubernetes, local LLM inference, AI gateway, agentic app runtime, and full MLOps stack.

## Hardware

### Cluster 1 — TuringPi 2.5 (this repo root)

| Slot | Module         | Hostname       | IP          | Role                        |
|------|----------------|----------------|-------------|-----------------------------|
| BMC  | —              | tpi1-bmc       | 10.0.0.10   | Board management controller |
| 1    | Turing RK1     | rk1-control    | 10.0.0.11   | Kubernetes control plane    |
| 2    | Nvidia Orin NX | orin-nx        | 10.0.0.14   | LLM inference (Ollama)      |
| 3    | Turing RK1     | rk1-worker-1   | 10.0.0.12   | Kubernetes worker           |
| 4    | Turing RK1     | rk1-worker-2   | 10.0.0.13   | Kubernetes worker + NFS     |

### Cluster 2 — TuringPi 2 (see cluster2/)

| Slot | Module   | Hostname   | IP          | Role                  |
|------|----------|------------|-------------|-----------------------|
| BMC  | —        | tpi2-bmc   | 10.0.0.20   | Board management      |
| 1    | CM4      | cm4-node-1 | 10.0.0.21   | Kubernetes control    |
| 2    | CM4      | cm4-node-2 | 10.0.0.22   | Kubernetes worker     |
| 3    | CM4      | cm4-node-3 | 10.0.0.23   | Kubernetes worker     |
| 4    | CM4      | cm4-node-4 | 10.0.0.24   | Kubernetes worker     |

### Standalone Nodes

| Device              | Hostname     | IP          | Role                              |
|---------------------|--------------|-------------|-----------------------------------|
| Nvidia Jetson Nano  | jetson-nano  | 10.0.0.15   | Embedding server + small models   |

## Network Layout

```
10.0.0.1          Router / gateway
10.0.0.10         Cluster 1 BMC   (tpi1-bmc)
10.0.0.11–14      Cluster 1 nodes
10.0.0.15         Jetson Nano (standalone)
10.0.0.20         Cluster 2 BMC   (tpi2-bmc)
10.0.0.21–24      Cluster 2 CM4 nodes
10.0.0.30–49      MetalLB pool — Cluster 1 LoadBalancer services
10.0.0.50–69      MetalLB pool — Cluster 2 LoadBalancer services
10.0.0.100–199    DHCP pool (router managed — laptops, phones, etc.)
```

## Full Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                 Kubernetes — Cluster 1 (RK1 nodes)              │
│                                                                  │
│  INGRESS (10.0.0.30)                                            │
│    ├── LiteLLM AI Gateway  ← routes to Orin NX + cloud APIs    │
│    ├── Open WebUI          ← chat UI for local models           │
│    ├── JupyterHub          ← ADK / LangGraph / Anthropic SDK    │
│    ├── LangGraph Server    ← production agent runtime            │
│    ├── Prefect             ← agent orchestration + scheduling    │
│    ├── Gitea + CI/CD       ← self-hosted Git + pipelines        │
│    └── Grafana             ← cluster + LLM monitoring           │
│                                                                  │
│  STORAGE                                                         │
│    ├── Longhorn  (NVMe 1TB × 3, replicated block storage)       │
│    ├── NFS       (SATA SSD 512GB on node 4, shared filesystem)  │
│    └── MinIO     (S3-compatible, backed by Longhorn)            │
│                                                                  │
│  DATABASES                                                       │
│    ├── Postgres + pgvector (relational + vector search)         │
│    └── Qdrant              (dedicated vector database)          │
│                                                                  │
│  MCP SERVERS (as K8s pods)                                      │
│    ├── mcp-postgres, mcp-qdrant, mcp-minio, mcp-web-search     │
└─────────────────────────────────────────────────────────────────┘
         │ Ollama API              │ Cloud APIs (via LiteLLM)
         ▼                        ▼
┌─────────────────┐    ┌──────────────────────────────┐
│  Orin NX        │    │  Anthropic (Claude)           │
│  10.0.0.14      │    │  Google (Gemini)              │
│                 │    └──────────────────────────────┘
│  Gemma4         │
│  NemoClaw       │    ┌──────────────────────────────┐
│  OpenClaw       │    │  Jetson Nano — 10.0.0.15     │
│  Mistral        │    │  nomic-embed-text (embeddings)│
│  nomic-embed    │    │  Phi-3 mini / TinyLlama       │
└─────────────────┘    └──────────────────────────────┘
```

## Quick Start

```bash
# 1. Set up workstation (new machine)
make setup

# 2. Flash Ubuntu on RK1 nodes
make flash

# 3. Discover node IPs after first boot
make discover

# 4. Bootstrap (SSH keys, hostnames, static IPs)
make bootstrap

# 5. Full cluster build
make build

# 6. Store your API keys
make secrets
```

See `docs/day0-runbook.md` for the complete step-by-step guide.

## Repository Structure

```
turingpi-homelab/
├── Makefile                          # All operations as make targets
├── ansible/
│   ├── inventory/hosts.yml           # Node definitions and IPs
│   ├── group_vars/all/vars.yml       # Global config (IPs, versions, models)
│   ├── playbooks/                    # Orchestration playbooks (00-08)
│   └── roles/                        # Ansible roles (one per service)
├── scripts/
│   ├── workstation/setup.sh          # New machine setup
│   ├── bmc/bmc-power.sh             # Node power control
│   ├── os-flash/flash-rk1.sh        # Automated OS flash
│   ├── os-flash/discover-nodes.sh   # Find node IPs after flash
│   ├── secrets/setup-api-keys.sh    # Store API keys in K8s
│   └── maintenance/                 # Teardown, rebuild, health check
├── kubernetes/
│   ├── manifests/                    # Raw K8s YAML
│   └── helm-values/                  # Helm chart value overrides
├── cluster2/                         # TuringPi 2 + CM4 cluster (future)
└── docs/                             # Runbooks and architecture notes
```
