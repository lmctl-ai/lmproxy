#!/usr/bin/env bash
set -euo pipefail
MIN_VERSION="0.2.456"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lmcode-compiler-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) WORK="$(cd "$WORK" && pwd -W | tr '\\' '/')" ;;
esac
candidate="${LMSCRIPT_BIN:-}"
if [[ -z "$candidate" ]]; then candidate="$(command -v lmscript || true)"; fi
if [[ -z "$candidate" ]]; then echo "error: no lmscript compiler found; install @lmctl-ai/lmctl >= $MIN_VERSION or set LMSCRIPT_BIN" >&2; exit 2; fi
SCHEMA="$WORK/lmproxy-probe.schema.json"
PROBE="$WORK/probe.lms"
cat > "$SCHEMA" <<'JSON'
{"dsl.schema":2,"name":"lmproxy_probe","types":{},"functions":{},"context":{}}
JSON
python3 - "$SCHEMA" "$PROBE" <<'PY_PROBE'
import json, pathlib, sys
schema, probe = sys.argv[1:]
source = (f'program = _lmcode_ schema={json.dumps(schema)};\n'
          'let value = <<~LM_PROXY_PROBE;\n'
          '  byte-oriented lmcode\n'
          'LM_PROXY_PROBE\n'
          '$return = str_len(value);\n'
          'end _lmcode_\n'
          'let result = run_lmcode(program);\n')
pathlib.Path(probe).write_text(source)
PY_PROBE
"$candidate" --check "$PROBE" >"$WORK/compiler.out" 2>"$WORK/compiler.err" || { cat "$WORK/compiler.err" >&2; exit 2; }
"$candidate" --lmcode-signatures "$SCHEMA" | grep -Fq 'fn str_len(string) -> int' || { echo "error: compiler inspection surface lacks implicit std fn str_len(string) -> int" >&2; exit 2; }
printf '%s\n' "$candidate"
