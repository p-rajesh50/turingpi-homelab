SHELL           := /bin/bash
INVENTORY       := ansible/inventory/hosts.yml
ANSIBLE_ARGS    ?=
KUBECONFIG      ?= $(HOME)/.kube/turingpi-cluster1.conf

-include $(HOME)/.turingpi
export BMC_IP BMC_USER BMC_PASSWORD BMC_TOKEN

.DEFAULT_GOAL := help

# ─────────────────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo ""
	@echo "TuringPi Homelab — github.com/p-rajesh50/turingpi-homelab"
	@echo "══════════════════════════════════════════════════════════"
	@echo ""
	@echo "  SETUP (run first on any new machine)"
	@echo "    make setup            Install tpi, ansible, credentials, SSH key"
	@echo "    make check            Verify tools + BMC connectivity"
	@echo ""
	@echo "  OS FLASH"
	@echo "    make flash            Flash Ubuntu 22.04 on RK1 slots 1, 3, 4"
	@echo "    make flash-node N=1   Flash a single node"
	@echo "    make discover         Scan network for node IPs after flash"
	@echo ""
	@echo "  CLUSTER BUILD (run in order)"
	@echo "    make bootstrap        SSH keys, hostnames, static IPs"
	@echo "    make common           Hardening, packages, NTP, firewall"
	@echo "    make kubernetes       Deploy K8s cluster (control + workers)"
	@echo "    make storage          Longhorn (NVMe) + NFS (SATA) + MinIO"
	@echo "    make addons           MetalLB, ingress, Prometheus, Grafana"
	@echo "    make secrets          Store API keys in Kubernetes Secrets"
	@echo "    make ai-stack         LiteLLM, Qdrant, JupyterHub, LangGraph, Prefect"
	@echo "    make dev-tools        Gitea + Actions CI/CD"
	@echo ""
	@echo "  ALL-IN-ONE"
	@echo "    make build            Runs: common → kubernetes → storage → addons"
	@echo "    make build-all        Runs: build → ai-stack → dev-tools"
	@echo ""
	@echo "  GPU NODES (manual JetPack flash required first)"
	@echo "    make jetson-orin      Configure Orin NX (Ollama, Open WebUI, ML stack)"
	@echo "    make jetson-nano      Configure Jetson Nano (embeddings, small models)"
	@echo ""
	@echo "  MAINTENANCE"
	@echo "    make health           Cluster health check"
	@echo "    make teardown         Reset K8s on all nodes (keeps OS)"
	@echo "    make teardown-hard    Reset K8s + power off all nodes"
	@echo "    make update           apt upgrade all nodes"
	@echo ""
	@echo "  BMC / POWER"
	@echo "    make power-status     Show all node power states"
	@echo "    make power-on         Power on all nodes"
	@echo "    make power-off        Power off all nodes"
	@echo "    make power-on-node  N=1    Power on specific node"
	@echo "    make power-off-node N=1    Power off specific node"
	@echo "    make cycle-node     N=1    Power cycle specific node"
	@echo ""
	@echo "  GIT"
	@echo "    make git-init         Initialize local git repo and push to GitHub"
	@echo "    make save MSG='...'   Commit and push all changes"
	@echo "    make sync             Pull latest from GitHub"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: setup
setup:
	@bash scripts/workstation/setup.sh

.PHONY: check
check:
	@echo "=== Tool versions ==="
	@command -v tpi     && tpi --version              || echo "✗ tpi not installed"
	@command -v ansible && ansible --version | head -1 || echo "✗ ansible not installed"
	@command -v nmap    && nmap --version | head -1    || echo "✗ nmap not installed"
	@echo ""
	@echo "=== BMC connectivity ==="
	@source "$(HOME)/.turingpi" && \
		tpi --host "$$BMC_IP" --user "$$BMC_USER" --password "$$BMC_PASSWORD" \
		power status || echo "✗ Cannot reach BMC"

# ─────────────────────────────────────────────────────────────────────────────
# OS FLASH
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: flash
flash:
	@bash scripts/os-flash/flash-rk1.sh

.PHONY: flash-node
flash-node:
	@test -n "$(N)" || (echo "ERROR: specify node with N=1, N=3, or N=4"; exit 1)
	@bash scripts/os-flash/flash-rk1.sh --node $(N)

.PHONY: discover
discover:
	@bash scripts/os-flash/discover-nodes.sh

# ─────────────────────────────────────────────────────────────────────────────
# CLUSTER BUILD
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: bootstrap
bootstrap:
	ansible-playbook ansible/playbooks/00-bootstrap.yml \
		-i $(INVENTORY) --ask-pass --ask-become-pass $(ANSIBLE_ARGS)

.PHONY: common
common:
	ansible-playbook ansible/playbooks/01-common.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: kubernetes
kubernetes:
	ansible-playbook ansible/playbooks/02-kubernetes.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: storage
storage:
	ansible-playbook ansible/playbooks/03-storage.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: addons
addons:
	ansible-playbook ansible/playbooks/04-cluster-addons.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: secrets
secrets:
	@bash scripts/secrets/setup-api-keys.sh

.PHONY: ai-stack
ai-stack:
	ansible-playbook ansible/playbooks/05-ai-stack.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: dev-tools
dev-tools:
	ansible-playbook ansible/playbooks/06-dev-tools.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: jetson-orin
jetson-orin:
	ansible-playbook ansible/playbooks/07-jetson-orin.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

.PHONY: jetson-nano
jetson-nano:
	ansible-playbook ansible/playbooks/08-jetson-nano.yml \
		-i $(INVENTORY) $(ANSIBLE_ARGS)

# ─────────────────────────────────────────────────────────────────────────────
# ALL-IN-ONE
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: build
build: common kubernetes storage addons
	@echo "✓ Core cluster build complete — run 'make secrets' then 'make ai-stack'"

.PHONY: build-all
build-all: build ai-stack dev-tools
	@$(MAKE) health

# ─────────────────────────────────────────────────────────────────────────────
# MAINTENANCE
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: health
health:
	@bash scripts/maintenance/health-check.sh

.PHONY: teardown
teardown:
	@bash scripts/maintenance/teardown.sh

.PHONY: teardown-hard
teardown-hard:
	@bash scripts/maintenance/teardown.sh --hard

.PHONY: update
update:
	ansible all -i $(INVENTORY) -m apt \
		-a "upgrade=dist update_cache=yes" --become $(ANSIBLE_ARGS)

# ─────────────────────────────────────────────────────────────────────────────
# BMC / POWER
# ─────────────────────────────────────────────────────────────────────────────
TPI := tpi --host $(BMC_IP) --user $(BMC_USER) --password $(BMC_PASSWORD)

.PHONY: power-status
power-status:
	@$(TPI) power status

.PHONY: power-on
power-on:
	@for n in 1 2 3 4; do $(TPI) power on --node $$n; done

.PHONY: power-off
power-off:
	@for n in 1 2 3 4; do $(TPI) power off --node $$n; done

.PHONY: power-on-node
power-on-node:
	@test -n "$(N)" || (echo "ERROR: N=<1-4> required"; exit 1)
	@$(TPI) power on --node $(N)

.PHONY: power-off-node
power-off-node:
	@test -n "$(N)" || (echo "ERROR: N=<1-4> required"; exit 1)
	@$(TPI) power off --node $(N)

.PHONY: cycle-node
cycle-node:
	@test -n "$(N)" || (echo "ERROR: N=<1-4> required"; exit 1)
	@$(TPI) power off --node $(N) && sleep 3 && $(TPI) power on --node $(N)
	@echo "✓ Node $(N) cycled"

# ─────────────────────────────────────────────────────────────────────────────
# GIT
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: git-init
git-init:
	@if [ ! -d ".git" ]; then \
		git init; \
		git add .; \
		git commit -m "Initial commit: TuringPi homelab automation"; \
		git branch -M main; \
		git remote add origin git@github.com:p-rajesh50/turingpi-homelab.git; \
		git push -u origin main; \
		echo "✓ Pushed to github.com/p-rajesh50/turingpi-homelab"; \
	else \
		echo "✓ Git already initialized"; git remote -v; \
	fi

.PHONY: save
save:
	@test -n "$(MSG)" || (echo "ERROR: MSG='your message' required"; exit 1)
	@git add -A && git commit -m "$(MSG)" && git push
	@echo "✓ Saved and pushed"

.PHONY: sync
sync:
	@git pull --rebase && echo "✓ Synced"
