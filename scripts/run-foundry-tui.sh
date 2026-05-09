#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_DIR="$ROOT_DIR/third_party/hermes"
TUI_DIR="$HERMES_DIR/ui-tui"

export HERMES_TUI_BACKEND="${HERMES_TUI_BACKEND:-foundry}"
export HERMES_FOUNDRY_ENDPOINT="${HERMES_FOUNDRY_ENDPOINT:-http://127.0.0.1:8088}"
export HERMES_FOUNDRY_AGENT_NAME="${HERMES_FOUNDRY_AGENT_NAME:-hermes-foundry-agent}"
export HERMES_PYTHON_SRC_ROOT="${HERMES_PYTHON_SRC_ROOT:-$HERMES_DIR}"
export HERMES_CWD="${HERMES_CWD:-$ROOT_DIR}"

if [[ -z "${HERMES_FOUNDRY_INVOCATIONS_PATH+x}" ]]; then
  case "$HERMES_FOUNDRY_ENDPOINT" in
    http://127.0.0.1|http://127.0.0.1:*|http://localhost|http://localhost:*)
      export HERMES_FOUNDRY_INVOCATIONS_PATH="/invocations"
      ;;
  esac
fi

if [[ -z "${HERMES_PYTHON:-}" ]]; then
  for candidate in python3.13 python3.12 python3.11 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
      export HERMES_PYTHON="$(command -v "$candidate")"
      break
    fi
  done
fi

if [[ -z "${HERMES_PYTHON:-}" ]]; then
  echo "Hermes TUI requires Python 3.11 or newer. Set HERMES_PYTHON to a compatible interpreter." >&2
  exit 1
fi

if [[ ! -d "$TUI_DIR/node_modules" ]]; then
  echo "ui-tui dependencies are missing. Run: cd third_party/hermes/ui-tui && npm install" >&2
  exit 1
fi

cd "$TUI_DIR"

if [[ ! -f packages/hermes-ink/dist/entry-exports.js ]]; then
  npm run build --prefix packages/hermes-ink
fi

exec npm start
