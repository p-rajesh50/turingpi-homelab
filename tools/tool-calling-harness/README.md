# Tool-calling harness

Manual dev-time script for scoring an OpenAI-compatible
`/v1/chat/completions` endpoint on tool-calling reliability, ahead of
wiring any model into LiteLLM. Not an Ansible role, not automated — run it
by hand against whichever `llama-server` is currently up (see
`ansible/roles/llama-cpp-jetson/README.md` for ports).

## Usage

```bash
python3 harness.py --base-url http://10.0.0.50:8081 --model qwen3.5-4b
python3 harness.py --base-url http://10.0.0.14:8081 --model gemma4-12b
python3 harness.py --base-url http://10.0.0.14:8082 --model qwen3-8b
```

Options: `--repeats` (default 5), `--temperature` (default 0.6), `--top-p`
(default 0.95), `--fixtures` (default `fixtures.json`), `--output-dir`
(default `results/`).

Stdlib-only (`urllib.request`/`json`/`argparse`) — no extra dependencies.

## Fixtures

`fixtures.json` defines 3 tool schemas (`get_budget_status`,
`create_api_key`, `check_rate_limit` — modeled on a FinOps-MCP governance
shape) and 18 cases across 6 categories:

- `correct_tool_correct_params` (6) — clear single-intent asks, 2 per tool.
- `correct_refusal` (4) — tool-adjacent prompts with no matching tool
  (e.g. "delete this key" — no delete tool exists).
- `missing_required_param` (4) — prompts missing one required field; model
  should ask, not guess.
- `ambiguous_tool` (1) — genuine tool-choice ambiguity (could plausibly map
  to more than one tool).
- `ambiguous_params` (1) — tool choice is clear, but parameter values are
  unresolved/unconfirmable (a distinct failure surface from tool-choice
  ambiguity — kept as its own category rather than averaged with
  `ambiguous_tool`).
- `multi_step_chained` (2) — a second tool call is conditional on the
  first call's result (e.g. only create a key if the team is under
  budget).

## Classification labels and scoring

Each response is classified into exactly one label; `SCORE_WEIGHTS` in
`harness.py` is the single source of truth for weights, reproduced here
for reference:

| Label | Weight | Meaning |
|---|---|---|
| `correct_tool_correct_params` | +1.0 | Right tool, right params. |
| `correct_refusal` | +1.0 | Correctly declined — no matching tool exists. |
| `missing_clarification` | +1.0 | Correctly asked instead of guessing a missing/ambiguous value. |
| `partial_params` | +0.5 | Right tool, a required param is wrong/malformed — a different failure mode than picking the wrong tool. |
| `ambiguous_param_guess` | -1.0 | Right tool, but guessed an unconfirmed param value instead of asking (`ambiguous_params` category only) — worse than `partial_params` because it can succeed silently. |
| `wrong_tool` | -1.0 | Called a real but incorrect tool. |
| `hallucinated_tool` | -1.5 | Invented a tool that doesn't exist — worse than `wrong_tool`: a governance layer has to trust the tool list it's given. |
| `chained_correct` | +1.0 | Favorable branch: condition satisfied, second tool correctly called. |
| `wrong_tool_sequence` | -0.5 | Chained case: both tools eventually called, wrong order. |
| `incomplete_chain` | -0.5 | **Favorable branch only** — condition was satisfied, second tool should have fired, didn't. A missed-action failure. |
| `chained_correct_gate_respected` | +1.0 | Unfavorable branch: condition failed, model correctly withheld the second call AND clearly said why (matched `gate_keywords`). |
| `chained_silent_gate` | -0.25 | **Unfavorable branch only** — model correctly withheld the second call, but didn't clearly explain the blocking condition. Right action, unconfirmed reasoning — lighter penalty than `incomplete_chain` since no wrong action was taken. |
| `chained_gate_ignored` | -1.5 | Unfavorable branch: model called the second tool anyway despite the blocking result — e.g. creates an API key after being told the team is over budget. Weighted equal to `hallucinated_tool`: a governance failure that acts silently on bad information. |
| `premature_unconditional_chain` | -1.5 | Both tools fired in the very first turn, before any result could be seen — the model never waited on the condition at all. |

### Chained-case testing: two branches per case

`multi_step_chained` cases run a 2-round conversation per repeat: round 1
sends the prompt; if only the first expected tool was called (not both —
that's `premature_unconditional_chain`), round 2 is run **twice**:

- **Favorable branch**: inject `synthetic_result_favorable` (e.g. under
  budget, not rate-limited) — the model should call the second tool.
- **Unfavorable branch**: inject `synthetic_result_unfavorable` (e.g. over
  budget, rate-limited) — the model should NOT call the second tool, and
  should say why (checked against `gate_keywords`).

This is the more important behavior to prove for a budget-gating
governance use case: a model that always chains obediently regardless of
the first result is a real risk, and a single favorable-only test can't
tell "correctly gated" from "got lucky once."

Results report `<case_id>-favorable` / `<case_id>-unfavorable` as separate
rows — they are never averaged into one chained-case score, since a model
could pass one branch while failing the other in an operationally
important way.

## A note on sample size per category

Categories are backed by different numbers of fixture cases, which means
their scores carry different statistical weight:

- `correct_tool_correct_params`: 6 cases (30 samples at `--repeats 5`)
- `correct_refusal`: 4 cases (20 samples)
- `missing_required_param`: 4 cases (20 samples)
- `multi_step_chained`: 2 cases x 2 branches (20 samples)
- `ambiguous_tool`: 1 case (5 samples)
- `ambiguous_params`: 1 case (5 samples)

Treat the first four as the primary decision signal when comparing models
— a consistent gap there is meaningful. Treat `ambiguous_tool` and
`ambiguous_params` as directional, not decisive: a single fixture case is
sensitive to prompt wording and sampling variance in ways a multi-case
category isn't. During qwen3.5-4b's first full run, `ambiguous_tool`
scored 0.00 (5/5 fail) — investigating the raw transcripts showed the
model wasn't randomly failing but consistently guessing the same tool,
and a fresh re-run at the same settings even produced one genuine
clarifying question. The headline number alone would have overstated how
settled that result was. If a category like this looks extreme for any
model being tested, dig into `repeats[].raw` in the results JSON before
treating the score as conclusive — don't average it into an overall
verdict at the same weight as the well-sampled categories.

## Output

Each run writes `results/<model>-<timestamp>.json` (raw per-branch labels
+ weighted scores + full category rollup) and a matching `.md` file with
per-category and per-case tables, so multiple models' runs sit side by
side for comparison.
