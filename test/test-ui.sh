#!/usr/bin/env bash
# ABOUTME: Unit tests for limpet's UI/animation helpers — pure functions, no TTY required.
# ABOUTME: Sources limpet (guarded main) and asserts _human_kb / _bar_str / _spin_frame / _ui_animated.
set -uo pipefail

LIMPET="$(cd "$(dirname "$0")/.." && pwd)/limpet"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export LIMPET_CONFIG_DIR="$SB/config"
export LIMPET_STATE_DIR="$SB/state"
export NO_COLOR=1

# shellcheck disable=SC1090
source "$LIMPET"   # must NOT run main (source-guard); just defines helpers

pass=0; fail=0
eq(){ if [ "$2" = "$3" ]; then printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1));
      else printf '  \033[31mFAIL\033[0m %s  (got:[%s] want:[%s])\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

echo "[human_kb]"
eq "512 KB"  "$(_human_kb 512)"     "512 KB"
eq "0 KB"    "$(_human_kb 0)"       "0 KB"
eq "1 MB"    "$(_human_kb 1024)"    "1 MB"
eq "240 MB"  "$(_human_kb 245760)"  "240 MB"
eq "1.5 GB"  "$(_human_kb 1572864)" "1.5 GB"
eq "2.0 GB"  "$(_human_kb 2097152)" "2.0 GB"

echo "[bar_str]"
eq "0%"          "$(_bar_str 0 8)"   "░░░░░░░░"
eq "50%"         "$(_bar_str 50 8)"  "████░░░░"
eq "100%"        "$(_bar_str 100 8)" "████████"
eq "53% partial" "$(_bar_str 53 8)"  "████▏░░░"

echo "[spin_frame]"
eq "frame 0"  "$(_spin_frame 0)"  "⠋"
eq "frame 3"  "$(_spin_frame 3)"  "⠸"
eq "wrap 10"  "$(_spin_frame 10)" "⠋"

echo "[ui_animated is false under NO_COLOR]"
_ui_animated; eq "gated off" "$?" "1"

echo "[copy engine — off-TTY is silent + correct]"
csrc="$SB/csrc"; mkdir -p "$csrc/sub"; echo hi > "$csrc/a.txt"; echo yo > "$csrc/sub/b.txt"
cdst="$SB/cdst"
out="$( _run_poll -1 "$cdst" -- ditto "$csrc" "$cdst" 2>&1 )"; st=$?
eq "copy exit 0"          "$st" "0"
eq "a.txt copied"         "$(cat "$cdst/a.txt" 2>/dev/null)"     "hi"
eq "sub/b.txt copied"     "$(cat "$cdst/sub/b.txt" 2>/dev/null)" "yo"
escs="$(printf '%s' "$out" | LC_ALL=C tr -dc '\033' | wc -c | tr -d ' ')"
eq "no ESC bytes off-TTY" "$escs" "0"

echo "[move_to_drive — copy, verify, swap to symlink]"
msrc="$SB/Docs"; mkdir -p "$msrc"; echo data > "$msrc/f.txt"
mdst="$SB/drv/Docs"; mkdir -p "$SB/drv"
move_to_drive "$msrc" "$mdst" "Docs" >/dev/null 2>&1
eq "src is a symlink" "$([ -L "$msrc" ] && echo yes)" "yes"
eq "symlink → dst"    "$(readlink "$msrc")"           "$mdst"
eq "data on drive"    "$(cat "$mdst/f.txt")"          "data"

echo "[spin — returns child status, silent off-TTY]"
out="$( spin "ok step" -- true 2>&1 )";  eq "spin true → 0"  "$?" "0"
eq "spin silent off-tty (true)" "$(printf '%s' "$out" | LC_ALL=C tr -dc '\033' | wc -c | tr -d ' ')" "0"
spin "bad step" -- false >/dev/null 2>&1; eq "spin false → 1" "$?" "1"

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
