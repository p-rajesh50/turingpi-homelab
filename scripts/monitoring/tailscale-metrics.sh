#!/usr/bin/env bash
# Writes a tailscale_up gauge for node-exporter's textfile collector.
# Runs on rk1-control only (the only node Tailscale is installed on).
set -euo pipefail

OUT_DIR="/var/lib/node_exporter/textfile_collector"
OUT_FILE="${OUT_DIR}/tailscale.prom"
TMP_FILE="${OUT_FILE}.$$"

if tailscale status --json >/dev/null 2>&1; then
  UP=1
else
  UP=0
fi

echo "# HELP tailscale_up Whether tailscaled is up and reachable (1) or not (0)" > "$TMP_FILE"
echo "# TYPE tailscale_up gauge" >> "$TMP_FILE"
echo "tailscale_up ${UP}" >> "$TMP_FILE"

mv "$TMP_FILE" "$OUT_FILE"
