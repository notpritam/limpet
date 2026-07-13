#!/usr/bin/env bash
# ABOUTME: Unit test for limpet's version-picking logic (used by the update check's git-ls-remote fallback).
# ABOUTME: Feeds sample `git ls-remote --tags` output to `limpet __pick-max-semver`; asserts correct numeric-semver max.
set -uo pipefail

LIMPET="$(cd "$(dirname "$0")/.." && pwd)/limpet"
pass=0; fail=0
ck(){ if [ "$2" = "$3" ]; then printf '  \033[32mok\033[0m   %s (%s)\n' "$1" "$3"; pass=$((pass+1)); else printf '  \033[31mFAIL\033[0m %s: got "%s" want "%s"\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

echo "[1] picks the highest tag, numeric (not lexical) — 0.10.0 > 0.9.0 > 0.3.1"
out="$(printf '%s\n' \
  'abc123	refs/tags/v0.3.0' \
  'def456	refs/tags/v0.9.0' \
  'aaa111	refs/tags/v0.10.0' \
  'bbb222	refs/tags/v0.3.1' | "$LIMPET" __pick-max-semver)"
ck "numeric semver max" "$out" "0.10.0"

echo "[2] tolerates non-tag noise and the ^{} deref lines"
out="$(printf '%s\n' \
  'sha	refs/heads/main' \
  'sha	refs/tags/v1.2.3' \
  'sha	refs/tags/v1.2.3^{}' \
  'sha	refs/tags/v1.10.4' | "$LIMPET" __pick-max-semver)"
ck "ignores refs/heads + picks max" "$out" "1.10.4"

echo "[3] handles bare (no 'v' prefix) tags"
out="$(printf '%s\n' '2.0.0' '2.0.1' '2.1.0' | "$LIMPET" __pick-max-semver)"
ck "bare semver max" "$out" "2.1.0"

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
