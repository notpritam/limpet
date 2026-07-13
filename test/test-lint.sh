#!/usr/bin/env bash
# ABOUTME: Source lint — forbid pipefail-unsafe `<command> | grep -q` (the early-exit consumer SIGPIPEs the
# ABOUTME: producer, so under `set -o pipefail` the pipeline returns non-zero even on success). grep -q on a FILE is fine.
set -uo pipefail

LIMPET="$(cd "$(dirname "$0")/.." && pwd)/limpet"
pass=0; fail=0
ck(){ if eval "$2"; then printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); else printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); fi; }

echo "[1] no pipefail-unsafe '<command> | grep -q' (SIGPIPEs the producer under set -o pipefail)"
# -n keeps real line numbers; drop matches that live inside a comment (`<line>:<spaces>#…`) so the
# invariant's own explanatory comments don't trip it.
hits="$(grep -nE '(launchctl|mount|find|ls |curl|df |diskutil)[^|]*\| *grep -q' "$LIMPET" | grep -vE ':[[:space:]]*#' || true)"
[ -n "$hits" ] && { echo "    offending lines (capture the producer first, e.g. case \"\$(cmd)\" in *pat*):"; printf '%s\n' "$hits" | sed 's/^/      /'; }
ck "zero command|grep -q pipes" '[ -z "$hits" ]'

echo "[2] the script parses under /bin/bash (3.2 gate)"
ck "bash -n clean" '/bin/bash -n "$LIMPET"'

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
