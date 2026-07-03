#!/usr/bin/env bash
# scripts/bmc/bmc-power.sh
# Usage: ./bmc-power.sh status|on|off|reset|cycle [1-4|all]
set -euo pipefail
[[ -f "$HOME/.turingpi" ]] && source "$HOME/.turingpi"
TPI="tpi --host ${BMC_IP} --user ${BMC_USER} --password ${BMC_PASSWORD}"

CMD="${1:-status}"; NODE="${2:-}"

case "$CMD" in
  status) $TPI power status ;;
  on|off|reset)
    if [[ "$NODE" == "all" ]]; then
      for n in 1 2 3 4; do $TPI power "$CMD" --node "$n"; sleep 1; done
    else
      $TPI power "$CMD" --node "$NODE"
    fi ;;
  cycle)
    $TPI power off --node "$NODE"; sleep 3; $TPI power on --node "$NODE"
    echo "✓ Node $NODE cycled" ;;
  *) echo "Usage: $0 {status|on|off|reset|cycle} [1-4|all]"; exit 1 ;;
esac
