# Medium Article Series Outline

## "Building a Production-Grade AI Homelab on TuringPi"

A planned 8-part series for Medium.com targeting senior engineers
comfortable with Kubernetes but new to homelab/ARM64/self-hosted AI.

**Tone:** Conversational but technically precise, honest about failures,
practical takeaways in each article.
**Length:** 4-7 minutes per article (~800-1400 words each)

---

### Article 1: Why I Built a Home AI Cluster (And Why You Should Too)

*4-5 min read*

- The problem: API costs, token limits, privacy concerns with cloud LLMs
- The vision: self-hosted AI gateway, local inference, production-grade ops
- Hardware overview: TuringPi 2.5, RK1 modules, ARM64 architecture
- Cost breakdown vs cloud alternatives
- What you will learn in this series

---

### Article 2: Hardware Setup and the Lessons Learned the Hard Way

*5-6 min read*

- TuringPi 2.5 board layout, BMC management
- The faulty DSA switch port (slot 3) — diagnosed with tcpdump
- Physical hardware changes: moving modules between slots, mini PCIe SATA adapter
- Flashing Ubuntu via BMC web UI
- Key lesson: always verify hardware with tcpdump before assuming software failure

---

### Article 3: From kubeadm to K3s — Choosing the Right Kubernetes for ARM64

*5-6 min read*

- Why we started with kubeadm+Flannel and why it failed
- Swap issues on Ubuntu crashing kubelet
- Why K3s is better for RK1/ARM64
- Cilium vs Flannel on ARM64 — the VXLAN interface conflict story
- The rebuild decision: when to cut losses and start fresh

---

### Article 4: Production-Grade Secrets Management on a Homelab

*4-5 min read*

- Why you should not store secrets in git (even for homelab)
- HashiCorp Vault + External Secrets Operator architecture
- How ESO syncs Vault secrets to Kubernetes automatically
- Cloudflare Access + Google OAuth for zero-trust access
- Lessons: always use a secrets manager, even at home

---

### Article 5: Storage Architecture — NVMe, NFS, and Longhorn on ARM64

*5-6 min read*

- The eMMC trap: why default K3s installs fill up your boot disk
- Longhorn on NVMe: the multipathd conflict and fix
- NFS via mini PCIe SATA adapter: the hardware journey
- MinIO for object storage
- The symlink strategy for redirecting containerd/rancher to NVMe

---

### Article 6: Tailscale + Cloudflare — Remote Access Without Opening Ports

*4-5 min read*

- The architecture: Tailscale for node SSH, Cloudflare for web services
- Why Tailscale on workers broke LAN connectivity (the --accept-routes trap)
- Control-plane-only Tailscale as the solution
- Cloudflare Tunnel + Access: production-grade auth for free
- Google OAuth protecting 8 services with zero open inbound ports

---

### Article 7: Self-Hosted LLM Gateway with LiteLLM

*5-7 min read*

- LiteLLM as a unified API gateway for multiple LLM providers
- Routing between Anthropic, Gemini, and local models
- Integration with Kubernetes via Helm
- The vision: adding Ollama + local models for truly offline inference
- Cost analysis: when does self-hosting pay off?

---

### Article 8: Operational Excellence — Monitoring, Alerting, and Runbooks

*4-5 min read*

- Grafana + Prometheus on ARM64
- The metrics-server kubelet scrape fix (pod CIDR UFW rule)
- Building a graceful shutdown/startup script
- Operational runbook: the 20 most common failure modes
- Lessons learned: what breaks first and why
- The Longhorn /var/log/instances race condition — a 90-minute debugging
  session that started with a routine metrics Helm upgrade and ended with
  discovering that a missing log directory in the instance-manager pod was
  the root cause. Document the full symptom chain, what didn't work, and the
  2-command fix.

---

## Key Themes to Weave Throughout the Series

Real incidents from this build that make compelling reading:

- Faulty DSA switch port diagnosed with tcpdump (looked like hardware
  failure, was switch silicon defect)
- Tailscale broke LAN connectivity on workers 3 times before isolating root
  cause (--accept-routes + subnet overlap)
- eMMC filled to 86% because leftover kubeadm containerd service was still
  running alongside K3s
- multipathd silently grabbed Longhorn iSCSI devices blocking volume
  formatting
- RollingUpdate strategy deadlocks single-replica RWO PVC pods — must use
  Recreate strategy
- Vault seals after every pod restart — requires manual unseal
- The journey from "saving on API costs" to genuinely production-grade
  infrastructure

## Starting Prompt for Writing Session

Use this prompt in a new Claude chat to start writing the articles:

```
I built a production-grade AI homelab on TuringPi 2.5 hardware
running K3s + Cilium, Longhorn storage, HashiCorp Vault, LiteLLM
AI gateway, Gitea, Grafana, and Cloudflare Tunnel. I want to write
an 8-part Medium article series about this experience.

The series is called 'Building a Production-Grade AI Homelab on
TuringPi'. Please read docs/medium-series-outline.md for the full
outline, then help me write Article 1 first.
```
