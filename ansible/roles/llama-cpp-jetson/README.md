# llama-cpp-jetson

Builds llama.cpp from source with CUDA on the `jetson_llm` inventory group
(`orin-nx` 10.0.0.14, `orin-nano` 10.0.0.50), then pulls target GGUF models
and runs them as `llama-server` systemd units with an OpenAI-compatible
`/v1/chat/completions` endpoint.

Run via `make llama-cpp-jetson` (playbook `ansible/playbooks/16-llama-cpp-jetson.yml`).

## Models and ports

| Host | Model | Port | Unit | Default-active |
|---|---|---|---|---|
| orin-nano | Qwen3.5-4B (Q4_K_M) | 8081 | `llama-server-qwen3.5-4b.service` | |
| orin-nano | Gemma-4 E2B-it (Q4_K_M) | 8082 | `llama-server-gemma4-e2b.service` | ✅ |
| orin-nano | Gemma-4 E4B-it (Q4_K_M) | 8083 | `llama-server-gemma4-e4b.service` | |
| orin-nx | gemma-4-12b-it, omni build (UD-Q4_K_XL) | 8081 | `llama-server-gemma4-12b.service` | ✅ |
| orin-nx | Qwen3-8B (Q4_K_M) | 8082 | `llama-server-qwen3-8b.service` | |

`gemma4-e2b` became the Nano's default-active model on 2026-08-27
(previously `qwen3.5-4b`) — see the Phase 1 tool-calling harness
comparison in `tools/tool-calling-harness/results/SUMMARY.md` for the
rationale: it ties `gemma4-e4b` on every harness score while running at
its native context with no OOM risk, and clearly outperforms
`qwen3.5-4b` on `correct_refusal`, `missing_required_param`, and
`ambiguous_tool`.

Model repos/filenames/fallbacks are defined in `defaults/main.yml`
(`llama_models_orin_nano`, `llama_models_orin_nx`). Every filename there was
live-verified against Hugging Face's file listing before use — never rely
on `-hf` auto-resolution, which can silently pick a different quant.

## Only one model runs at a time, per host

Neither host can hold more than one of its models in memory at once at
these quant levels — the NX can't run Gemma-4-12B and Qwen3-8B together
(16GB), and the Nano is tighter still (8GB): even though qwen3.5-4b
(3.01GB), gemma4-e2b (3.11GB), and gemma4-e4b (4.98GB) each fit
individually at Q4, running two at once doesn't. Two enforcement layers
exist on both hosts:

1. **`llama_active_model_nx` / `llama_active_model_nano`**
   (`defaults/main.yml`, default `gemma4-12b` / `gemma4-e2b`) — controls
   which unit this role enables + starts by default on a run. The other
   unit(s) are still installed (`enabled: false, state: stopped`), just
   not started automatically. This is *intent*, not enforcement — it only
   governs what happens at deploy/boot time.
2. **`systemd Conflicts=`** (`templates/llama-server.service.j2`) — the
   actual enforcement. Each unit's `[Unit]` section declares `Conflicts=`
   on every *other* unit on the same host (driven by `conflicts_with` in
   `defaults/main.yml` — a list per model: 1 entry on the NX pair, 2
   entries each on the Nano's three-way set). Systemd stops every
   conflicting unit automatically whenever one is started — so
   `systemctl start llama-server-gemma4-e4b` on the Nano while
   `llama-server-qwen3.5-4b` is running will stop `qwen3.5-4b`
   automatically (and would stop `gemma4-e2b` too, if it had been
   running), regardless of what `llama_active_model_nano` says. This
   guarantees exclusivity even if someone starts the "wrong" unit by hand
   later and forgets the convention.

To switch which model is active by default: change
`llama_active_model_nx` / `llama_active_model_nano` and re-run the role,
or just `systemctl start llama-server-<other-model>` directly on the host
(`Conflicts=` handles stopping whichever else was running).

## Bandwidth guardrail: shared 1GbE NIC/VLAN on Cluster 1

The Orin NX is physically in Cluster 1 (TuringPi 2.5, slot 2) on the same
1GbE NIC/VLAN as the K3s nodes — bandwidth is shared and constrained. Model
downloads here are multi-GB (Q4-quantized 8B-12B models run 5-8GB+). Two
things account for this:

- `llama_download_timeout` (default 3600s / 1hr) is passed explicitly to
  `get_url` — do not trust Ansible's default socket timeout for these
  transfers.
- Downloads run `async: llama_download_async_seconds (7200s) / poll: 0`,
  with a separate `async_status`-polling task (every 30s), so a slow
  transfer can't stall or time out the whole Ansible play the way a
  synchronous `get_url` would.

If you add a new large model pull to this role later, reuse
`llama_download_timeout` / `llama_download_async_seconds` rather than
re-investigating this from scratch.

## Idempotency

Re-running the role does not blindly restart every unit. For each
default-active model, it checks `systemctl is-active` **and** the
`/health` endpoint on that model's port — it only (re)starts the unit if
either check fails, not merely because the unit file exists.

## Smoke test

`make llama-serve-test` curls `/v1/chat/completions` on each active
server's port and checks for a real completion in the response.
