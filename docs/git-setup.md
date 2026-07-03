# Git Setup — github.com/p-rajesh50/turingpi-homelab

## First time: push repo to GitHub

You have already created the `turingpi-homelab` repo on GitHub this morning.
Do these steps once from your WSL terminal after downloading the repo files.

### 1. Initialize and push

```bash
cd ~/turingpi-homelab

git init
git add .
git commit -m "Initial commit: TuringPi homelab automation"
git branch -M main
git remote add origin git@github.com:p-rajesh50/turingpi-homelab.git
git push -u origin main
```

### 2. Set up GitHub SSH key (if not done)

```bash
# Generate a key for GitHub (separate from your cluster key)
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/github -N ""

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github

# Copy public key
cat ~/.ssh/github.pub
# Paste at: https://github.com/settings/ssh/new

# Test
ssh -T git@github.com
```

---

## On every new machine: 3 commands

```bash
git clone git@github.com:p-rajesh50/turingpi-homelab.git ~/turingpi-homelab
cd ~/turingpi-homelab
make setup
```

---

## Daily workflow

```bash
make save MSG="Add LiteLLM config for Gemini"   # commit + push
make sync                                         # pull latest
make help                                         # see all commands
```

---

## What is NOT in git (intentional)

- `~/.turingpi`                          — BMC credentials (machine-local)
- `ansible/group_vars/all/vault.yml`     — Ansible Vault secrets
- `scripts/os-flash/images/`             — large OS image files (~3GB each)
- `*.local.yml`                          — local overrides

The `make setup` script recreates `~/.turingpi` on each new machine.
API keys are stored in Kubernetes Secrets, not in this repo.
