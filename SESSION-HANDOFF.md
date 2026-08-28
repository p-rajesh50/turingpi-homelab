# TuringPi Homelab — Session Handoff Document
# Date: July 26, 2026 (PostgreSQL live for LiteLLM, Cluster 2 CM4 flashing breakthrough, Longhorn backup NFSv3 fix, Cluster 2 K3s plan checkpoint — see STATUS below)
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

**Since that handoff (same day, new session):** metrics-server, Headlamp RBAC
(two separate bugs), eMMC space on all 3 nodes, `health-check.sh`, and a new
`cluster-lifecycle.sh` (shutdown/startup/health-check) have all been fixed,
written, and verified. See "Post-Handoff Fixes" below — the eMMC urgency
flagged in the previous version of this doc is resolved. Documentation was
also brought fully current: `docs/runbook.md` (20-item severity-ordered
troubleshooting playbook), a full `README.md` rewrite (was describing the
pre-rebuild architecture), and `docs/medium-series-outline.md` (planned
8-part article series).

**July 9, 2026 — Chunk 4 and Chunk 5 both complete and verified live:**

- **Cluster health fixes**: eMMC space reclaimed on all 3 nodes (rk1-worker-2
  86%→35%, rk1-worker-1 56%→22%, rk1-control 53%→46%); Headlamp RBAC fixed
  (`cluster-admin` was bound to the wrong ServiceAccount); metrics-server
  fixed (missing pod-CIDR UFW rule for same-node kubelet self-scrape);
  `cluster-lifecycle.sh` added (shutdown/startup/health-check, `--dry-run`
  supported); `health-check.sh` field-selector bug fixed.
- **Documentation**: `docs/runbook.md` created (20 failure modes, 4 severity
  tiers, now 21 with the Longhorn stuck-attach entry below); `README.md`
  fully rewritten for the current K3s+Cilium architecture;
  `docs/medium-series-outline.md` created (8-article series outline).
- **Chunk 4 — Prometheus alerting with Gmail SMTP**: 14 `PrometheusRule`
  alert rules across critical/high/warning severity tiers, Alertmanager wired
  to Gmail SMTP via a Vault-backed `ExternalSecret`, and a node-exporter
  textfile collector on rk1-control backing the `TailscaleDown` alert (no
  native Tailscale exporter exists). Verified live: a real test alert was
  delivered to Gmail.
- **Chunk 5 — Grafana dashboards + ServiceMonitors**: 8 community dashboards
  provisioned under Grafana's "TuringPi" folder; new `ServiceMonitor`s for
  MinIO, Gitea, and Cilium, all reporting `up` in Prometheus. Also fixed the
  worker-node apt-cache failure (stale Tailscale APT source left over from
  the earlier Tailscale-on-workers incident) and hit + resolved a real
  Longhorn `/var/log/instances` stuck-attach incident along the way — full
  recovery procedure now in `docs/runbook.md`, and a preventive Ansible task
  was added to `ansible/roles/common`. **Gitea's PVC now runs on
  rk1-worker-2** (moved from rk1-worker-1 during incident recovery — nothing
  pins it back).

**Current cluster state:** all 3 RK1 nodes `Ready`, all pods `Running`, all
services live at kloud-worx.com, Gmail alerting active for
critical/high/warning events, `make cluster-health` passes cleanly.

**July 10, 2026 — TrueNAS live, Grafana dashboards fixed, MinIO/Portainer verified:**

- **TrueNAS integration (partial — web UI only)**: TrueNAS is live at its
  static IP **10.0.0.5** and reachable at **https://truenas.kloud-worx.com**
  via the Cloudflare Tunnel, protected by the same Google OAuth Access policy
  as every other service (verified: unauthenticated requests to the public
  hostname 302 to the Access login page). TrueNAS uses a Cloudflare Origin
  Certificate (valid until 2041), so the tunnel's ingress rule sets
  `originRequest.noTLSVerify: true`. Added to `ansible/roles/cloudflare-tunnel/`
  (both `tasks/main.yml` ingress config and `defaults/main.yml` hostname
  lists) so it persists on future `make cloudflare` runs. Note: direct LAN
  access to `https://10.0.0.5` bypasses Access entirely (Cloudflare can't see
  traffic that never transits its edge) — investigated and confirmed this is
  expected/inherent to the tunnel architecture, not a misconfiguration;
  accepted as-is for a homelab. NFS/SMB shares, Longhorn backup target, and
  scheduled snapshots (the rest of roadmap item 1) are still not done.
- **Grafana dashboard fixes**: Longhorn, MinIO, and Node Exporter Full were
  all showing "No data" despite correct-looking gnetId config. Root causes
  varied — Longhorn/Node-Exporter-Full: the chart's dashboard-download sed
  substitution can't resolve modern per-panel object-form datasource refs
  (`${DS_PROMETHEUS}`); MinIO: a multi-select template variable
  (`job="$scrape_jobs"`) that could never exact-match. Fixed by hand-editing
  pre-resolved JSON (checked into `kubernetes/grafana-dashboards/`) loaded via
  ConfigMaps the `grafana-sc-dashboard` sidecar picks up — reordered in
  `ansible/playbooks/04-cluster-addons.yml` to run *before* the
  kube-prometheus-stack Helm upgrade (the sidecar only does a one-time
  initial sync at Grafana pod startup) and moved into the same "TuringPi"
  folder as every other dashboard via `folderAnnotation` +
  `foldersFromFilesStructure`. Verified end-to-end with a genuinely fresh
  Grafana pod, not just a config reload. All **8 dashboards** now live in the
  TuringPi folder with real data: Cilium, Gitea, K3S cluster monitoring,
  Longhorn (updated), MinIO Dashboard, NGINX Ingress controller, Node
  Exporter Full, kubernetes-persistent-volumes.
- **MinIO credentials**: `secret/minio` in Vault updated (confirmed via Vault
  KV metadata — version 2, updated today).
- **Portainer**: confirmed already operational at
  https://portainer.kloud-worx.com with known credentials stored in Vault —
  no changes needed (a proposed fix to pre-seed the admin password via
  `adminPassword.existingSecret` was evaluated and explicitly declined this
  session since Portainer already works and wiping its PVC to force
  reinitialization wasn't worth the disruption).

**July 12, 2026 — Storage strategy complete, Cluster 2 BMC static IP, Jetson Orin Nano configured:**

- **Storage strategy — COMPLETE**: TrueNAS datasets created
  (`SSDStorage/kubernetes`, `SSDStorage/kubernetes/longhorn-backups`,
  `SSDStorage/kubernetes/cluster-configs`); NFS export configured with hosts
  restricted to `10.0.0.11-13` (rk1-control/worker-1/worker-2 only), NFS
  service enabled and running on TrueNAS. Longhorn's backup target is now
  set to `nfs://10.0.0.5:/mnt/SSDStorage/kubernetes/longhorn-backups`. Vault
  has recurring Longhorn jobs — `vault-snapshot` + `vault-backup`, both
  daily at 2 AM, retain 7. New playbooks:
  `ansible/playbooks/03c-longhorn-backup-target.yml` and
  `ansible/playbooks/03d-longhorn-recurring-jobs.yml`. New role:
  `ansible/roles/truenas/`. This closes out the remaining TrueNAS
  integration work noted as pending in the July 10 entry above and in
  roadmap item 1 below.
- **Cluster 2 BMC — DONE**: `tpi2-bmc` now has a static IP, **10.0.0.20**
  (was `10.0.0.190` DHCP). CM4 node 1 booted at `10.0.0.231` but has an SSH
  key mismatch — **action needed**: reflash CM4 node 1's SD card with
  `~/.ssh/turingpi_homelab`, username `raj`, hostname `cm4-node-1`.
- **Jetson Orin Nano — CONFIGURED**: JetPack 7.2 (L4T 39.2.0) on Ubuntu
  24.04, installed on a 1TB NVMe. Static IP **10.0.0.50**, hostname
  `orin-nano`, user `raj` (`ssh raj@10.0.0.50`). MAXN_SUPER power mode
  active (67 TOPS) and persists across reboots; `jetson_clocks` is pinned at
  boot via a systemd service. 16GB swap configured on the NVMe. nvpmodel
  fix: `nvpmodel_p3767_0003_super.conf` must be **copied** (not symlinked)
  to `/etc/nvpmodel.conf`, or the MAXN_SUPER mode setting doesn't stick.
- **JetPack 7.2 ecosystem note (important)**: prebuilt Ollama and
  `dustynv`-container images don't work on this JetPack — CUDA 12.6 (what
  they're built against) vs CUDA 13.2 (what JetPack 7.2 ships) mismatch.
  `llama.cpp` must be built from source instead:
  `cmake -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=87`. Separately, `jtop`
  reports "JetPack NOT DETECTED" on this JetPack version — confirmed
  cosmetic only, all metrics (GPU/CPU/power/temp) read correctly despite
  the message.

**Pending next session:**
- Orin Nano: build `llama.cpp` from source (CUDA 13.2,
  `-DCMAKE_CUDA_ARCHITECTURES=87`)
- Orin Nano: mount the 5TB USB drive at `/mnt/backup-archive`
- Orin Nano: configure as a TrueNAS rsync target over SSH
- Orin Nano: install Open WebUI
- Cluster 1: shutdown → install the Orin NX module in slot 3 → test
  connectivity (re-tests whether slot 3's fault was hardware or leftover
  kubeadm/Tailscale artifacts — see roadmap item 2 below)
- CM4 cluster: reflash node 1's SD card (see SSH key mismatch above), boot
  the remaining nodes

**Next up:** the Orin Nano / CM4 / slot-3 items above — TrueNAS's storage
integration (roadmap item 1) is now fully complete.

---

**July 26, 2026 (planning) — Cluster 2 K3s bring-up plan (not yet implemented):**

All 4 CM4 nodes (`cm4-node-1` through `cm4-node-4`, 10.0.0.21-24) are now
confirmed reachable and stable, including surviving a full power-cycle test
— node 2's earlier SATA-cable/IPv6 issue is resolved. Planned approach
(reviewed, not yet applied to any files):

- **Isolated roles, not shared**: fork `ansible/roles/k3s-server/` and
  `ansible/roles/k3s-agent/` into new `k3s-server-cm4`/`k3s-agent-cm4`
  roles rather than parameterizing the existing ones — Cluster 1's roles
  stay byte-for-byte untouched. The cm4 copies drop the NVMe
  symlink/containerd-relocation logic (CM4 has no NVMe), hardcode
  `cm4-node-1` as the control host (no shared control-host variable), and
  hardcode `~/.kube/turingpi-cluster2.conf` as the kubeconfig output path.
- **CNI**: K3s installs with its **default Flannel** backend (no
  `--flannel-backend=none`, no Cilium) — Cluster 2 doesn't use Cilium.
- **Topology**: single control-plane (`cm4-node-1`), K3s default SQLite
  datastore (no HA needed), workers `cm4-node-2`/`cm4-node-3`/`cm4-node-4`.
- **Longhorn**: scoped to `cm4-node-3` only (its 2×1TB SATA drives) via a
  `longhorn.io/exclude=true:NoSchedule` taint on the other three nodes —
  the existing `ansible/roles/longhorn/` role itself stays unmodified,
  since its DaemonSet pods simply won't tolerate the custom taint.
- **MetalLB**: new standalone pool `10.0.0.60-10.0.0.69` (shrunk from the
  previously-reserved `10.0.0.50-10.0.0.69`, which conflicted with the
  Jetson Orin Nano's static `10.0.0.50` — see the flagged conflict in
  Network Layout below). No Ingress-NGINX/Prometheus/Headlamp/Portainer
  on Cluster 2 initially — services get direct LoadBalancer IPs.
- **New files planned**: `ansible/roles/k3s-server-cm4/`,
  `ansible/roles/k3s-agent-cm4/`, new `cm4_nodes`/`cm4_control`/
  `cm4_workers`/`cluster2` groups in `ansible/inventory/hosts.yml`
  (`ansible_user: raj`, not `ubuntu`), new
  `ansible/inventory/group_vars/cluster2.yml`, new playbooks
  `ansible/playbooks/20-cluster2-kubernetes.yml`,
  `21-cluster2-longhorn.yml`, `22-cluster2-metallb.yml`, and three new
  Makefile targets (`cluster2-k3s`, `cluster2-longhorn`,
  `cluster2-metallb`).
- **Explicitly not touched**: the `cluster2/` directory (per CLAUDE.md —
  it's a disconnected legacy stub, left as-is), `ansible/roles/k3s-server/`,
  `ansible/roles/k3s-agent/`, `04-cluster-addons.yml`, `02b-cilium.yml`,
  and every existing Cluster 1 inventory group.

**Picking this up next session**: implement the plan above (nothing has
been created yet — this is a plan-only checkpoint), then verify with
`KUBECONFIG=~/.kube/turingpi-cluster2.conf kubectl get nodes -o wide` and
confirm Longhorn pods only land on `cm4-node-3`.

---

**July 26, 2026 — PostgreSQL deployed for LiteLLM, Cluster 2 CM4 flashing breakthrough, Longhorn backup NFSv3 fix:**

- **PostgreSQL — COMPLETE**: PostgreSQL 16 deployed via new role
  `ansible/roles/postgresql/`, backed by a 5Gi Longhorn PVC in the `litellm`
  namespace. `PGDATA` is set to a subdirectory of the mount
  (`/var/lib/postgresql/data/pgdata`) to work around Longhorn always
  creating a `lost+found` directory at the volume root, which otherwise
  makes `initdb` refuse to run on a "non-empty" directory. Daily 2 AM
  recurring snapshot + backup jobs configured, retain 7 (same pattern as
  the Vault jobs). LiteLLM's `DATABASE_URL` is wired successfully — Prisma
  migration confirmed, the full `LiteLLM_*` schema was created in the
  database. **Still needed**: replace the placeholder
  `ANTHROPIC_API_KEY`/`GEMINI_API_KEY` values in Vault at `secret/llm-keys`
  with real keys, then build out LiteLLM teams/budgets for the client
  FinOps demo ($40/mo standard tier, $200/mo developer tier).
- **Cluster 2 — CM4 eMMC flashing breakthrough**: found a proven flashing
  method after prior attempts stalled — use the BMC web portal
  (`http://10.0.0.20`) → Flash Node → local upload of a **shrunk,
  pre-configured image** (not a vanilla OS image) → let it run
  uninterrupted for hours → switch the node to host mode → boot. Node 1
  (`cm4-node-1`, static `10.0.0.21`) and Node 3 (`cm4-node-3`, static
  `10.0.0.23`) are confirmed working with this method. **Correction (later
  the same session)**: all 4 CM4 nodes — `cm4-node-1` through
  `cm4-node-4` (`10.0.0.21`-`10.0.0.24`) — are now confirmed reachable and
  stable, including surviving a full power-cycle test; the note below
  about Node 2 being unreachable and Node 4 not yet flashed is stale.
  Node 2 (a CM5 Lite) had gone unreachable at `10.0.0.22` after a SATA
  cable disconnect plus an IPv6 change, but recovered after a power cycle.
  Node 4 is now flashed at `10.0.0.24`. **Gotchas learned**: the BMC portal's CRC-check
  progress display can look "stuck" near 100% while the flash is actually
  still succeeding in the background — don't cancel it; the `tpi` BMC CLI
  can hang or leave orphaned/stopped jobs if `Ctrl+Z` is hit by accident —
  exit and reconnect SSH rather than fighting the stuck job; a fully
  unresponsive BMC recovers cleanly from the physical BMC reset button.
  Node 2 has an mPCIe-to-SATA adapter with a 1TB SATA SSD attached, but the
  drive never gets detected (AHCI reports "SATA link down") — deferred,
  needs hands-on cable/power troubleshooting.
- **Longhorn backup fix**: the backup target URL was silently failing every
  Vault backup for weeks because TrueNAS has NFSv4 disabled and the
  original `nfs://` URL was negotiating (and failing) NFSv4. Fixed by
  forcing NFSv3 via `?nfsOptions=vers%3D3` on the backup target URL (see
  `ansible/inventory/group_vars/all/vars.yml` `longhorn_backup_target`).
  **Lesson**: always verify actual backups exist with
  `kubectl get backups.longhorn.io -n longhorn-system` — the RecurringJob
  and Volume-label objects existing is not proof that any backup ever
  actually succeeded.

**Next session priorities:**
- Implement the Cluster 2 K3s bring-up plan above (isolated `-cm4` roles,
  inventory groups, playbooks 20/21/22, Makefile targets — nothing built
  yet, plan-only checkpoint)
- ~~Recover Cluster 2 node 2~~ — resolved, all 4 CM4 nodes confirmed
  stable through a full power-cycle test
- Troubleshoot node 2's SATA drive connection (AHCI link-down) if still
  unresolved
- Replace the placeholder Anthropic/Gemini API keys in Vault
- Build LiteLLM teams/budgets for the client FinOps demo

**August 12-13, 2026 — Gitea CI Kaniko RBAC, custom act-runner image with kubectl, research-forum.kloud-worx.com onboarded, per-app Cloudflare Access policies:**

- **Gitea Actions runner RBAC extended for Kaniko builds**: `gitea-runner-rbac`
  Role gained `batch/jobs` (full CRUD) and `pods/log` (read-only) so CI
  pipelines in the separate `research-forum-app` repo can run in-cluster
  Kaniko build Jobs and stream their logs, scoped only to that Role — no
  other namespace or permission touched.
- **Custom `gitea-act-runner` image with `kubectl` baked in**: the runner's
  job-step shell turned out to have no `curl`/`wget`/package manager/kubectl
  at all, blocking `deploy.yml`. Built `ansible/roles/gitea/files/Dockerfile.act-runner-kubectl`
  (Alpine 3.23.4 base, confirmed via `docker run --rm --entrypoint cat
  gitea/act_runner:latest /etc/os-release`) that adds `kubectl` v1.30.5 via
  `wget` (already present in the base image). Built and pushed from
  parani-laptop's Docker Desktop to the Gitea registry at LAN address
  `10.0.0.36:3000` (outside-cluster push address), while the in-cluster
  Deployment pulls the same image via that same LAN IP — image-pull happens
  at the kubelet/containerd layer, which resolves via the node's host DNS,
  not CoreDNS, so `*.svc.cluster.local` names are unusable there. Hit and
  fixed three layered `ImagePullBackOff` causes in sequence: DNS resolution
  (switched to LAN IP), `imagePullSecrets` `--docker-server` mismatch (had
  to match the image ref's host:port exactly), and HTTP-vs-HTTPS (containerd
  defaults to HTTPS for unknown registries; Gitea serves plain HTTP — fixed
  via `/etc/rancher/k3s/registries.yaml` mirror config on all 3 nodes,
  `ansible/playbooks/06-dev-tools.yml`, requiring a `k3s`/`k3s-agent`
  service restart to reload since registries.yaml is only read at
  containerd startup). Verified both runner replicas `Running` with a
  working `kubectl exec ... -- kubectl version --client`.
- **`research-forum.kloud-worx.com` added to the Cloudflare Tunnel**, with
  its own independent Access Application + Policy ("Allow Research Forum
  App team") separate from the shared single-email
  `cloudflare_access_allowed_email` path used by the other 8 tools — new
  `ansible/roles/cloudflare-tunnel/tasks/research-forum-access.yml`.
- **`gitea.kloud-worx.com` split off the shared Access policy into its own**,
  matching the research-forum pattern (`gitea-access.yml`), so
  `pamulliving@gmail.com` could be granted access to Gitea only, without
  touching the other 8 shared-policy tools. Because gitea's Access
  Application + single-email Policy already existed from prior shared-loop
  runs, this updates the existing Policy **in place** (`PUT`, full-object
  replace preserving `decision`/`session_duration`) rather than creating a
  duplicate — verified live via the Cloudflare API that `created_at` stayed
  the same while `updated_at` changed, confirming a true in-place update.
- **Three more emails added to the research-forum Access policy**
  (`kdougl1@uic.edu`, `nkstout@uic.edu`, `sydelleb@uic.edu`, alongside the
  original two), and `research-forum-access.yml` was extended with the same
  idempotent PUT-if-emails-differ logic gitea-access.yml already had — it
  previously only handled first-time creation and would have silently done
  nothing on a re-run with new emails. Verified live: same policy `id`/
  `created_at`, `include` now has all 5 emails.
- **Mixed-content fix on `research-forum.kloud-worx.com`**: Ingress-NGINX
  wasn't honoring `X-Forwarded-Proto` from cloudflared (which connects
  internally over plain HTTP), so it recomputed the scheme itself and
  overwrote `https` with `http` before the app saw it. Fixed with one Helm
  flag, `--set controller.config.use-forwarded-headers="true"`, added to
  the "Install Ingress-NGINX" task in `ansible/playbooks/04-cluster-addons.yml`
  and applied live (confirmed via `kubectl get configmap`).

**August 14-15, 2026 — rf-pre-event-app onboarded with isolated RBAC and Cloudflare Access:**

- **New Gitea Actions runner RBAC for `rf-pre-event-app`**, a second Laravel
  companion app to research-forum-app. Rather than parameterize the existing
  `gitea-runner-rbac` role (namespace/SA name are hardcoded there), added a
  parallel role `ansible/roles/gitea-runner-rbac-rf-pre-event/` — own
  namespace `rf-pre-event-app`, own `gitea-runner-deployer`
  ServiceAccount/Role/RoleBinding, own durable SA-token kubeconfig
  (`~/.kube/turingpi-cluster1-rf-pre-event-app.conf`) — fully isolated from
  research-forum-app's resources. `batch/jobs` and `pods/log` permissions
  were included in the Role from the start this time, since they had to be
  retrofitted for research-forum-app last session. New playbook
  `ansible/playbooks/15-gitea-runner-rbac-rf-pre-event.yml` and Makefile
  target `gitea-runner-rbac-rf-pre-event`.
- **`rf-pre-event.kloud-worx.com` added to the Cloudflare Tunnel**, routing
  to `ingress-nginx-controller.ingress-nginx.svc.cluster.local:80`, with its
  own independent Access Application + Policy ("Allow RF Pre-Event App
  team") covering the same five emails as research-forum-app
  (`rajesh.pamulapati@gmail.com`, `pamulliving@gmail.com`,
  `kdougl1@uic.edu`, `nkstout@uic.edu`, `sydelleb@uic.edu`) — new
  `ansible/roles/cloudflare-tunnel/tasks/rf-pre-event-access.yml`, built
  from the start with the idempotent update-in-place PUT logic (no
  first-run-only gap to retrofit, unlike research-forum-access.yml
  originally).
- Verified live: `research-forum-app` namespace/RBAC/Access policy
  unchanged (same `created_at` timestamps, existing secrets intact);
  `rf-pre-event-app` got its own namespace/SA/Role/RoleBinding/token Secret
  and its own Cloudflare Access Application; both new make targets are
  idempotent on re-run (no changes on second pass). Kubeconfig for
  `rf-pre-event-app`'s deployer output for manual paste into that repo's
  Gitea Actions secrets — actual app Deployment/Ingress/Service manifests
  are left to that repo's CI, same as research-forum-app.

**August 16, 2026 — rpc-statd + Longhorn NFS lock fixes (backups unstuck):**

Longhorn NFS backups were still not completing despite the July 26, 2026
NFSv3-forcing fix (`?nfsOptions=vers%3D3`). Investigation found two separate,
stacked root causes:

- **Root cause 1 — rpc-statd not persistent on rk1-control.** All three RK1
  nodes need `rpc.statd` (the NFSv3 lock manager) enabled at boot for NFS
  client mounts to keep lock support across a reboot. Both worker nodes
  already had it `static`/active, but rk1-control only had it running
  transiently — not `enabled` — so it silently reverted after any reboot.
  Fixed manually first:
  ```bash
  sudo mkdir -p /etc/systemd/system/remote-fs.target.wants
  sudo ln -sf /lib/systemd/system/rpc-statd.service /etc/systemd/system/remote-fs.target.wants/rpc-statd.service
  sudo systemctl daemon-reload
  ```
  then codified as an idempotent task in `ansible/roles/common/tasks/main.yml`
  (`ansible.builtin.systemd: name: rpc-statd, enabled: true, state: started`)
  so it applies to all three RK1 nodes on every `make common` run and survives
  a future reflash.
- **Root cause 2 — `longhorn-manager` pods can never see the host's rpc-statd
  fix.** Even with rpc-statd correctly enabled on every node, backups still
  failed lock registration, because `longhorn-manager` pods run without
  `hostNetwork` and have no `rpcbind`/`rpc.statd` inside their own network
  namespace — no host-level fix can ever reach an NFSv3 mount performed from
  inside that pod. The actual fix was adding `nolock` to the backup-target's
  `nfsOptions`, updating
  `ansible/inventory/group_vars/all/vars.yml`'s `longhorn_backup_target` from
  `...?nfsOptions=vers%3D3` to `...?nfsOptions=vers%3D3,nolock`, then
  re-applying via `make longhorn-backup-target` (patches the Longhorn
  `settings.longhorn.io backup-target` CRD; see
  `ansible/roles/longhorn/tasks/backup-target.yml`).

**Lessons learned:**
- Leader-election-based controllers (Longhorn's manager runs one active
  instance via leader election) mean a host-level symptom can look like it
  depends on whichever node currently holds leadership — root cause 1 was
  only visible on rk1-control today. But the underlying fix still needs to
  ship cluster-wide, not just to today's leader: leadership moves on the next
  restart/failover, and an unpatched node becoming leader next time would
  reintroduce the exact same failure.
- A host-level fix can look completely correct while the actual failure is
  still happening inside a container's isolated network namespace. rpc-statd
  being `enabled` and `active` on every node was not sufficient proof the bug
  was fixed — it only became clear once verified from the actual failure
  point (the `longhorn-manager` pod's own NFSv3 mount attempt), not just from
  host-level `systemctl`/`rpcinfo` state.

Verified: `systemctl is-enabled rpc-statd` returns `enabled` on all three RK1
nodes; `kubectl -n longhorn-system get settings.longhorn.io backup-target -o
jsonpath='{.value}'` reflects the `,nolock` value; `kubectl get
backups.longhorn.io -n longhorn-system` shows backups actually completing,
not just the RecurringJob/Volume-label objects existing (same verification
discipline as the July 26 lesson above).

**August 16, 2026 — Cluster 2 (CM4) K3s build implemented and applied live
(four bugs found and fixed, SATA storage added on cm4-node-3):**

Implemented the "Cluster 2 K3s bring-up plan" from the July 26, 2026 (planning)
entry above — single control-plane on `cm4-node-1` (K3s default SQLite
datastore), default Flannel CNI, workers `cm4-node-2`/`cm4-node-3`/
`cm4-node-4`, Longhorn scoped to `cm4-node-3` only, MetalLB pool
`10.0.0.60-10.0.0.69`. Fully isolated from Cluster 1 — forked (not
parameterized) roles, separate inventory groups, separate playbooks, separate
kubeconfig.

- **New forked roles** `ansible/roles/k3s-server-cm4/` and
  `ansible/roles/k3s-agent-cm4/`, copied from `k3s-server`/`k3s-agent` with:
  NVMe-symlink relocation logic dropped (no NVMe on CM4), `--flannel-backend=none`/
  `--disable-network-policy` dropped (default Flannel), `delegate_to: rk1-control`
  → `delegate_to: cm4-node-1` hardcoded, kubeconfig fetched to
  `~/.kube/turingpi-cluster2.conf`. Cluster 1's `k3s-server`/`k3s-agent` roles
  are untouched — confirmed via `git diff` showing zero changes to either.
- **New inventory groups** `cm4_nodes`/`cm4_control`/`cm4_workers`/`cluster2`
  in `ansible/inventory/hosts.yml`, plus a new
  `ansible/inventory/group_vars/cluster2.yml` for cluster2-scoped vars
  (`k3s_version_cluster2`, `k3s_server_ip_cluster2`,
  `longhorn_replica_count_cluster2: 1`, etc.). `metallb_ip_range_cluster2` in
  the shared `all/vars.yml` corrected from `10.0.0.50-10.0.0.69` to
  `10.0.0.60-10.0.0.69` — `.50` is now the Orin Nano's static IP (claimed in a
  later session than when that var was originally written).
- **Bug caught during implementation**: the forked roles and new playbooks
  build paths like `/home/{{ admin_user }}/.kube/config`, but `admin_user`
  resolves globally to `"ubuntu"` (from `all/vars.yml`) — wrong for CM4 hosts,
  which use `ansible_user: raj`. Fixed by using `{{ ansible_user }}` directly
  in the new roles/playbooks instead of `admin_user`, and — since the reused
  `longhorn` role's own tasks hardcode `{{ admin_user }}` internally, not
  inherited from the calling play's `environment:` block — overriding
  `admin_user: "{{ ansible_user }}"` at the play `vars:` level in
  `21-cluster2-longhorn.yml` so the unmodified role still resolves the right
  path. Confirmed via `ansible-inventory --host cm4-node-3` showing
  `ansible_user: raj` vs. `admin_user: ubuntu` side by side before the fix.
- **Longhorn scoping — corrected approach**: initially planned a
  `longhorn.io/exclude=true:NoSchedule` taint on the three non-storage nodes,
  but that's not a Longhorn-recognized key and a generic `NoSchedule` taint
  would have blocked all workloads (not just storage) from those nodes.
  Corrected to Longhorn's actual documented mechanism: label `cm4-node-3` with
  `node.longhorn.io/create-default-disk=true` and set the Longhorn Setting
  `create-default-disk-on-labeled-nodes=true` (`21-cluster2-longhorn.yml`).
  All 4 nodes remain fully schedulable for general workloads — no taints
  applied anywhere.
- **New playbooks**: `20-cluster2-kubernetes.yml` (OS prep + K3s server/agent),
  `21-cluster2-longhorn.yml` (label + Longhorn install via the existing,
  unmodified `longhorn` role), `22-cluster2-metallb.yml` (MetalLB +
  `cluster2-pool`/`cluster2-l2`). New Makefile targets `cluster2-k3s`,
  `cluster2-longhorn`, `cluster2-metallb`.
- **Known gap, flagged not silently omitted**: `20-cluster2-kubernetes.yml`'s
  OS-prep play only forks in the swap-disable fix from the `common` role
  (Cluster 1's documented kubelet-crash-on-reboot incident) — it does **not**
  apply UFW, fail2ban, chrony, or any other `common`-role hardening to
  `cm4_nodes`, since the full `common` role is Cluster-1-scoped
  (`hosts: rk1_nodes`). CM4 nodes currently have no firewall/fail2ban/NTP
  hardening. Tracked as a follow-up below, not a silent omission.
- **All YAML/playbook syntax validated** (`ansible-playbook --syntax-check`
  on all three new playbooks, `ansible-inventory --graph` confirms the new
  group nesting).

**Live deployment — four bugs found, all fixed and folded back into the code:**

1. **`open-iscsi` and `ufw` missing on CM4 nodes.** `longhorn-manager`
   crash-looped with `"Failed environment check... iscsiadm not found"` —
   Longhorn needs `iscsiadm` on the host for iSCSI-backed volume attachment.
   Separately, `k3s-server-cm4`'s "Allow K3s API server port through UFW" task
   failed outright because `ufw` wasn't installed. Both packages are normally
   installed by Cluster 1's `common` role, which `cm4_nodes` never runs. Fixed
   by forking in `open-iscsi` install + `iscsid` enable, and a plain `ufw`
   package install, into `20-cluster2-kubernetes.yml`'s OS-prep play.
2. **CM4/CM5 nodes need `cgroup_memory=1 cgroup_enable=memory` on the kernel
   cmdline.** Without it, k3s fails to start with `"failed to find memory
   cgroup (v2)"` — this is a Raspberry Pi/CM-family default (cgroup v2 memory
   controller isn't enabled by default the way it is on generic ARM server
   images). Fixed with an idempotent check-append-reboot task in
   `20-cluster2-kubernetes.yml`, placed last in the OS-prep play (only reboots
   once, after all other package installs).
3. **Wrong Longhorn Setting name, and a real ordering bug, not just a typo.**
   `create-default-disk-on-labeled-nodes` doesn't exist in Longhorn v1.6.2 —
   confirmed via `helm show values longhorn/longhorn --version 1.6.2` (run
   identically from both rk1-control and cm4-node-1, byte-for-byte matching
   output) that the real key is `create-default-disk-labeled-nodes`
   (`defaultSettings.createDefaultDiskLabeledNodes` in Helm values). Beyond
   the name, a `kubectl patch settings.longhorn.io` run as a `post_tasks` step
   *after* `helm upgrade --install ... --wait` is fundamentally too late — by
   the time `--wait` returns, longhorn-manager pods are already Ready and have
   already run their default-disk auto-creation logic once per node. Fixed by
   moving the setting into the Helm chart's own `defaultSettings` block
   (`ansible/roles/longhorn/tasks/main.yml`, one new Jinja-conditional line,
   gated on a var that's undefined — and therefore a no-op — for every
   Cluster 1 invocation), applied atomically at chart-install time with zero
   race window, instead of a racy post-install patch.
4. **Consequence of #3: all 4 nodes got an auto-created eMMC/SD-backed
   default Longhorn disk before the fix landed.** Removed by hand from
   `cm4-node-1`/`cm4-node-2`/`cm4-node-4`: `allowScheduling: false` +
   `evictionRequested: true` first, *then* delete — Longhorn's admission
   webhook rejects deleting a disk that's still schedulable, and (separately)
   a single empty-object `kubectl patch` is a no-op under JSON Merge Patch
   semantics (merging `{}` into an existing key changes nothing) — the disk
   key itself has to be explicitly set to `null` to remove it. The corrected
   playbook (fix #3) prevents this from recurring on any future
   `make cluster2-longhorn` run or reflash.

**New: SATA storage added on cm4-node-3.** Two unmounted 1TB SATA SSDs
(`/dev/sda` "Inland SATA SSD", `/dev/sdb` "P3-1TB") alongside the 14.6GB eMMC
boot disk. Decision: used as **two separate Longhorn disks, not RAID1** — with
TrueNAS backups already in place and a weekly retention purge planned,
disk-level redundancy isn't worth the write-amplification/capacity cost for
this homelab. Before formatting, verified with `file -s /dev/sda1` (byte-for-byte
raw output shown to and confirmed by the user) that its existing partition
already had a valid, essentially-empty ext4 filesystem (only `lost+found`,
2.1MB used of 938GB) — mounted as-is via its existing UUID rather than
reformatted; only `/dev/sdb` needed partitioning + formatting. Both mounted
persistently via `/etc/fstab` using `UUID=...` (not `/dev/sda`/`/dev/sdb`
device names, which can shift across reboots) at `/mnt/sata1`/`/mnt/sata2`,
registered as `sata1-disk`/`sata2-disk` in Longhorn's `node.longhorn.io`
CR for `cm4-node-3`, and the eMMC default disk explicitly set to
`allowScheduling: false` — kept OS-only, no longer eligible for replica data
now that ~1.9TB of real storage exists. All of `21-cluster2-longhorn.yml`'s
new tasks are idempotent (`community.general.parted`/`filesystem` no-op on an
already-correct partition/filesystem, `ansible.posix.mount` no-ops on an
already-correct fstab entry).

**Caught and resolved: cross-cluster nfs-provisioner dependency.** The shared
`longhorn` role's `main.yml` unconditionally installs an `nfs-provisioner`
Helm release pointed at `nfs_server_ip`/`nfs_export_path` — both Cluster-1-only
globals (rk1-worker-1's NFS export). Since `21-cluster2-longhorn.yml` reuses
this same role, Cluster 2 would silently have gotten an `nfs-provisioner`
release pointing cross-cluster at Cluster 1's NFS server. Fixed with the same
conditional-var pattern as `createDefaultDiskLabeledNodes`: both NFS-provisioner
tasks in the role gated behind `when: longhorn_install_nfs_provisioner |
default(true)` (Cluster 1 never sets it, so it defaults `true` — unchanged
behavior there), and `21-cluster2-longhorn.yml` sets
`longhorn_install_nfs_provisioner: false`. Cluster 2 doesn't need NFS-backed
storage — the two SATA disks on `cm4-node-3` above cover its storage need.

**Caught and resolved: vault-volume label failure + a deeper tag-gating
misunderstanding.** The next `21-cluster2-longhorn.yml` run failed at "Label
Vault volume for vault-snapshot and vault-backup recurring jobs" —
`ansible/roles/longhorn/tasks/recurring-jobs.yml` hardcodes Cluster 1's vault
PVC ID (`longhorn_vault_volume`) and labels it unconditionally; Cluster 2 has
no volumes yet, so it failed with `NotFound`. Root cause turned out to be
deeper than one unguarded task: both `recurring-jobs.yml` and
`backup-target.yml` are included from the role's `main.yml` behind
`tags: [...]`, with comments claiming they "only run when `--tags` is
explicitly requested." **That's a misunderstanding of Ansible tag
semantics** — tags only filter execution when `--tags`/`--skip-tags` is
explicitly passed on the CLI; absent that flag (true for
`21-cluster2-longhorn.yml`, and also true for Cluster 1's own
`03-storage.yml`/`03b-longhorn-nvme.yml`), every task runs regardless of its
tag. This means `backup-target.yml` had *also* already silently run against
Cluster 2 — and since a `kubectl patch settings.longhorn.io backup-target`
doesn't `NotFound` the way the volume label did, it succeeded silently,
leaving Cluster 2's `backup-target` Setting pointed at Cluster 1's exact
TrueNAS path (confirmed live before the fix:
`nfs://10.0.0.5:/mnt/SSDStorage/kubernetes/longhorn-backups?nfsOptions=vers%3D3,nolock`,
byte-for-byte Cluster 1's URL).

Fixed both `include_tasks` calls in `main.yml` with real `when:` gates
(`longhorn_configure_backup_target`/`longhorn_configure_vault_recurring_jobs`,
both defaulting `true` — Cluster 1 unaffected) and corrected the stale
comments. **Design decision**: rather than disabling Cluster 2's backup
target outright, gave it its own distinct TrueNAS path —
`nfs://10.0.0.5:/mnt/SSDStorage/kubernetes/longhorn-backups-cluster2?nfsOptions=vers%3D3,nolock`
(new `longhorn_backup_target_cluster2` var in `cluster2.yml`, overriding
`longhorn_backup_target` at the play level in `21-cluster2-longhorn.yml`) —
so two independent Longhorn installations never write backups to the same NFS
directory. Vault recurring-jobs stays disabled for Cluster 2
(`longhorn_configure_vault_recurring_jobs: false`) — it has no Vault or
Postgres volumes to snapshot/back up, so the RecurringJob CRs would be inert,
misleading dead config.

**Manual prerequisite — done**: the `longhorn-backups-cluster2` directory/NFS
export was created on TrueNAS (`https://10.0.0.5`) before the next
`make cluster2-longhorn` run, mirroring `longhorn-backups` (Cluster 1's
existing export). Confirmed live below — the backup-target patch succeeded
and the readback assert passed against the new `-cluster2` path.

Because the playbook failed before reaching the SATA disk setup plays (later,
separate top-level plays in the same file), those never ran on the previous
attempt.

**Caught and resolved: Longhorn admission-webhook race between back-to-back
disk patches.** The next attempt (after the TrueNAS `longhorn-backups-cluster2`
export was created) reached the SATA disk plays and got further, but
"Add sata2-disk to cm4-node-3" was rejected by Longhorn's admission webhook:
`"spec and status of disks on node cm4-node-3 are being syncing and please
retry later"` — the `sata1-disk` patch immediately before it kicks off
reconciliation that hadn't finished before the next patch landed. Fixed with a
retry loop (`register`/`until`/`retries: 6`/`delay: 10`, ~60s headroom) on the
`sata2-disk` and eMMC-disable patch tasks, rather than a blind fixed pause —
retries exactly as long as needed. **Confirmed idempotent**: `sata1-disk`
(already applied from the prior run) re-applied cleanly as a no-op merge
patch; the eMMC-disable task actually hit the race on this run too
(`FAILED - RETRYING... (6 retries left)`, succeeded on the second attempt),
confirming the fix works for real, not just in theory.

**Live run now fully completed** (`PLAY RECAP: failed=0` on both `cm4-node-1`
and `cm4-node-3`). Final state, verified directly:
- `backup-target`: `nfs://10.0.0.5:/mnt/SSDStorage/kubernetes/longhorn-backups-cluster2?nfsOptions=vers%3D3,nolock`
- No RecurringJobs on Cluster 2 — also found and deleted two stray
  `vault-backup`/`vault-snapshot` RecurringJob CRs left over from before the
  `longhorn_configure_vault_recurring_jobs: false` gate was added (created
  33 minutes earlier, inert — `groups: []`, no volumes ever labeled — but
  contradicted the decision that Cluster 2 shouldn't have them at all).
- `cm4-node-3` disk status (`kubectl get nodes.longhorn.io ... -o
  jsonpath='{.status.diskStatus}'`): `default-disk-3031f08ccc92ad69`
  (`allowScheduling: false`, `Ready`/`Schedulable` both `True` — OS-only, as
  intended), `sata1-disk` and `sata2-disk` (`allowScheduling: true`,
  `Ready`/`Schedulable` both `True`, ~938GB available each — ~1.9TB total
  schedulable storage). `df -h` on `cm4-node-3` confirms both mounts live.

Cluster 2's storage layer (K3s, Longhorn scoped to `cm4-node-3`, MetalLB,
SATA disks, isolated backup target) is now fully deployed and verified.

**Not done this session** (explicitly out of scope): no observability
workloads (Prometheus/Grafana/Loki) on Cluster 2 yet — storage-layer prep
only. See roadmap item 5 below, which still tracks the CM4
UFW/fail2ban/chrony hardening gap as a separate, still-open follow-up.

**August 17, 2026 — rk1-control's containerd/k3s + Longhorn eMMC disk
migrated to NVMe:**

Cluster 1's sole control-plane node (`rk1-control`, no HA) had its
`/dev/nvme0n1` sitting completely raw and unpartitioned since the original
worker migrations, per an open follow-up in this file. Investigated first
(not assumed) exactly how `rk1-worker-2`'s proven NVMe migration worked, since
the goal was to reuse that exact mechanism, not a superficially-similar new
one:

- The eMMC-usage root cause on the workers was mostly a leftover kubeadm-era
  `containerd.service` (K3s embeds its own containerd; this one was dead
  weight) — already fixed on `rk1-control` by the `common` role, confirmed
  live (`masked`/`inactive`, `/var/lib/containerd` doesn't exist).
- The actual `/var/lib/rancher` → NVMe move is a **symlink**, not a
  bind-mount — but the codified Ansible logic in `k3s-server`/`k3s-agent`
  only prevents *regression* on a fresh install (`when: not
  item.stat.exists`); the original data move on the workers was done by
  hand, once, and was never written as a reusable Ansible task anywhere.
  This session wrote that missing step for the first time.
- NVMe formatting is **whole-disk `mkfs.ext4`, no partition table**, mounted
  via a **LABEL-based** (not UUID-based) fstab entry — confirmed live on
  `rk1-worker-2` before replicating, to genuinely match the proven pattern
  (this differs from the UUID-based approach used for Cluster 2's SATA disks
  the day before, which was UUID by a separate explicit decision for that
  work).
- `03b-longhorn-nvme.yml` hardcodes the two workers by literal hostname —
  rather than risk that already-proven path, wrote a new, separate,
  `rk1-control`-only playbook (`ansible/playbooks/03e-rk1-control-nvme.yml`)
  using the identical mechanism, split into four independently-tagged phases
  (`rk1c-nvme-format`, `rk1c-nvme-migrate-rancher`,
  `rk1c-nvme-register-disk`, `rk1c-nvme-evict-emmc`) run one at a time with
  explicit approval between each — not as a single unattended script, given
  the single-point-of-failure risk.

**Pre-flight risk check, done before touching anything**: confirmed
`vault-0` is **not** scheduled on `rk1-control` (it's on `rk1-worker-1`,
unaffected) — only `vault-agent-injector` (the sidecar webhook, not Vault
itself) is on this node. Real single-replica exposure found instead:
`coredns`, `ingress-nginx-controller`, and `litellm` each have their only
instance on `rk1-control`. In practice, stopping/starting `k3s.service`
didn't even restart these pods — containerd's shim processes survived the
brief outage (`RESTARTS`/`AGE` on all three were unchanged afterward) — a
gentler outcome than planned for.

**All four phases completed successfully**:
1. NVMe formatted/mounted — matches `rk1-worker-2` exactly (`ext4`,
   `LABEL=longhorn-nvme`, no partition, `/var/lib/longhorn-nvme`).
2. `/var/lib/rancher` migrated: stopped `k3s.service`, `rsync -a` to NVMe,
   old directory renamed (not deleted) to `/var/lib/rancher.bak-<timestamp>`
   as a rollback safety net, symlinked, `k3s.service` restarted. Verified
   with `sudo du -sh` (permission-denied without sudo badly undercounted the
   first check) — both copies **8.7G**, byte-for-byte match; file count
   differed by ~196 (~0.17%), almost certainly transient socket/PID files
   present only while k3s was running, not real data loss.
   - **Bug found and fixed live**: the readiness-check task's jsonpath
     quoting broke under `ansible.builtin.command`'s `shlex` parsing (which
     strips quote characters appearing mid-argument, turning
     `@.type=="Ready"` into invalid `@.type==Ready`) — switched to
     `ansible.builtin.shell` with proper quoting, tested directly over SSH
     before re-running. Re-run was a clean no-op on the already-completed
     risky steps (symlink guard) and passed the readiness check correctly.
3. `nvme-disk` registered in Longhorn on `rk1-control` — `Ready`/`Schedulable`
   both `True`, ~997GB available.
4. eMMC disk (`default-disk-c198b0f7bc4dffa4`) disabled + eviction
   requested. **The previously-recorded Longhorn bug on this exact node
   (`open /var/log/instances/<name>.log: no such file or directory`, which
   forced a revert last time) did not recur** — `/var/log/instances` already
   existed live (a fix added after that earlier failed attempt), and this
   time both replicas migrated cleanly to `rk1-worker-1`/`rk1-worker-2` with
   zero volume degradation throughout (watched live via
   `kubectl get volumes.longhorn.io` during the eviction, not just the final
   result).

**Result**: `rk1-control`'s eMMC usage dropped **63% → 49%** (17G → 14G).
Smaller than `rk1-worker-2`'s 86%→35% since the `containerd.service` cleanup
had already happened here; most of the remaining gap is the still-present
`/var/lib/rancher.bak-20260816T235021` (8.7G) — left on eMMC deliberately, not
auto-deleted, for manual removal once stability is confirmed over the next
few days.

Verified end state: all 3 nodes `Ready`; all 9 Longhorn volumes
`healthy`/`attached` throughout, zero degradation; `rk1-control`'s eMMC disk
shows `allowScheduling: false`, `evictionRequested: true`, 0 replicas
remaining; `nvme-disk` `Ready`/`Schedulable`.

**Follow-up — resolved (checked August 23, 2026)**: went to remove
`/var/lib/rancher.bak-20260816T235021` from `rk1-control` manually, but it
was already gone — `sudo find /var/lib -maxdepth 1 -iname "rancher*"` on the
node shows only the live `rancher` symlink, no `.bak-*` directory. Not clear
who/what removed it or when; eMMC usage is now 29% (`/dev/mmcblk0p2`, down
from 49% recorded right after the migration), consistent with it being gone.
Nothing left to do here.

---

**August 22, 2026 — cloudflared CrashLoopBackOff on rk1-control fixed
(QUIC/UDP failure, not a probe-tuning issue):**

Flagged as a pre-existing, unrelated issue during the August 17 rk1-control
NVMe migration (787+ restarts at the time) — investigated and fixed as its
own task. Root cause, confirmed via logs on the crashing pod:

- cloudflared's own startup connectivity precheck found QUIC/UDP broken on
  this pod/node's network path — `UDP Connectivity FAIL` ("QUIC connection
  failed" / "handshake did not complete in time") against both Cloudflare
  edge regions, while `TCP Connectivity PASS` (HTTP/2) succeeded cleanly. A
  supporting log line pointed at a Linux UDP receive-buffer ceiling quic-go
  needs (`wanted: 7168 kiB, got: 416 kiB`) as the likely proximate cause,
  though the exact reason this pod/node fails QUIC while the other replica
  (on `rk1-worker-1`) doesn't was not root-caused further than that.
- The precheck itself says "Environment ready with degraded transport.
  cloudflared will proceed using 'http2'" — but only *after* it's already
  spent time retrying QUIC handshakes with exponential backoff against a
  rotating list of edge IPs. The Deployment's `livenessProbe` (`/ready` on
  port 2000, `initialDelaySeconds: 10`, Kubernetes' unspecified defaults for
  `periodSeconds`/`failureThreshold` — ~40s total grace, not the 60s
  originally assumed) killed the container before it ever fell through to
  HTTP2. **This was a protocol-selection problem, not a probe-tuning
  problem** — do not mistake this for something fixable by loosening the
  liveness probe; that would just prolong the outage window without fixing
  the actual cause.
- Fix: added `protocol: http2` as a top-level key to cloudflared's
  `config.yaml` (embedded ConfigMap content in
  `ansible/roles/cloudflare-tunnel/tasks/main.yml`), a documented cloudflared
  config key (values: `auto`/`http2`/`quic`) confirmed against [Cloudflare's
  Tunnel run-parameters
  docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/)
  before applying. This skips QUIC negotiation entirely instead of racing it
  against the liveness probe.
- Applied live: re-ran the `cloudflare-tunnel` role, `kubectl rollout
  restart deployment cloudflared`. Logs post-restart show `Initial protocol
  http2` and all 4 tunnel connections registering on `protocol=http2` within
  3 seconds — the async precheck still runs afterward and still reports the
  same QUIC/UDP failure (unrelated network condition, unfixed and not
  necessary to fix), but no longer blocks startup since HTTP2 was already
  selected up front. Both replicas held `1/1 Running`, 0 restarts, for 5+
  minutes of observation; confirmed `https://vault.kloud-worx.com` still
  routes through the tunnel (302 to Access login) after the restart.
- **Sysctl recommendation (not implemented)**: raising
  `net.core.rmem_max`/`wmem_max` on `rk1-control` might let QUIC work again
  later, but was declined for now — HTTP2 is fully functional for Cloudflare
  Tunnel (QUIC's only advantage is latency, not correctness), and there's no
  confirmation yet that the buffer size is the only blocker (a NAT/firewall
  UDP restriction is equally plausible). Flagged as an optional future
  follow-up, not bundled into this fix.
- **Separately noted, not fixed**: cloudflared's config also sets
  `credentials-file: /etc/cloudflared/creds/credentials.json`, but the
  Deployment has no volumeMount for that path — only `/etc/cloudflared/config`
  is mounted, and auth actually happens via the `TUNNEL_TOKEN` env var. This
  line appears to be dead/unused config; left as-is since it's unrelated to
  this crash.

---

**August 23, 2026 — Prometheus disk-full CrashLoopBackOff fixed (retention
config, not just storage expansion):**

`prometheus-monitoring-kube-prometheus-prometheus-0` had been
`CrashLoopBackOff` for 11 days (3204+ restarts). Confirmed via
`kubectl logs --previous`: `write /prometheus/queries.active: no space left
on device` — the 20Gi Longhorn-backed PVC was completely full, so Prometheus
couldn't even start (never got far enough to run its own TSDB retention
sweep).

- **Root cause**: `kubernetes/helm-values/prometheus-stack.yml` set
  `retention: 15d` with **no `retentionSize`** — a purely time-based cap
  with no size-based backstop. Nothing stopped ingestion from overshooting
  the 20Gi volume before the 15-day window could naturally cycle out old
  blocks. This is a configuration gap, not a one-off fluke — expanding the
  PVC alone would only have delayed the same failure recurring.
- **Fix**: changed `retention: 15d` → `7d` and added `retentionSize: "15GB"`
  as an explicit hard cap on the same 20Gi PVC (~25% headroom for WAL/
  compaction overhead). Verified `"15GB"` against the format both the
  Prometheus Operator's live CRD schema
  (`kubectl get crd prometheuses.monitoring.coreos.com` →
  `spec.retentionSize.pattern: (^0|([0-9]*[.])?[0-9]+((K|M|G|T|E|P)i?)?B)$`)
  and Prometheus's own `--storage.tsdb.retention.size` flag docs require,
  before applying — same diligence as the earlier Longhorn Helm-key
  verification.
- **PVC wipe**: since Prometheus couldn't start at all under the full old
  data (monitoring/metrics only, not app state, and this instance is being
  migrated to Cluster 2 soon anyway — data loss accepted), the fix required
  scaling down and deleting the PVC for a clean restart. **Scaling the
  `StatefulSet` to 0 alone did not work** — the Prometheus Operator
  reconciles the StatefulSet's replica count from the `Prometheus` CR and
  silently restored it to 1, remounting the PVC before it could delete.
  The correct approach: `kubectl patch prometheus
  monitoring-kube-prometheus-prometheus --type=merge -p
  '{"spec":{"replicas":0}}'` (patching the **CR**, not the StatefulSet)
  actually stops the pod for good; then `kubectl delete pvc ...` completes
  cleanly (StatefulSet's `volumeClaimTemplate` recreates a fresh PVC
  automatically once replicas is patched back to 1 — no manual PV/Longhorn
  volume manipulation needed).
- **Hit the same known Longhorn eMMC/`/var/log/instances` bug again**, this
  time on a brand-new replica scheduled to `rk1-control`'s `nvme-disk`
  (first replica placed there since the August 17 eviction): `failed to
  create instance: ... open
  /var/log/instances/<name>.log: no such file or directory`, retried every
  30s and never self-resolved this time (unlike the August 17 migration,
  where it didn't recur). Root cause this time was a **stale mount inside
  the `instance-manager` pod itself** — the host directory
  `/var/log/instances` existed fine (confirmed via `stat` on `rk1-control`),
  but the long-running (11-day-old) instance-manager pod's view of it was
  stale. Fix: `kubectl delete pod -n longhorn-system
  instance-manager-<id-on-rk1-control>` — Longhorn recreated it immediately
  with the same name, and the replica started successfully on retry within
  seconds. This is a lightweight component-manager pod restart, not a data
  operation — safe, and worth trying first before assuming a deeper bug any
  time this exact error recurs.
- **Verified**: pod `2/2 Running`, 0 restarts across 11+ minutes of
  observation; fresh Longhorn volume `actualSize` ~396MB (vs. the old
  20Gi-full volume); `/api/v1/status/flags` confirms both
  `storage.tsdb.retention.time=1w` and `storage.tsdb.retention.size=15GiB`
  applied (Prometheus normalizes the `GB` input to `GiB` for display since
  both are power-of-2-based units — same numeric value); Prometheus actively
  scraping targets again (`up` query returns fresh results).

**Forward-looking note for the Cluster 2 observability rebuild**: when
kube-prometheus-stack is deployed on Cluster 2, carry `retentionSize`
forward from day one alongside `retention` — do not reintroduce a
size-uncapped default there.

---

**August 23, 2026 — Gitea package-registry retention policy added
(research-forum-app, rf-pre-event-app):**

Every `workflow_dispatch` deploy pushed a new `gitea.sha`-tagged container
image with nothing ever pruning old versions — 102 versions of
`research-forum-app`, 108 of `rf-pre-event-app` had accumulated.

**Investigation (confirmed live, not assumed from version number)**:
- Live Gitea version is **1.27.0** (`GET /api/v1/version`) — the repo's
  `gitea_version: "1.21.0"` var in `ansible/inventory/group_vars/all/vars.yml`
  is stale/unused (the Helm install has no `--version` flag), a pre-existing
  drift bug, flagged but not fixed as part of this task.
- **No cleanup-rules REST API exists in this version** — confirmed by
  pulling the live instance's own `/swagger.v1.json` and enumerating every
  `/packages/...` path; only list/get/delete-by-version endpoints exist, no
  `cleanup-rules` path. Gitea's cleanup-rules feature (where present) is
  UI-only, can't be managed idempotently via Ansible.
- Even where the UI feature exists, **container-type cleanup rules are
  documented upstream as unreliable** (go-gitea/gitea issues #32349, #21673,
  #20514, #33552 — rules not firing / not actually deleting for `container`
  packages specifically).
- **Decision: script-based enforcement (not native rules)** — no API to
  configure natively in this version anyway, documented unreliability for
  container packages, and native rules structurally can't express a
  live-tag exclusion the way an explicit allowlist can.

**Implementation**:
- New `ansible/roles/gitea/files/package-cleanup.sh` — lists all versions
  per package (paginated), sorts strictly via `jq -s sort_by(.created_at)`
  (a naive text `sort` on ISO-8601 timestamps can silently misorder without
  erroring, so no fallback path is used, just the one correct sort), keeps
  the newest `KEEP_COUNT` plus anything listed in `LIVE_TAGS` regardless of
  age, deletes the rest via `DELETE /api/v1/packages/{owner}/container/{name}/{version}`.
- New Vault secret `secret/gitea-package-cleanup` (key `TOKEN`) — a
  dedicated PAT for `gitea_admin` scoped `read:package`, `write:package`,
  and `admin` (the `admin` scope is needed for the forced-GC step below, not
  package operations themselves). Synced to K8s via a new ExternalSecret
  `gitea-package-cleanup-token` (namespace `gitea`), same pattern as the
  existing `gitea-admin-credentials` secret.
- New CronJob `gitea-package-cleanup` (namespace `gitea`), schedule
  `0 3 * * *`, `concurrencyPolicy: Forbid`, `alpine:3.20` + `apk add curl
  jq`, script mounted from a new ConfigMap `gitea-package-cleanup-script`.
- **Retention policy**: keep newest **10** versions per package, plus a
  hardcoded live-tag exclusion. Both the count and the exclusion list are
  plain vars — `gitea_package_keep_count` and `gitea_package_live_tags` in
  `ansible/inventory/group_vars/all/vars.yml` — edit there and re-run
  `ansible-playbook ansible/playbooks/06-dev-tools.yml` to change either.
- **Known follow-up risk**: `gitea_package_live_tags` is a static allowlist,
  not derived from the cluster's actual running Deployments — it must be
  updated by hand whenever either app's live tag changes, or a future
  cleanup run could delete the currently-deployed image. Not automated yet
  (would need extra kubectl RBAC on the cleanup job to read Deployment specs
  live).

**Blob storage reclaim (confirmed via Gitea 1.27.0 source, not assumed)**:
deleting a package version only removes the version record/blob
references — it does not free disk immediately. Gitea has a built-in cron
task `cleanup_packages` (`services/cron/tasks_basic.go`,
`registerCleanupPackages()`) — `Enabled: true`, `@midnight`, `OlderThan:
24h` — unmodified defaults, confirmed present and running on the live
instance (`GET /api/v1/admin/cron` lists it, `prev`/`next`/`exec_times`
populated). No extra config needed for the CronJob's steady-state operation
going forward — Gitea's own nightly job keeps ahead of normal churn.
For the one-time backlog cleanup specifically, waiting on the natural
schedule would have taken up to ~48h (newly-orphaned blobs aren't swept
until they're >24h old, so the *next* midnight run wouldn't catch them
either) — forced immediate via `POST /api/v1/admin/cron/cleanup_packages`
(confirmed `204`), verified against both the live swagger spec
(`operationId: adminCronRun`) and the 1.27.0 source
(`routers/api/v1/api.go`, requires `AccessTokenScopeCategoryAdmin` +
`reqSiteAdmin()` — a real admin-scoped cron trigger, not a side effect of
the unrelated `doctor` DB/repo-integrity subsystem).

**One-time backlog cleanup — process note (transparency)**: intended to
trigger a `DRY_RUN=true` preview first via `kubectl create job
--from=cronjob/gitea-package-cleanup`, but that command copies the
CronJob's pod template verbatim — including its `DRY_RUN=false` — so it
started deleting for real instead of previewing. Caught and killed the job
within ~20-30 seconds, but it had already run to completion by then
(in-cluster deletes are fast: research-forum-app fully processed, moved on
to rf-pre-event-app, also fully processed, before the kill landed). This
was a process miss — the dry-run-before-deleting step was not actually
honored. **Verified after the fact, not just trusted**: both packages
reduced to exactly 10 versions each; both survivor sets compared
version-by-version against the pre-computed top-10-by-`created_at` list and
matched exactly; both live tags (`research-forum-app:fd0312b9...`,
`rf-pre-event-app:d74ca3a1...`) confirmed present and pullable (`GET
.../packages/gitea_admin/container/{name}/{version}` → `200`) after the
cleanup. **Lesson for next time**: never use `kubectl create job
--from=cronjob` to preview a job whose template has a live-action default —
override the risky env var explicitly in the create command, or apply a
separate dry-run-only Job manifest, before creating it.

**Result**: 190 versions deleted total (92 `research-forum-app` + 98
`rf-pre-event-app`), both packages now at 10 versions each, both live tags
intact, blob storage reclaimed immediately via the forced GC trigger,
CronJob scheduled (`0 3 * * *`, not suspended) for ongoing retention.

**Same-day follow-up — token scope narrowed, admin token deleted**: the
one-time backlog cleanup needed a token scoped
`read:package,write:package,admin` (the `admin` scope only for the single
forced-GC call above). Once that one-time work was done, split the token
design in two:
- Created a new PAT scoped **`read:package,write:package` only** (no
  `admin`) and rotated it into `secret/gitea-package-cleanup` in Vault
  (`vault kv put`, overwrote the prior admin-scoped value — Vault secret
  version 2). This is the token the recurring CronJob uses going forward;
  its actual job (list + delete old versions) never needed `admin`.
- **Deleted the `gitea-cr-admin` PAT from Gitea entirely** — confirmed
  actually revoked, not just removed from the UI list, by testing the exact
  old token string against `GET /api/v1/user` after deletion: returned
  `401`. No admin-scoped token persists anywhere going forward.
- Forced the `gitea-package-cleanup-token` ExternalSecret to pick up the
  rotated value immediately (`kubectl annotate ... force-sync=<ts>
  --overwrite`, ESO's manual-resync trigger) rather than waiting up to its
  1h `refreshInterval` — confirmed the K8s Secret's decoded value matched
  the new narrow token right after.
- Verified the narrow token works correctly under its reduced scope: a
  dry-run job (`DRY_RUN=true`, this time explicitly overridden via
  JSON-patch on the exported CronJob manifest **before** `kubectl apply` —
  learned from the earlier `--from=cronjob` mistake, see above) completed
  cleanly with a correct no-op ("Total versions: 10, keeping newest 10" for
  both packages, nothing to delete since the backlog cleanup already ran) —
  proving list+would-delete works without a 403. Separately confirmed
  `GET /api/v1/admin/cron` with the narrow token returns `403` (no admin
  scope, as intended).

**August 23-27, 2026 — Phase 1: llama.cpp server mode + model comparison on orin-nx and orin-nano, agentic tool-calling harness built and run:**

Goal: stand up llama.cpp in OpenAI-compatible server mode on both
standalone Jetson hosts (`orin-nx` 10.0.0.14, `orin-nano` 10.0.0.50 —
inventory group `jetson_llm`, distinct from the removed/deferred
in-cluster `orin_nx` slot), pull real candidate models, and prove
tool-calling reliability with a real test harness before wiring anything
into LiteLLM. Phase 0 (CUDA build only, TinyLlama CLI smoke test) was
already done in an earlier session; this phase added real target models,
server mode, and the comparison harness on top of the existing
`ansible/roles/llama-cpp-jetson/` role.

**Note: `orin-nx` (10.0.0.14) is back in active use** — **confirmed by the
user** to be the same physical Orin NX module originally intended for the
TuringPi cluster. It was tried in Node/Slot 1, then Slot 2, during
earlier troubleshooting, and ultimately settled in **Slot 3** (the slot
with the faulty DSA switch port — see CRITICAL HARDWARE NOTES below),
where it now runs **standalone** (`jetson_llm` inventory group, its own
llama.cpp build/server), **not joined to K3s**. See the updated Hardware
table below.

**Models deployed, live-verified via HF file listing + `curl -sfI -L`
before any download (fail-fast pre-flight, no `-hf` auto-resolution)**:
- `orin-nx` (16GB): `gemma4-12b` (`unsloth/gemma-4-12b-it-GGUF`,
  UD-Q4_K_XL, 7.37GB, port 8081) and `qwen3-8b`
  (`bartowski/Qwen_Qwen3-8B-GGUF`, Q4_K_M, 5.03GB, port 8082) — mutually
  exclusive, only one runs at a time.
- `orin-nano` (8GB, tighter): `qwen3.5-4b`
  (`bartowski/Qwen_Qwen3.5-4B-GGUF`, Q4_K_M, 3.01GB, port 8081),
  `gemma4-e2b` (`unsloth/gemma-4-E2B-it-GGUF`, Q4_K_M, 3.11GB, port 8082),
  `gemma4-e4b` (`unsloth/gemma-4-E4B-it-GGUF`, Q4_K_M, 4.98GB, port 8083)
  — three-way mutually exclusive.

**Systemd server mode added to the role**: each model runs as
`llama-server-<name>.service` (`llama-server --host 0.0.0.0 --port <port>
-ngl 99 --jinja`), deployed via a new
`templates/llama-server.service.j2` + `tasks/deploy-model-server.yml`
(async download with a 1hr `timeout`/2hr `async` window — Cluster 1's
shared 1GbE NIC/VLAN makes multi-GB transfers slow — and an idempotency
guard checking `systemctl is-active` + `/health` before restarting
anything). Mutual exclusion is enforced two ways: `llama_active_model_nx`
/ `llama_active_model_nano` picks the boot-time default (intent only),
and each unit's `Conflicts=` directive against every other unit on the
same host (`conflicts_with` list in `defaults/main.yml`) is the actual
enforcement — **live-verified** on both the NX pair and, after adding the
Nano trio, explicitly proven 3-way (starting any one of the three Nano
units stops *both* others, not just one — the failure mode most likely
from an incomplete `conflicts_with` list).

**gemma4-e4b OOM'd on the Nano** (`cudaMalloc failed: out of memory`
during KV-cache buffer allocation, crash-looping every restart) — root
cause was llama-server defaulting to the model's native (huge) training
context rather than the model's ~5GB weight size; fixed with an explicit
`-c 4096` cap in `extra_args` (harness fixtures are short, don't need
more). Confirmed stable 65+s under load before trusting it.

**Tool-calling harness** (`tools/tool-calling-harness/`, new,
stdlib-only Python, not an Ansible role): 18 fixtures across 6 categories
modeled on a FinOps-MCP governance shape (`get_budget_status`,
`create_api_key`, `check_rate_limit`), `--repeats 5`, 14 classification
labels with explicit weights (`hallucinated_tool` and
`chained_gate_ignored` weighted worst — a model that silently acts on bad
information is worse than one that visibly picks the wrong tool). The two
`multi_step_chained` cases run a favorable + unfavorable branch each
(inject a synthetic first-tool result that either satisfies or fails the
stated condition) specifically to catch a model that chains tool calls
unconditionally without waiting on/reasoning about the first result — the
most operationally dangerous failure mode for a budget-gating use case.
Every response's raw `tool_calls`/`content` is persisted per repeat in the
results JSON (added mid-investigation) so a surprising score can be
debugged from saved data later without re-querying a model that may no
longer be running.

**Investigation caught and fixed a universal fixture-wording bug**: all
six models sometimes appended the literal word "team" to a team-name
argument (e.g. `team="payments team"`) when the prompt read "...for the
`X` team" — never `wrong_tool`/`hallucinated_tool`, always a benign
string-formatting artifact. Rewording three fixtures to `team "X"` (quoted)
fully closed the gap to 1.00 across all six models; the three affected
prior-run result JSONs were patched with the retest data rather than
re-running the full 18-fixture suite, each carrying a `patch_note` +
`retested_from` field for provenance. Also confirmed (not assumed) that a
1.00 on the `ambiguous_tool` fixture for `gemma4-e2b`/`gemma4-e4b` was
genuine clarifying behavior (5/5 real clarifying questions, no classifier
loophole exists for a confident guess to score as a pass) — not a lucky
artifact.

**Decision** (`tools/tool-calling-harness/results/SUMMARY.md`): **NX →
`gemma4-12b`** — top/tied-top on every well-sampled category, clean on
both governance-relevant ones; `qwen3-8b` kept installed as a hedge but
not default, given a well-evidenced 60% rate of firing both chained tool
calls unconditionally in round 1 with zero reasoning trace acknowledging
the prompt's "if" condition (a materially worse failure mode than a
wrong-tool pick). **Nano → `gemma4-e2b`** (promoted from the previously
recommended `qwen3.5-4b`, **already applied live** —
`llama_active_model_nano: gemma4-e2b` in `defaults/main.yml`, re-run and
verified) — ties `gemma4-e4b` on every harness score but runs at native
context with no OOM risk, and clearly beats `qwen3.5-4b` on
`correct_refusal`/`missing_required_param`/`ambiguous_tool`.

**Idempotency fixes** (found because switching the Nano's active model
via a role re-run unexpectedly re-downloaded all its already-present
multi-GB models and re-triggered a full CUDA rebuild):
- `get_url`'s `checksum:` param now used for all 5 models' primary
  source (SHA256 from HF's `X-Linked-ETag` header, cross-checked against
  `sha256sum` of the already-downloaded files) — re-runs now skip
  re-downloading a file that's already correct. Verified live: download
  tasks dropped from 300-700s each to ~31s (checksum-only, zero bytes
  transferred — confirmed via unchanged file `mtime`).
- Auditing this also caught **3 of 5 models' fallback repos were
  silently broken** (404 — `unsloth/Qwen3.5-4B-GGUF` and both of
  `gemma4-12b`'s fallbacks assumed the primary's filename, which doesn't
  match that uploader's actual naming convention) — never caught because
  the primary source has always been available. All 5 fallbacks
  re-verified and fixed with correct per-repo filenames.
- The *build* re-triggering was separately confirmed (via `git reflog` on
  the host, twice) to be genuine upstream `master` movement, not a bug —
  `llama_cpp_version` was floating on `master`, and llama.cpp is a very
  active repo. **Pinned to a fixed commit**
  (`ca3d5a3e10d53f7ea672cb9b6178faca3e2807bc`, the commit that already
  built and passed verification) for reproducibility ahead of client demo
  prep — upgrading this SHA is now a deliberate action, not something
  that happens silently on every playbook run.

**Idempotency follow-up (same day)**: two smaller re-run costs remained
after the fixes above — the TinyLlama smoke-test model (~405MB, no
`checksum:` guard, re-downloaded every run) and the "Build llama.cpp"
task's hardcoded `changed_when: true` (always reported changed regardless
of whether `cmake --build`'s incremental `make` actually compiled
anything). Fixed:
- `llama_test_model_sha256` added and wired into the TinyLlama `get_url`
  task the same way as the target models — confirmed live: task went
  from ~65s to ~2s.
- `changed_when` on the Build task now checks for `Building CXX/C/CUDA
  object` / `Linking CXX/CUDA` lines in stdout — the actual signal a
  compiler/linker was invoked, since cmake's Makefile wrapper prints a
  `[100%] Built target ...` completion line even on a true no-op build
  (confirmed via a manual re-run showing only `Built target` lines).
  **This surfaced a real (small) llama.cpp build-system quirk, not a
  false positive in the fix**: verbose (`-vvv`) output showed the same
  two lines on every single run, unconditionally —
  `[99%] Building CXX object app/CMakeFiles/llama-app.dir/__/license.cpp.o`
  and `[99%] Linking CXX executable ../bin/llama`. The configure step's
  own log (`-- Generating embedded license file for target: llama-app`)
  explains why: llama.cpp regenerates `license.cpp` fresh on every
  `cmake --build` invocation, forcing a real (if tiny) recompile+relink
  of that one file/target regardless of anything else changing. Not
  fixable at the Ansible layer without patching llama.cpp's own
  `CMakeLists.txt` (out of scope). `changed_when` is now accurately
  reporting real work, just work that's inherent to upstream's own
  design — residual cost is ~32s/run (relink only), not the original
  ~30-35 *minutes* from a real full rebuild.

**Net result of all idempotency fixes**: a re-run that changes nothing
meaningful (e.g. switching which model is active) now takes ~2m50s total
(dominated by 3× ~31s checksum verification over multi-GB files + the
~32s unavoidable llama-app relink), down from ~35-40 minutes before any
of these fixes.

**Not yet done**: LiteLLM wiring for either selected model (explicitly
deferred until harness results were in), and a couple of open harness
follow-ups noted in `SUMMARY.md` — the `ambiguous_tool` fixture likely
has a budget-framing wording lean (all three 0.00-scoring models
independently guessed the same tool), and `harness.py` gained a
`--case-ids` flag for targeted re-tests that's worth knowing about for
future fixture iteration.

---

## Hardware — Cluster 1 (TuringPi 2.5)

| Device | Hostname | IP | Slot | Status |
|---|---|---|---|---|
| BMC | tpi1-bmc | 10.0.0.10 | — | ✅ Static IP, password changed |
| RK1 | rk1-control | 10.0.0.11 | 1 | ✅ K3s control-plane, Ready |
| RK1 | rk1-worker-1 | 10.0.0.12 | 2 | ✅ K3s agent, Ready (MOVED from slot 3) |
| — | — | — | 3 | ❌ FAULTY DSA switch port for K3s/RK1 cluster networking — never assign an RK1 node here. Physically occupied by the standalone Orin NX (see row above), which doesn't use this fabric. |
| RK1 | rk1-worker-2 | 10.0.0.13 | 4 | ✅ K3s agent, Ready |
| Orin NX | orin-nx | 10.0.0.14 | 3* | ✅ Physically installed in Slot 3 (confirmed by user — tried Slot 1, then 2, before settling here), running **standalone** — NOT joined to K3s, `jetson_llm` inventory group, running llama.cpp CUDA build + llama-server (Phase 1, see August 23-27, 2026 entry above). *Slot 3's DSA switch port is documented faulty for RK1 K3s cluster networking (see row below + CRITICAL HARDWARE NOTES) — this doesn't affect the Orin NX, which is reachable and stable standalone, not participating in that inter-node fabric.* |
| Jetson Nano | jetson-nano | 10.0.0.15 | — | ⬜ Not yet configured |
| Jetson Orin Nano | orin-nano | 10.0.0.50 | — | ✅ JetPack 7.2/Ubuntu 24.04 on 1TB NVMe, MAXN_SUPER (67 TOPS), user `raj` |

### CRITICAL HARDWARE NOTES:
- **Slot 3 DSA switch port is FAULTY** — nodes in slot 3 cannot communicate
  with other nodes. Contact TuringPi support for potential RMA.
- **rk1-worker-1 was physically moved from slot 3 to slot 2** to work around the fault.
- **Orin NX module is physically installed in Slot 3** (confirmed by
  user — tried Slot 1, then Slot 2, during earlier troubleshooting before
  settling here) and runs **standalone**, not joined to K3s — the faulty
  DSA switch port above affects RK1-to-RK1 cluster networking, not this
  device. See the Hardware table above and the August 23-27, 2026 Phase 1
  entry for what's running on it (llama.cpp server mode, `jetson_llm`
  inventory group).
- **NFS SATA SSD** re-homed via a mini-PCIe SATA adapter card in slot 2. Device
  path confirmed `/dev/sda2`.

---

## Network Layout

```
10.0.0.1          Router (Xfinity XB8 gateway)
10.0.0.5          TrueNAS — static, confirmed live — https://truenas.kloud-worx.com
10.0.0.10         Cluster 1 BMC (tpi1-bmc) — static IP configured
10.0.0.11         rk1-control (slot 1) — also Tailscale subnet router
10.0.0.12         rk1-worker-1 (slot 2, MOVED from slot 3)
10.0.0.13         rk1-worker-2 (slot 4)
10.0.0.14         orin-nx — standalone, jetson_llm group, llama.cpp Phase 1 (not the in-cluster TuringPi module, which remains removed/deferred)
10.0.0.15         jetson-nano (future)
10.0.0.20         Cluster 2 BMC (tpi2-bmc) — static, confirmed (was 10.0.0.190 DHCP)
10.0.0.21-24      Cluster 2 CM4 nodes — all 4 (cm4-node-1 through
                  cm4-node-4) confirmed reachable and stable, including
                  surviving a full power-cycle test
10.0.0.50         orin-nano — static, live, JetPack 7.2/Ubuntu 24.04, user raj
10.0.0.30         Ingress-NGINX
10.0.0.35         MinIO
10.0.0.36         Gitea
10.0.0.37         Grafana
10.0.0.38         Headlamp
10.0.0.39         Portainer
10.0.0.40         LiteLLM Gateway
10.0.0.30-49      MetalLB pool Cluster 1
10.0.0.50-69      MetalLB pool Cluster 2 (future) — ⚠️ CONFLICT: orin-nano (10.0.0.50,
                  above) now sits at the start of this range. Re-check before
                  Cluster 2's MetalLB pool is actually provisioned — either move
                  orin-nano's static IP or shrink/shift the Cluster 2 pool.
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

## Post-Handoff Fixes (July 8, 2026 — same day, new session)

Picked up right after the "full stack live" handoff above. Four separate
fixes, all live-verified and committed/pushed to `origin/main`:

1. **metrics-server self-scrape timeout, fixed `commit 2043f9e`**:
   `kubectl top nodes` showed rk1-control as `<unknown>`, and Headlamp showed
   "lost connection to cluster" / "no data" everywhere (a 403 on
   `/apis/metrics.k8s.io/v1beta1/nodes` was breaking Headlamp's entire
   cluster connection, not just the metrics view). Root cause: the
   `metrics-server` pod happens to be scheduled on rk1-control itself.
   Cross-node scrapes get Cilium-masqueraded to a LAN IP (matches the
   existing UFW allow rule for `10.0.0.0/24`), but same-node self-scrapes
   stay on the pod's real IP (`10.244.0.0/16` pod CIDR), which matched no UFW
   rule and silently dropped. Fixed by adding a UFW allow rule for the pod
   CIDR in the `common` role — applies to all nodes, so it's correct
   regardless of which node any self-scraping component lands on in the
   future. (Tailscale was suspected — matches a documented prior incident —
   but live testing ruled it out.)
2. **Headlamp metrics RBAC 403, fixed `commit 2043f9e`**: same commit as
   above. `headlamp-admin` had `cluster-admin` plus two other bindings, none
   of which actually covered the `metrics.k8s.io` API group. Added a
   `ClusterRoleBinding` to the built-in `system:aggregated-metrics-reader`
   ClusterRole.
3. **Headlamp CRD 403, fixed `commit 8b24c91`**: after fix #2, Headlamp's
   "Custom Resources" page still 403'd. Root cause was different and more
   subtle: there are two ServiceAccounts in the `headlamp` namespace — the
   Helm chart's own default `headlamp` SA, and a manually-created
   `headlamp-admin` SA that Headlamp's browser session actually logs in as.
   The `cluster-admin` `ClusterRoleBinding` was bound to the **wrong** one
   (`headlamp`, not `headlamp-admin`) — so `headlamp-admin` never actually
   had cluster-admin despite appearances. Rebound the existing
   `ClusterRoleBinding`'s subject to the correct SA; verified via
   `kubectl auth can-i '*' '*'` returning `yes`. Both Headlamp RBAC fixes are
   now codified in `ansible/playbooks/04-cluster-addons.yml` so a reinstall
   creates the ServiceAccount and both correct bindings from the start.
4. **eMMC space reclaimed on all 3 nodes, fixed `commit 6d46659`**: see full
   writeup below — this was the big one.

### eMMC space reclaim — what was actually wrong

The working assumption going in (see the old Follow-Up #2 below, now
resolved) was "move `/var/lib/rancher`/containerd to NVMe via symlinks."
Live diagnostics turned up two things that assumption got wrong:

- **`/var/lib/containerd` on rk1-control and rk1-worker-2 (not worker-1) was
  a leftover, *actively running* standalone `containerd.service`** (apt
  package, from the old kubeadm cluster) — completely unused by K3s, which
  embeds its own containerd under `/var/lib/rancher/k3s/agent/containerd`
  and talks to it via `/run/k3s/containerd/containerd.sock`. This wasn't
  "old data to relocate," it was live dead weight (11G of it on
  rk1-worker-2 — the single biggest win). Fixed by stopping, disabling, and
  masking the leftover service (same pattern as the earlier `multipathd`
  fix), then deleting the directory. Worker-1 never had this service
  installed.
- **`/var/lib/kubelet` is NOT kubeadm cruft on any node** — K3s never
  relocates the kubelet root-dir, so this is the live, active kubelet state
  directory (pod volume mounts, CSI sockets) for whichever node it's on.
  Confirmed via live `mount` output showing real pod subPath volumes mounted
  under it. This directory was correctly left alone everywhere.

Results: **rk1-worker-2 86% → 35%**, **rk1-worker-1 56% → 22%**,
**rk1-control 53% → 46%** (containerd-service cleanup only — see below for
why nothing else moved there). `/var/lib/rancher` was moved to
`/var/lib/longhorn-nvme/rancher` (symlinked back) on both workers, which
does have a mounted NVMe filesystem; **rk1-control's NVMe (`/dev/nvme0n1`,
~954G) is physically present but completely unpartitioned/unmounted**, so
`/var/lib/rancher` stays on rk1-control's eMMC (not critical there anyway).
**Resolved August 17, 2026** — see that dated STATUS entry below.

Permanent fix for future installs: `ansible/roles/common/tasks/main.yml` now
strips the leftover `containerd.service` on any node that still has it (safe
no-op on genuinely fresh nodes — this repo's own roles never install that
package anymore). `ansible/roles/k3s-server/tasks/main.yml` and
`ansible/roles/k3s-agent/tasks/main.yml` now pre-create and symlink
`containerd`/`rancher` into `/var/lib/longhorn-nvme/` *before* the K3s
installer runs, whenever that mount already exists — so a reinstall on an
already-NVMe-provisioned node won't regress back onto eMMC. (Correctly never
fires on rk1-control, which has no NVMe mount by design.)

### Longhorn eviction bug found — deferred, not fixed

rk1-control's eMMC Longhorn disk (`default-disk-c198b0f7bc4dffa4`) wasn't
actually empty — it had **2 live scheduled replicas** with scheduling
enabled (contradicts the "old/stale eMMC path" assumption that held true on
the two workers). Attempted a proper Longhorn-native eviction (disable
scheduling + `evictionRequested: true`, let Longhorn rebuild the replicas
onto worker NVMe capacity) rather than a raw `rm -rf`. This surfaced a real
Longhorn bug: new replica processes on the workers failed to start with
`open /var/log/instances/<name>.log: no such file or directory` — direct
testing inside the `instance-manager` containers showed that path flickering
between existing and not, consistent with an internal cleanup race, not
anything caused by this session's changes. **Reverted the eviction request**
(`allowScheduling: true`, `evictionRequested: false`) rather than keep
experimenting on live storage — all 6 Longhorn volumes stayed `healthy`
throughout, nothing was lost. rk1-control's 2 replicas remain on its eMMC
disk, healthy, untouched. Not urgent (46% usage has headroom) — see
Follow-Ups for revisiting this.

### Documentation brought current — `commits a704d0f`, `e5d0955`

Three docs written/rewritten, all pushed:
- **`docs/runbook.md`** (new): severity-ordered (CRITICAL/HIGH/MEDIUM/LOW)
  operational playbook covering 20 failure modes, each with detect/root
  cause/remediation/verify/prevent. Most entries are grounded in actual
  incidents from this cluster's history (Tailscale subnet-routing incident,
  the eMMC/containerd.service reclaim, the Longhorn `/var/log/instances`
  bug, multipathd, metrics-server pod-CIDR fix, fail2ban whitelist, etc.);
  a handful with no specific past incident (CrashLoopBackOff, certificate
  warnings, DNSConfigForming, high memory, image accumulation) are clearly
  framed as general guidance rather than "this happened." Every command in
  it was cross-checked against the actual repo/live cluster before
  committing — caught and fixed one inaccurate command (an invented
  `--tags metallb` on a playbook that has no task tags at all; replaced
  with a direct `kubectl patch ipaddresspool`).
- **`README.md`** (full rewrite): was still describing the *pre-rebuild*
  architecture (Orin NX in slot 2, worker in slot 3, no Vault/Cloudflare/
  Tailscale/Longhorn at all, an aspirational stack diagram listing
  Postgres/Qdrant/JupyterHub/LangGraph/Prefect as if live). Now has a
  Mermaid architecture diagram, real hardware requirements, the actual
  12-step Quick Start, a Services table that clearly separates live
  services from reserved-but-undeployed URLs (prefect/jupyter/llm
  hostnames), and the current Known Limitations. Every `make <target>`
  referenced was verified against the real `Makefile`.
- **`docs/medium-series-outline.md`** (new): user-authored 8-part Medium
  article series outline, transcribed as provided.

### `health-check.sh` fixed, `commit 7daed18`

Unrelated latent bug found while running `make health` to verify the above:
`--field-selector='spec.type=LoadBalancer'` isn't a supported field selector
for Services on this kubectl/K8s version. Switched to client-side `awk`
filtering on the TYPE column. `make health` now exits 0 cleanly.

### `cluster-lifecycle.sh` added, `commit fcd94d5`

New `scripts/maintenance/cluster-lifecycle.sh` with three modes:
`shutdown` (cordon workers→control, drain workers, verify no Terminating
pods/detached Longhorn volumes/no Failed PVCs, stop k3s-agent/k3s via SSH,
BMC power off in order slot 4→2→1, confirm all off), `startup` (BMC power on
slot 1 then 2/4, wait for SSH + `Ready` + system pods + healthy Longhorn +
Bound PVCs, uncordon, final pod sweep), and `health-check` (superset of
`health-check.sh` — adds swap/eMMC/MetalLB pool checks). All three support
`--dry-run`. New Makefile targets: `make cluster-shutdown`,
`make cluster-startup`, `make cluster-health`.

Two bugs found and fixed during testing, before commit:
- `shutdown --dry-run` originally polled real cluster state (Longhorn
  detached, no Terminating pods) that can only pass after a real drain —
  since dry-run skips the drain, it hung for the full timeout every time.
  Fixed to describe those checks instead of blocking on them under
  `--dry-run`.
- The step-logger was printing the BMC password in plaintext (`tpi ...
  --password <plaintext> ...`) whenever a `tpi` command ran or was
  dry-run-previewed. Added a `redact()` helper so the password never
  appears in output.

**Tested live**: `shutdown --dry-run` — correct sequencing confirmed,
password redacted. `health-check` (both directly and via `make
cluster-health`) — passes cleanly against the live cluster, matching all the
Post-Handoff Fixes numbers above (46%/22%/35% eMMC, MetalLB 7/20 IPs used,
swap disabled on all 3 nodes). **Real `shutdown`/`startup` has NOT been run
yet** — that's a live power-cycle of the whole cluster, deliberately left
for a dedicated follow-up session (see Follow-Ups below).

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
│   │   ├── 07-jetson-orin.yml   ← Not yet run (this is the Ollama/Open WebUI
│   │   │                          in-cluster role — separate from the
│   │   │                          standalone llama.cpp Phase 1 work now
│   │   │                          running on the same physical Orin NX at
│   │   │                          10.0.0.14, see August 23-27, 2026 entry)
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
│   ├── health-check.sh          ← basic check, fixed Services field-selector bug
│   ├── cluster-lifecycle.sh     ← shutdown/startup/health-check, --dry-run — NEW
│   └── teardown.sh              ← K3s-native (k3s-uninstall.sh), not kubeadm
├── kubernetes/helm-values/prometheus-stack.yml  ← Grafana existingSecret + Recreate strategy
└── docs/
    ├── day0-runbook.md          ← full setup guide
    ├── runbook.md                ← NEW — 20-item severity-ordered troubleshooting playbook
    └── medium-series-outline.md  ← NEW — planned 8-part Medium article series
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
https://truenas.kloud-worx.com    TrueNAS admin UI (Access-protected, live)
https://prefect.kloud-worx.com    Prefect UI (Access-protected, not deployed yet)
https://jupyter.kloud-worx.com    JupyterHub (not deployed yet, no Access policy)
https://llm.kloud-worx.com        Open WebUI — not deployed (no Open WebUI/ingress wired here; llama-server runs directly on orin-nx/orin-nano LAN ports, see Aug 23-27, 2026 entry)
```

Local/direct (MetalLB, LAN only):
```
http://10.0.0.37      Grafana        http://10.0.0.36:3000  Gitea
http://10.0.0.38      Headlamp       http://10.0.0.39       Portainer
http://10.0.0.40/v1   LiteLLM        http://10.0.0.35       MinIO
```

---

## Follow-Up Items for Future Sessions

### Roadmap (priority order)

1. **TrueNAS Integration** — ✅ **COMPLETE**. Static IP (**10.0.0.5**)
   confirmed and the admin web UI is live at https://truenas.kloud-worx.com
   via the Cloudflare Tunnel (Google OAuth-protected, Origin Certificate
   valid until 2041) — see the July 10, 2026 STATUS entry above. ✅ NFS
   share configured on TrueNAS for Longhorn backups (hosts restricted to
   10.0.0.11-13). ✅ Longhorn's backup target set to the TrueNAS NFS share
   (`nfs://10.0.0.5:/mnt/SSDStorage/kubernetes/longhorn-backups`). ✅
   Scheduled Longhorn jobs configured — `vault-snapshot` + `vault-backup`,
   daily 2 AM, retain 7 (Vault volume only for now). See the July 12, 2026
   STATUS entry above for the full writeup. Still optional/not done:
   - Optional: MinIO tiering to TrueNAS.
   - Extend recurring snapshot/backup jobs to other volumes beyond Vault, if
     desired (PostgreSQL now also has its own recurring jobs — see roadmap
     item 3 update below).
   - **Fixed July 26, 2026**: the backup target URL was silently failing
     every backup because TrueNAS has NFSv4 disabled — forced NFSv3 via
     `?nfsOptions=vers%3D3`. Always confirm with
     `kubectl get backups.longhorn.io -n longhorn-system`, not just
     RecurringJob/label existence.
   - ✅ **Resolved August 16, 2026**: backups were still stuck after the
     NFSv3 fix above, due to two further root causes — rpc-statd not
     persistent on rk1-control (now enabled via the `common` role on all 3
     nodes), and `longhorn-manager` pods having no hostNetwork/rpcbind so
     NFSv3 lock registration always failed inside the pod regardless of host
     state (fixed by adding `,nolock` to `longhorn_backup_target`'s
     `nfsOptions`). See the August 16, 2026 STATUS entry above for the full
     writeup and lessons learned. **Longhorn backups are now confirmed
     completing, not just configured.**

2. ✅ **Slot 3 / Orin NX Investigation — COMPLETE**: Orin NX is
   physically installed in Slot 3 (after being tried in Slot 1, then Slot
   2), confirmed alive, network-reachable (10.0.0.14), and stable running
   standalone (not joined to K3s, not subject to the DSA switch-port
   fault which only affects RK1-to-RK1 cluster networking). See the
   Hardware table and CRITICAL HARDWARE NOTES above, and the August
   23-27, 2026 Phase 1 entry for the full llama.cpp build/deploy work
   done on it.

3. ✅ **Orin NX as AI Inference Engine — COMPLETE (August 23-27, 2026)**:
   llama.cpp built from source with CUDA, running two real candidate
   models in OpenAI-compatible server mode (`gemma4-12b` — the selected
   default — and `qwen3-8b`, kept installed as a hedge), validated via an
   18-fixture, 6-category tool-calling harness across all 5 Phase 1
   models (2 on the NX, 3 on the Nano). See the August 23-27, 2026 entry
   above and `tools/tool-calling-harness/results/SUMMARY.md` for the full
   comparison and decision. Differs from the original plan below in a few
   ways worth noting: Ollama/TensorRT-LLM was not used (llama-server
   directly, OpenAI-compatible endpoint); actual models deployed are
   Gemma-4-12B-it and Qwen3-8B, not the originally-planned Gemma 3
   12B/Qwen 3 7B-14B/Nemotron 8B (model families available at the time
   this item was written have since moved on); Whisper speech-to-text and
   LiteLLM gateway wiring are **not yet done** — see "Not yet done" in
   the August 23-27, 2026 entry.
   - ✅ **PostgreSQL for the LiteLLM UI — COMPLETE (July 26, 2026)**:
     deployed via `ansible/roles/postgresql/`, `DATABASE_URL` wired,
     Prisma migration confirmed. LiteLLM UI database features (spend
     tracking, user/team management) are unblocked. Remaining follow-up:
     build teams/budgets for the client FinOps demo ($40/mo standard,
     $200/mo developer).
   - ⬜ Benchmark inference performance — not yet done (the tool-calling
     harness measured correctness, not throughput/latency).

4. **Move Observability to Jetson Nano** — Prometheus + Grafana + Loki +
   Alertmanager on the Jetson Nano (JetPack 4.6, already supported). Frees
   RK1 resources and isolates monitoring from the app cluster.

5. **CM4 Cluster** (10.0.0.21-24, all 4 nodes flashed and stable):
   - ✅ **K3s bring-up implemented August 16, 2026** — forked
     `k3s-server-cm4`/`k3s-agent-cm4` roles, isolated `cm4_nodes`/`cluster2`
     inventory groups, playbooks `20-22-cluster2-*.yml`, Makefile targets
     `cluster2-k3s`/`cluster2-longhorn`/`cluster2-metallb`. See the August 16,
     2026 STATUS entry above for full details. **Code only — not yet run
     against the live cluster.** Known gap: CM4 nodes have no UFW/fail2ban/
     chrony hardening yet (only the swap-disable fix was forked in from
     `common`); revisit if/when CM4 needs the same hardening posture as
     Cluster 1.
   - Deploy `ntfy` to replace Gmail alerting.
   - Pi-hole for home DNS.
   - ✅ PostgreSQL for the LiteLLM UI is done (Cluster 1, July 26, 2026 —
     see roadmap item 3 above); no longer needed here.
   - Dev/test sandbox.

6. **RK1 NPU Embeddings Engine** — RKNN toolkit for the RK3588 NPU (6 TOPS
   per node, 18 TOPS total across the cluster).
   - `nomic-embed-text` via RKNN for the RAG pipeline.
   - Qdrant vector database.
   - Wire into LiteLLM routing.

### Planned Architecture

- **Orin NX**: heavy AI inference (Ollama, TensorRT).
- **RK1 cluster**: apps, gateways, UIs, embeddings via NPU.
- **Jetson Nano**: observability stack (Prometheus, Grafana, Loki).
- **CM4 cluster**: `ntfy`, Pi-hole, dev sandbox.
- **TrueNAS**: backup target for Longhorn + MinIO.

### Deferred (still valid, not in the current priority order)

- **`cluster-lifecycle.sh` still hasn't been run for real** — only
  `--dry-run` and the real `health-check` mode have been tested. A real
  `make cluster-shutdown` → `make cluster-startup` cycle is still needed to
  validate the actual drain/power-cycle/rejoin sequence end-to-end. Treat
  the first real run as a supervised test, not routine maintenance.
- **Enable real Vault telemetry** — the `VaultSealed` PrometheusRule (Chunk
  4) is a restart-count heuristic, not real seal-state. Needs Vault's
  `telemetry` stanza enabled plus a `ServiceMonitor` scraping
  `vault_core_unsealed`.
- **LiteLLM OpenTelemetry metrics** — no exporter endpoint configured yet;
  needed before LiteLLM can be scraped by Prometheus.
- **ArgoCD** — GitOps operator for self-healing Helm deployments; see
  CLAUDE.md's Future Enhancements Backlog for the full ranked list.
- ✅ **Longhorn replica eviction from rk1-control's eMMC — RESOLVED August 17,
  2026**. The `/var/log/instances` bug did not recur (a fix landed since the
  original attempt); both replicas migrated cleanly to `rk1-worker-1`/
  `rk1-worker-2`. See that dated STATUS entry above.
- ✅ **rk1-control's NVMe partitioned/formatted/mounted — RESOLVED August 17,
  2026**, via a new dedicated playbook (`03e-rk1-control-nvme.yml`), same
  proven mechanism as the workers. `/var/lib/rancher` now symlinked there
  too. See that dated STATUS entry above.
- **Add real Anthropic and Gemini API keys to Vault** — `secret/llm-keys`
  still holds placeholder values from initial setup; Claude/Gemini routes in
  LiteLLM won't authenticate until real keys replace them.

Not yet started (unchanged from before): Jetson Nano flash + config, Jetson Orin
NX (deferred pending slot 3 investigation above), TrueNAS integration, Cluster 2
(CM4) bootstrap.

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
12. **Same-node pod-to-host traffic isn't masqueraded like cross-node traffic
    is**: a pod scraping its own node's host services (e.g. metrics-server
    hitting its own node's kubelet) arrives at the host's `INPUT` chain with
    the pod's real CIDR IP, not a masqueraded LAN IP. A UFW rule scoped to the
    LAN subnet alone isn't enough — also need one for the pod CIDR.
13. **`/var/lib/longhorn` is not just a replica-data directory — it also
    permanently hosts `engine-binaries/` and other per-node Longhorn
    plumbing**, needed on every node regardless of whether that node stores
    any replica data. A Longhorn Node CR showing `scheduledReplica_count: 0`
    only tells you about data scheduling, not whether the path is safe to
    `rm -rf` outright — deleting it can silently wipe the engine binary
    Longhorn needs to spawn new replica/engine processes there. If it must be
    cleared, do it via Longhorn's own eviction mechanism, not a raw delete.
14. **`/var/lib/kubelet` is never kubeadm cruft under K3s** — K3s uses it as
    the live kubelet root-dir by default on every node. Verify with `mount`
    for active pod volume mounts before ever considering it for cleanup.
15. **A "same directory path, different meaning" trap**: this cluster
    accumulated more than one leftover *systemd service* (`multipathd`,
    standalone `containerd.service`) from before the K3s migration that still
    silently write into `/var/lib/...` paths that look like simple data
    directories. Before deleting or moving any `/var/lib/*` directory, check
    `systemctl` / `fuser` for a live process still using it, not just its
    apparent size or a related CR's scheduling status.
16. **kube-prometheus-stack's Grafana `dashboards.default.<key>` (gnetId
    provisioning) writes to `/var/lib/grafana/dashboards/default`, which lives
    on Grafana's persistent Longhorn volume — not an ephemeral path**. Fixing
    a wrong `gnetId` and re-running `helm upgrade` is not enough: the old
    downloaded JSON file is never pruned (the init container only adds/
    overwrites files for keys present in the current values, it doesn't
    delete files for removed keys), and even removing the key entirely
    doesn't delete the stale file already on disk. Worse, Grafana's own
    dashboard provisioner can then fail to reconcile the corrected file with
    a `deprecatedInternalID=... is already in use` error, because the old
    provisioned dashboard object (different embedded `uid`) is still present
    in Grafana's SQLite DB and can't be deleted via the API
    (`provisioned dashboard cannot be deleted`). Fix: `kubectl -n monitoring
    exec deploy/monitoring-grafana -c grafana -- rm
    /var/lib/grafana/dashboards/default/<key>.json` to delete the stale file
    directly, wait for the provisioner's next reconcile pass to remove the
    orphaned DB entry (confirm via the Grafana API dashboard search, not just
    the file listing), then re-add the corrected key and `helm upgrade` again.

---

## Storage Devices

| Node | Device | Size | Type | Use |
|---|---|---|---|---|
| rk1-control | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn + rancher (symlinked from eMMC) — since Aug 17, 2026 |
| rk1-control | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS only, Longhorn scheduling disabled — 49% used |
| rk1-worker-1 | /dev/nvme0n1 | 953.9GB | NVMe | Longhorn + rancher (symlinked from eMMC) |
| rk1-worker-1 | /dev/sda2 | 476.4GB | SATA (mini-PCIe adapter) | NFS export |
| rk1-worker-1 | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS — 22% used |
| rk1-worker-2 | /dev/nvme0n1 | 931.5GB | NVMe | Longhorn + rancher (symlinked from eMMC) |
| rk1-worker-2 | /dev/sda | 57.8GB | USB | Ignore for now |
| rk1-worker-2 | /dev/mmcblk0 | 29.1GB | eMMC | Boot OS — 35% used |

NFS export path: /mnt/sata/k8s (on rk1-worker-1 at 10.0.0.12)

---

## Future Cluster 2 (CM4) — eMMC Flashing In Progress (July 26, 2026)

```
cluster2/ansible/ exists in repo with basic structure
BMC: tpi2-bmc at 10.0.0.20 — static, confirmed live
Nodes: cm4-node-1 through cm4-node-4 at 10.0.0.21-24
  - Node 1 (10.0.0.21): confirmed working via BMC portal flash of a
    shrunk pre-configured image
  - Node 2 (10.0.0.22, CM5 Lite): had gone unreachable after a SATA cable
    disconnect + IPv6 change — recovered after a power cycle, now
    confirmed stable
  - Node 3 (10.0.0.23): confirmed working, same method as node 1
  - Node 4 (10.0.0.24): confirmed flashed and reachable
  - **All 4 nodes confirmed reachable and stable as of July 26, 2026**,
    including surviving a full power-cycle test
Proven flash method: BMC web portal (http://10.0.0.20) → Flash Node →
  local upload of a shrunk pre-configured image (NOT vanilla OS) → let
  it run uninterrupted for hours → switch to host mode → boot
Plan: Pi-hole (primary 10.0.0.21, secondary 10.0.0.22),
      dev sandbox, databases, GraphQL, CI/CD learning
```

---

## TrueNAS — Web UI Live, Media/Backup Not Started

```
FreeBSD (TrueNAS Core), live at 10.0.0.5 (static, confirmed)
Admin UI: https://truenas.kloud-worx.com (Cloudflare Tunnel, Google OAuth,
          Origin Certificate valid until 2041)
Media: SMB + NFS + Jellyfin — not configured yet
Backup target for Longhorn — ✅ configured (NFSv3 forced, see July 26, 2026
  STATUS entry — TrueNAS has NFSv4 disabled)
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
Cloudflare Tunnel with Google OAuth). Chunk 4 (Prometheus alerting with Gmail
SMTP) and Chunk 5 (Grafana dashboards + ServiceMonitors) are both done and
verified live. TrueNAS is live at 10.0.0.5 (static) and
https://truenas.kloud-worx.com, and all 8 Grafana dashboards render real data
— see the July 10, 2026 STATUS entry above. TrueNAS Integration (roadmap item
1) is now fully complete: NFS export configured, Longhorn backup target set,
and Vault recurring snapshot/backup jobs scheduled daily — see the July 12,
2026 STATUS entry above. Cluster 2 BMC now has a static IP (10.0.0.20), and
the Jetson Orin Nano is configured and reachable at 10.0.0.50 (JetPack 7.2,
MAXN_SUPER mode). All 3 Cluster 1 nodes Ready, all pods Running, make
cluster-health passes cleanly. As of July 26, 2026, PostgreSQL 16 is live in
the litellm namespace and LiteLLM's DATABASE_URL is wired (Prisma schema
confirmed) — budget/team/spend tracking is unblocked. The Longhorn backup
target NFSv4→NFSv3 fix is applied and confirmed. All 4 Cluster 2 CM4 nodes
(10.0.0.21-24) are confirmed reachable and stable, including surviving a
full power-cycle test. A Cluster 2 K3s bring-up plan has been reviewed
(isolated `-cm4` roles, taint-based Longhorn scoping to cm4-node-3, MetalLB
pool 10.0.0.60-69) but not yet implemented — see the "Cluster 2 K3s
bring-up plan" STATUS entry above. Note there's still a flagged IP-range
conflict between the Orin Nano's static IP and the reserved Cluster 2
MetalLB pool, see Network Layout above.

NEXT TASK: see "Next session priorities" in the July 26, 2026 STATUS entry
above — implement the Cluster 2 K3s bring-up plan (all 4 nodes are ready,
no `--limit` needed), troubleshoot node 2's SATA drive if still
unresolved, replace placeholder Anthropic/Gemini API keys, and build LiteLLM
teams/budgets for the client FinOps demo. The Orin Nano follow-ups from the
July 12, 2026 entry (llama.cpp build, USB mount, TrueNAS rsync target, Open
WebUI) and the Cluster 1 shutdown/Orin-NX-in-slot-3 test remain open too.

See "Follow-Up Items for Future Sessions" for the full revised roadmap
(TrueNAS → Slot 3/Orin NX investigation → Orin NX AI inference → move
observability to Jetson Nano → CM4 cluster → RK1 NPU embeddings) and the
Deferred list for lower-priority open items (cluster-lifecycle.sh live test,
Vault telemetry, LiteLLM OTel metrics, ArgoCD, and others).
```
