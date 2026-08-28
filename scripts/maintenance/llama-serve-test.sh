#!/bin/bash
# scripts/maintenance/llama-serve-test.sh
# Smoke test for the llama-server units deployed by ansible/roles/llama-cpp-jetson.
# Curls /v1/chat/completions on each known port and checks for a real
# completion. Every model on both hosts is part of a mutually-exclusive
# group now (systemd Conflicts= — orin-nx: 2-way, orin-nano: 3-way), so a
# connection failure on any single port is expected whenever a different
# model on that host is the one currently active — flagged as SKIP, not
# FAIL.
set -u

TARGETS=(
  "orin-nano:10.0.0.50:8081:qwen3.5-4b"
  "orin-nano:10.0.0.50:8082:gemma4-e2b"
  "orin-nano:10.0.0.50:8083:gemma4-e4b"
  "orin-nx:10.0.0.14:8081:gemma4-12b"
  "orin-nx:10.0.0.14:8082:qwen3-8b"
)

fail=0
for target in "${TARGETS[@]}"; do
  IFS=':' read -r host ip port label <<< "$target"
  # max_tokens raised well past 16: these are reasoning-tuned models whose
  # /v1/chat/completions responses spend tokens on `reasoning_content`
  # (thinking) before any `content` — a small budget can exhaust entirely
  # on thinking and legitimately return empty `content` on a healthy server.
  resp=$(curl -sf -m 60 -X POST "http://${ip}:${port}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Say OK."}],"max_tokens":128}')
  rc=$?

  if [ $rc -ne 0 ]; then
    echo "SKIP  ${host} ${label} (${ip}:${port}) — not running (expected: only one model per host runs at a time)"
    continue
  fi

  # Accept either field as evidence of a real completion — a reasoning
  # model that only fills reasoning_content within the token budget is
  # still a working server, not a broken one.
  content=$(echo "$resp" | jq -r '.choices[0].message.content // empty')
  reasoning=$(echo "$resp" | jq -r '.choices[0].message.reasoning_content // empty')
  if [ -z "$content" ] && [ -z "$reasoning" ]; then
    echo "FAIL  ${host} ${label} (${ip}:${port}) — 200 but no content or reasoning_content in response: $resp"
    fail=1
  else
    shown="${content:-$reasoning}"
    echo "OK    ${host} ${label} (${ip}:${port}) — \"$(echo "$shown" | tr -d '\n' | cut -c1-60)\""
  fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "One or more expected-active servers failed the smoke test."
  exit 1
fi

echo
echo "All expected-active llama-server endpoints responded correctly."
