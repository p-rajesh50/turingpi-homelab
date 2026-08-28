#!/usr/bin/env python3
"""
tools/tool-calling-harness/harness.py

Manual dev-time test harness for scoring an OpenAI-compatible
/v1/chat/completions endpoint (llama-server, LiteLLM, etc.) on tool-calling
reliability, against the fixtures in fixtures.json. Parameterized by
--base-url/--model so the same script runs against any candidate model.

Not an Ansible role, not wired into any automation — run manually:
    python3 harness.py --base-url http://10.0.0.50:8081 --model qwen3.5-4b

See README.md for the classification-label design and scoring rationale.
"""
import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error

KNOWN_TOOLS = {"get_budget_status", "create_api_key", "check_rate_limit"}

# Weight rationale lives in README.md — kept here as the single source of
# truth the scoring logic actually reads from.
SCORE_WEIGHTS = {
    "correct_tool_correct_params": 1.0,
    "correct_refusal": 1.0,
    "missing_clarification": 1.0,
    "partial_params": 0.5,
    "ambiguous_param_guess": -1.0,
    "wrong_tool": -1.0,
    "hallucinated_tool": -1.5,
    "chained_correct": 1.0,
    "wrong_tool_sequence": -0.5,
    "incomplete_chain": -0.5,
    "chained_correct_gate_respected": 1.0,
    "chained_silent_gate": -0.25,
    "chained_gate_ignored": -1.5,
    "premature_unconditional_chain": -1.5,
}

CLARIFYING_HINTS = [
    "?", "which team", "what team", "which key", "what key", "which scope",
    "what scope", "could you clarify", "can you clarify", "can you specify",
    "could you specify", "let me know", "please provide", "please specify",
    "not sure which", "need to know",
]


def post_chat(base_url, model, messages, tools, temperature, top_p, timeout=180):
    url = base_url.rstrip("/") + "/v1/chat/completions"
    body = {
        "model": model,
        "messages": messages,
        "tools": tools,
        "temperature": temperature,
        "top_p": top_p,
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def extract_message(response):
    return response["choices"][0]["message"]


def get_tool_calls(message):
    return message.get("tool_calls") or []


def parse_call_args(call):
    try:
        return json.loads(call["function"]["arguments"])
    except (KeyError, json.JSONDecodeError, TypeError):
        return {}


def params_match(expected, actual):
    if set(expected.keys()) - set(actual.keys()):
        return False
    for k, v in expected.items():
        av = actual.get(k)
        if isinstance(v, list) and isinstance(av, list):
            if sorted(v) != sorted(av):
                return False
        elif av != v:
            return False
    return True


def looks_like_clarifying_question(content):
    if not content:
        return False
    lowered = content.lower()
    return any(hint in lowered for hint in CLARIFYING_HINTS)


def content_mentions_any(content, keywords):
    if not content:
        return False
    lowered = content.lower()
    return any(kw.lower() in lowered for kw in keywords)


def classify_single_call(call, expected_tool):
    name = call["function"]["name"]
    if name not in KNOWN_TOOLS:
        return "hallucinated_tool"
    if name != expected_tool:
        return "wrong_tool"
    return None  # caller checks params


def classify_correct_tool_correct_params(case, message):
    calls = get_tool_calls(message)
    if len(calls) != 1:
        return "wrong_tool" if calls else "missing_clarification"
    verdict = classify_single_call(calls[0], case["expected_tool"])
    if verdict:
        return verdict
    args = parse_call_args(calls[0])
    if params_match(case["expected_params"], args):
        return "correct_tool_correct_params"
    return "partial_params"


def classify_correct_refusal(case, message):
    calls = get_tool_calls(message)
    if not calls:
        return "correct_refusal" if message.get("content") else "wrong_tool"
    name = calls[0]["function"]["name"]
    return "hallucinated_tool" if name not in KNOWN_TOOLS else "wrong_tool"


def classify_missing_required_param(case, message):
    calls = get_tool_calls(message)
    if not calls:
        if looks_like_clarifying_question(message.get("content")):
            return "missing_clarification"
        return "wrong_tool"
    verdict = classify_single_call(calls[0], case["expected_tool"])
    if verdict:
        return verdict
    args = parse_call_args(calls[0])
    if case["missing_field"] not in args or not args.get(case["missing_field"]):
        return "missing_clarification"
    return "partial_params"


def classify_ambiguous_tool(case, message):
    calls = get_tool_calls(message)
    if not calls:
        if looks_like_clarifying_question(message.get("content")):
            return "missing_clarification"
        return "wrong_tool"
    name = calls[0]["function"]["name"]
    if name not in KNOWN_TOOLS:
        return "hallucinated_tool"
    return "wrong_tool"  # confidently picked one of several plausible tools


def classify_ambiguous_params(case, message):
    calls = get_tool_calls(message)
    if not calls:
        if looks_like_clarifying_question(message.get("content")):
            return "missing_clarification"
        return "wrong_tool"
    name = calls[0]["function"]["name"]
    if name not in KNOWN_TOOLS:
        return "hallucinated_tool"
    if name != case["expected_tool"]:
        return "wrong_tool"
    return "ambiguous_param_guess"


def round_raw(message):
    return {
        "tool_calls": get_tool_calls(message) or None,
        "content": message.get("content", ""),
    }


def run_chained_case(case, tools, base_url, model, temperature, top_p, request_timeout):
    """Returns a list of (branch, label, raw) tuples — one entry if round 1
    already fired both calls (short-circuit), else two entries
    (favorable, unfavorable). `raw` always includes round1; round2 is None
    when no second round was run (short-circuit or first tool never called)."""
    first_tool, second_tool = case["expected_tool_sequence"]
    user_msg = {"role": "user", "content": case["prompt"]}
    r1 = post_chat(base_url, model, [user_msg], tools, temperature, top_p, timeout=request_timeout)
    msg1 = extract_message(r1)
    calls1 = get_tool_calls(msg1)
    call_names1 = [c["function"]["name"] for c in calls1]
    round1_raw = round_raw(msg1)

    if first_tool in call_names1 and second_tool in call_names1:
        return [("both", "premature_unconditional_chain", {"round1": round1_raw, "round2": None})]

    if first_tool not in call_names1:
        # didn't even call the first tool — treat as incomplete on both branches
        raw = {"round1": round1_raw, "round2": None}
        return [
            ("favorable", "incomplete_chain", raw),
            ("unfavorable", "incomplete_chain", raw),
        ]

    first_call = next(c for c in calls1 if c["function"]["name"] == first_tool)
    results = []
    for branch, synthetic_key in (
        ("favorable", "synthetic_result_favorable"),
        ("unfavorable", "synthetic_result_unfavorable"),
    ):
        assistant_msg = {
            "role": "assistant",
            "content": msg1.get("content"),
            "tool_calls": [first_call],
        }
        tool_result_msg = {
            "role": "tool",
            "tool_call_id": first_call.get("id", "call_1"),
            "content": json.dumps(case[synthetic_key]),
        }
        r2 = post_chat(
            base_url, model,
            [user_msg, assistant_msg, tool_result_msg],
            tools, temperature, top_p,
            timeout=request_timeout,
        )
        msg2 = extract_message(r2)
        calls2 = get_tool_calls(msg2)
        call_names2 = [c["function"]["name"] for c in calls2]
        round2_raw = round_raw(msg2)

        if branch == "favorable":
            if second_tool in call_names2:
                label = "chained_correct"
            elif calls2:
                label = "wrong_tool_sequence"
            else:
                label = "incomplete_chain"
        else:
            if second_tool in call_names2:
                label = "chained_gate_ignored"
            elif calls2:
                label = "wrong_tool_sequence"
            elif content_mentions_any(msg2.get("content"), case["gate_keywords"]):
                label = "chained_correct_gate_respected"
            else:
                label = "chained_silent_gate"
        results.append((branch, label, {"round1": round1_raw, "round2": round2_raw}))
    return results


CLASSIFIERS = {
    "correct_tool_correct_params": classify_correct_tool_correct_params,
    "correct_refusal": classify_correct_refusal,
    "missing_required_param": classify_missing_required_param,
    "ambiguous_tool": classify_ambiguous_tool,
    "ambiguous_params": classify_ambiguous_params,
}


def run_case(case, tools, base_url, model, repeats, temperature, top_p, request_timeout):
    """Returns a list of dicts: {branch, label, raw} across all repeats.
    `raw` is always present (never behind a flag) so a borderline or
    surprising label can be investigated later straight from the saved
    JSON, without needing to re-query a model that may no longer be
    running or may not reproduce the same sample.

    Any single request failure (HTTP error, connection timeout, malformed
    JSON) is caught per-repeat and recorded as an "error" outcome rather
    than propagating — a slow/failed request on one repeat must not lose
    every result already collected in this run. TimeoutError/OSError are
    caught explicitly since neither is a urllib.error.URLError subclass."""
    outcomes = []
    for _ in range(repeats):
        try:
            if case["category"] == "multi_step_chained":
                for branch, label, raw in run_chained_case(
                    case, tools, base_url, model, temperature, top_p, request_timeout
                ):
                    outcomes.append({"branch": branch, "label": label, "raw": raw})
            else:
                classifier = CLASSIFIERS[case["category"]]
                user_msg = {"role": "user", "content": case["prompt"]}
                resp = post_chat(base_url, model, [user_msg], tools, temperature, top_p, timeout=request_timeout)
                message = extract_message(resp)
                label = classifier(case, message)
                outcomes.append({"branch": "single", "label": label, "raw": round_raw(message)})
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError, KeyError, json.JSONDecodeError) as e:
            outcomes.append({"branch": "error", "label": "error", "raw": None, "error": str(e)})
    return outcomes


def summarize_case(case, outcomes):
    good_labels = {
        "correct_tool_correct_params": {"correct_tool_correct_params"},
        "correct_refusal": {"correct_refusal"},
        "missing_required_param": {"missing_clarification"},
        "ambiguous_tool": {"missing_clarification"},
        "ambiguous_params": {"missing_clarification"},
        "multi_step_chained": {"chained_correct", "chained_correct_gate_respected"},
    }[case["category"]]

    by_branch = {}
    for o in outcomes:
        by_branch.setdefault(o["branch"], []).append(o)

    summary = {"case_id": case["id"], "category": case["category"], "branches": {}}
    for branch, branch_outcomes in by_branch.items():
        n = len(branch_outcomes)
        scored = [o for o in branch_outcomes if o["label"] != "error"]
        passes = sum(1 for o in scored if o["label"] in good_labels)
        weighted = sum(SCORE_WEIGHTS.get(o["label"], 0.0) for o in scored)
        labels_seen = [o["label"] for o in branch_outcomes]
        dominant = max(set(labels_seen), key=labels_seen.count) if labels_seen else "n/a"
        summary["branches"][branch] = {
            "n": n,
            "pass_rate": passes / n if n else 0.0,
            "weighted_score": weighted,
            "dominant_label": dominant,
            "labels": labels_seen,
            # Full per-repeat transcript detail (label + raw tool_calls/content,
            # both rounds for chained cases) — always persisted, not gated
            # behind a flag, so a borderline score can be investigated later
            # from the saved JSON alone.
            "repeats": [
                {"label": o["label"], "raw": o["raw"], **({"error": o["error"]} if "error" in o else {})}
                for o in branch_outcomes
            ],
        }
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", required=True)
    here = os.path.dirname(os.path.abspath(__file__))
    parser.add_argument("--fixtures", default=os.path.join(here, "fixtures.json"))
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--temperature", type=float, default=0.6)
    parser.add_argument("--top-p", type=float, default=0.95)
    parser.add_argument("--request-timeout", type=int, default=180,
                         help="Per-request socket timeout in seconds (default 180). "
                              "Larger models may need more headroom than smaller ones.")
    parser.add_argument("--case-ids", default=None,
                         help="Comma-separated case IDs to run instead of the full fixture "
                              "set (e.g. --case-ids correct-02,correct-03,correct-04). "
                              "Useful for targeted re-tests after a fixture wording fix, "
                              "without re-running the whole suite. Unknown IDs are an error.")
    parser.add_argument("--output-dir", default=os.path.join(here, "results"))
    args = parser.parse_args()

    with open(args.fixtures) as f:
        fixtures = json.load(f)
    tools = fixtures["tools"]
    cases = fixtures["cases"]

    if args.case_ids:
        wanted = [c.strip() for c in args.case_ids.split(",") if c.strip()]
        by_id = {c["id"]: c for c in cases}
        unknown = [c for c in wanted if c not in by_id]
        if unknown:
            parser.error(f"Unknown case ID(s) in --case-ids: {', '.join(unknown)}")
        cases = [by_id[c] for c in wanted]

    os.makedirs(args.output_dir, exist_ok=True)
    timestamp = time.strftime("%Y%m%d-%H%M%S")
    safe_model = args.model.replace("/", "_")

    all_summaries = []
    for case in cases:
        print(f"Running {case['id']} ({case['category']})...", file=sys.stderr)
        outcomes = run_case(
            case, tools, args.base_url, args.model,
            args.repeats, args.temperature, args.top_p, args.request_timeout,
        )
        all_summaries.append(summarize_case(case, outcomes))

    category_rollup = {}
    for s in all_summaries:
        cat = s["category"]
        category_rollup.setdefault(cat, {"pass_rates": [], "weighted_scores": []})
        for branch_data in s["branches"].values():
            category_rollup[cat]["pass_rates"].append(branch_data["pass_rate"])
            category_rollup[cat]["weighted_scores"].append(branch_data["weighted_score"])

    category_summary = {
        cat: {
            "mean_pass_rate": sum(d["pass_rates"]) / len(d["pass_rates"]),
            "mean_weighted_score": sum(d["weighted_scores"]) / len(d["weighted_scores"]),
        }
        for cat, d in category_rollup.items()
    }

    result = {
        "model": args.model,
        "base_url": args.base_url,
        "timestamp": timestamp,
        "repeats": args.repeats,
        "temperature": args.temperature,
        "top_p": args.top_p,
        "request_timeout": args.request_timeout,
        "case_ids_filter": args.case_ids,
        "cases": all_summaries,
        "category_summary": category_summary,
        "score_weights": SCORE_WEIGHTS,
    }

    json_path = os.path.join(args.output_dir, f"{safe_model}-{timestamp}.json")
    with open(json_path, "w") as f:
        json.dump(result, f, indent=2)

    md_path = os.path.join(args.output_dir, f"{safe_model}-{timestamp}.md")
    with open(md_path, "w") as f:
        f.write(f"# Tool-calling harness results — {args.model}\n\n")
        f.write(f"Base URL: `{args.base_url}` — repeats: {args.repeats} — "
                f"temp: {args.temperature} — top_p: {args.top_p} — run: {timestamp}\n\n")
        f.write("## Per-category summary\n\n")
        f.write("| Category | Mean pass rate | Mean weighted score |\n|---|---|---|\n")
        for cat, s in category_summary.items():
            f.write(f"| {cat} | {s['mean_pass_rate']:.2f} | {s['mean_weighted_score']:.2f} |\n")
        f.write("\n## Per-case detail\n\n")
        f.write("| Case | Category | Branch | Pass rate | Weighted score | Dominant label |\n")
        f.write("|---|---|---|---|---|---|\n")
        for s in all_summaries:
            for branch, bd in s["branches"].items():
                f.write(
                    f"| {s['case_id']} | {s['category']} | {branch} | "
                    f"{bd['pass_rate']:.2f} ({int(bd['pass_rate']*bd['n'])}/{bd['n']}) | "
                    f"{bd['weighted_score']:.2f} | {bd['dominant_label']} |\n"
                )

    print(f"\nWrote {json_path}")
    print(f"Wrote {md_path}\n")
    print("Per-category summary:")
    for cat, s in category_summary.items():
        print(f"  {cat}: pass_rate={s['mean_pass_rate']:.2f} weighted_score={s['mean_weighted_score']:.2f}")


if __name__ == "__main__":
    main()
