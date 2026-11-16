#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
cmd="${1:-install}"
case "$cmd" in
  install|update|uninstall|enable-timer|disable-timer|status|help)
    exec make "$cmd"
    ;;
  *)
    echo "Usage: $0 {install|update|uninstall|status}" >&2
    exit 1
    ;;
esac
