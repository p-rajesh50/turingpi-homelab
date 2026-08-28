# Phase 1 tool-calling comparison — summary

Reference record of the model-selection decisions made from harness runs
against all five Phase 1 Jetson-hosted models (3 Nano candidates, 2 NX
candidates). See `../README.md` for full methodology; see the linked JSON
files below for raw per-repeat transcripts.

## How this was tested

18 fixtures across 6 categories (`fixtures.json`), `--repeats 5` per case,
temp 0.6 / top_p 0.95. The 2 `multi_step_chained` cases each run a
favorable branch (condition satisfied — should proceed) and an
unfavorable branch (condition fails — should decline and say why),
scored separately rather than averaged together.

**Provenance note (added 2026-08-27):** `correct-02`/`correct-03`/
`correct-04` were reworded on 2026-08-26 to remove a `"<team-name> team"`
phrasing ambiguity (see "Key qualitative findings" below) and re-tested
against all five models via `harness.py --case-ids correct-02,correct-03,
correct-04 --repeats 5`. Each model's result JSON below has those three
cases' `branches.single` blocks — and the `correct_tool_correct_params`
category rollup — replaced with that retest's data (each patched case
carries a `retested_from` field naming the retest file it came from, and
each file's root object carries a `patch_note` explaining the change).
`correct-01`/`correct-05`/`correct-06` and every other category are
untouched, reflecting each model's original full-suite run date.

## Comparison table — Nano candidates

| Category | qwen3.5-4b | gemma4-e2b | gemma4-e4b |
|---|---|---|---|
| correct_tool_correct_params (30 samples) | 1.00 | 1.00 | 1.00 |
| correct_refusal (20 samples) | 0.85 | **1.00** | **1.00** |
| missing_required_param (20 samples) | 0.50 | **1.00** | **1.00** |
| multi_step_chained (20 samples) | 1.00 | 1.00 | 1.00 |
| ambiguous_tool (5 samples — low confidence, see below) | 0.00 | **1.00** | **1.00** |
| ambiguous_params (5 samples — low confidence, see below) | 1.00 | 1.00 | 1.00 |

Full per-model results: [`qwen3.5-4b-20260823-194421.json`](qwen3.5-4b-20260823-194421.json), [`gemma4-e2b-20260825-222034.json`](gemma4-e2b-20260825-222034.json), [`gemma4-e4b-20260826-125709.json`](gemma4-e4b-20260826-125709.json).

## Comparison table — NX candidates

| Category | gemma4-12b | qwen3-8b |
|---|---|---|
| correct_tool_correct_params (30 samples) | 1.00 | 1.00 |
| correct_refusal (20 samples) | 0.85 | 0.90 |
| missing_required_param (20 samples) | **1.00** | **1.00** |
| multi_step_chained (20 samples) | **1.00** | 0.67 |
| ambiguous_tool (5 samples — low confidence, see below) | 0.00 | 0.00 |
| ambiguous_params (5 samples — low confidence, see below) | 1.00 | 1.00 |

Full per-model results: [`gemma4-12b-20260824-191122.json`](gemma4-12b-20260824-191122.json), [`qwen3-8b-20260824-201028.json`](qwen3-8b-20260824-201028.json).

## Decisions

**NX: `gemma4-12b` is selected for the agentic tool-calling path** (unchanged
by the fixture-wording fix — the deciding factor was always
`multi_step_chained`, not `correct_tool_correct_params`). `gemma4-12b` is
top or tied-top on every well-sampled category and clean (1.00) on both
categories most relevant to FinOps governance gating. `qwen3-8b` remains
installed on the NX (`llama-server-qwen3-8b.service`, not auto-started —
see `ansible/roles/llama-cpp-jetson/README.md`) as a hedge, but is not the
default given its chained-call weakness below.

**Nano: `gemma4-e2b` is now the recommended pick, superseding the earlier
`qwen3.5-4b` confirmation.** Before the fixture-wording fix,
`correct_tool_correct_params` was the strongest signal favoring
`qwen3.5-4b` over the two Gemma edge variants (0.80 vs. 0.60-0.63). That
gap was entirely a fixture artifact and is now equalized at 1.00 for all
three. With that category no longer discriminating, `gemma4-e2b` and
`gemma4-e4b` both post a **clean 1.00 sweep across every one of the six
categories**, while `qwen3.5-4b` trails on `correct_refusal` (0.85),
`missing_required_param` (0.50 — the largest gap, on a well-sampled
20-sample category), and `ambiguous_tool` (0.00, though low-confidence).
This is not a toss-up: both Gemma variants clearly outperform
`qwen3.5-4b` on every category where they differ.

Between the two Gemma variants themselves — identical scores everywhere —
`gemma4-e2b` is the tie-breaker pick over `gemma4-e4b` for operational
reasons: `gemma4-e2b` runs at its default/native context window with no
memory issues, while `gemma4-e4b` OOM'd on the Nano's 8GB unified memory
at its default context and required an explicit `-c 4096` cap
(`ansible/roles/llama-cpp-jetson/defaults/main.yml`) to run stably at all.
Equal measured quality plus one fewer operational constraint favors
`gemma4-e2b`.

A follow-up investigation (2026-08-27, see "Key qualitative findings"
below) confirmed `gemma4-e2b`'s `ambiguous_tool` 1.00 is genuine, not
lucky — this modestly *strengthens* the case for `gemma4-e2b` rather than
creating it: the category-level comparison above already made
`gemma4-e2b` the clear pick without this result, and this just confirms
the one category where it diverged in its favor was earned.

**Not yet acted on**: `llama_active_model_nano` in
`ansible/roles/llama-cpp-jetson/defaults/main.yml` still defaults to
`qwen3.5-4b` — this summary records the updated recommendation, but
promoting `gemma4-e2b` to the deployed default is a separate follow-up
action.

## Key qualitative findings

- **The `"<team-name> team"` fixture-wording artifact (found and fixed
  2026-08-26)**: `correct-02`/`03`/`04` originally phrased the team
  identifier as "...for the `X` team" (e.g. "the analytics team"). Every
  one of the six models tested sometimes read "team" as part of the
  identifier itself, returning `team="analytics team"` instead of
  `team="analytics"` — scored `partial_params`, never `wrong_tool` or
  `hallucinated_tool`. This was universal (present in all six models, not
  specific to any size or architecture) and concentrated exactly in the
  three multi-field cases sharing that phrasing; the single-field cases
  (`correct-01`/`05`/`06`) were unaffected. Rewording the three prompts to
  `team "X"` (quoted, unambiguous) fully closed the gap — all six models
  scored a clean 1.00 on the reworded cases across 5 repeats each. This
  is the reason the numbers in this document changed between the original
  comparison and this revision; see the provenance note above and each
  result file's `patch_note`. **Lesson for future fixture design**: a
  phrasing like "`<value>` `<field-name>`" invites the model to include
  the field name in the value — prefer an explicit label/quote format
  (`field: "value"`) for any free-text identifier fixture.

- **qwen3-8b's primary weakness: `multi_step_chained` (0.67, the
  20-sample category) — unaffected by the wording fix.** A 60% rate (3/5
  repeats, on both chained cases) of firing both tool calls
  unconditionally in round 1 — before any result from the first call
  could inform whether the second should happen at all. Inspecting the
  raw transcripts: `content` was empty in every one of these repeats,
  with no reasoning trace acknowledging the prompt's "if" conditional
  anywhere. This looks like the conditional never being registered in the
  first place, not a judgment call that went wrong — a meaningfully worse
  failure mode for a governance-gating use case than an occasional
  wrong-tool pick, since it fails silently and confidently rather than
  visibly. The pattern was structurally consistent across repeats
  (near-identical `tool_calls` output each time, not scattered variation)
  and present equally on both the budget-gated (`chained-01`) and
  rate-limit-gated (`chained-02`) cases, so it isn't domain-specific.

- **gemma4-12b**: clean (1.00) on `missing_required_param` and
  `multi_step_chained`, the two governance-relevant well-sampled
  categories, and top or tied-top everywhere except the shared
  `ambiguous_tool` artifact below.

- **gemma4-e2b / gemma4-e4b**: a clean 1.00 sweep across all six
  categories, identically. See the Nano decision above for how the two
  are differentiated (operational fit, not measured quality).

- **`ambiguous_tool`**: 0.00 for `qwen3.5-4b`, `gemma4-12b`, and
  `qwen3-8b`, but **1.00 for both `gemma4-e2b` and `gemma4-e4b`** — the
  only category where the edge-tuned Gemma variants diverge from their
  12B sibling. **Investigated 2026-08-27 and confirmed genuine, not a
  classifier or fixture artifact**: pulling `repeats[].raw` for both
  models showed 5/5 repeats each with no `tool_calls` at all and a real,
  substantive clarifying question every time — consistently laying out
  both plausible interpretations (budget vs. rate-limit) and asking which
  was meant, rather than guessing. Cross-checked against
  `classify_ambiguous_tool` in `harness.py`: there is no path where a
  confident tool call scores as a pass — any `tool_calls` response is
  `wrong_tool` (or `hallucinated_tool`) regardless of which of the two
  plausible tools was picked, so the 1.00 is only reachable via correctly
  declining and asking. This is a materially stronger, more reproducible
  signal than `qwen3.5-4b`'s one genuine clarifying question out of 5 in
  an earlier fresh re-run (1/5, not its dominant behavior) — the two Gemma
  edge variants did this **every single time**.

  This finding being *confirmed real* should not be conflated with it
  being *general*: this is still an n=1 fixture case (5 samples), flagged
  as low-confidence per the sample-size note in `../README.md`. It is a
  genuine, well-evidenced data point about how these two models handle
  *this specific ambiguity pattern* — not a general claim about either
  Gemma variant's ambiguity-handling overall, which would need a second,
  differently-worded `ambiguous_tool` fixture to establish. Separately,
  the fixture-wording lean noted earlier still holds: all three 0.00-
  scoring models independently defaulted to `get_budget_status` on this
  prompt ("something's off with the team's API usage"), suggesting the
  wording reads as budget-framing rather than genuinely balanced — worth
  adding a second, more neutrally-framed `ambiguous_tool` case before
  trusting this category's score more broadly in a future comparison.
