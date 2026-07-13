#!/usr/bin/env bash
# ABOUTME: End-to-end test for `limpet env` — the drive-aware build-cache env-var offload.
# ABOUTME: Sandboxes HOME + a fake drive; asserts --shell output (present/absent), eval, and add/rm/validation.
set -uo pipefail

LIMPET="$(cd "$(dirname "$0")/.." && pwd)/limpet"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export HOME="$SB"                       # sandbox home — config/env.conf key off $HOME
export LIMPET_STATE_DIR="$SB/state"     # keep logs/locks in the sandbox
DRV="$SB/X9"; mkdir -p "$DRV/Caches/go-build" "$DRV/Caches/go-mod" "$DRV/Android/sdk"

mkdir -p "$SB/.config/limpet"
cat > "$SB/.config/limpet/config" <<EOF
DRIVE=$DRV
FOLDERS=(Documents Downloads)
MIRROR_DEST=$SB/.limpet/mirror
AUTO_UPDATE=0
GUARD_INTERVAL=0
EOF
cat > "$SB/.config/limpet/env.conf" <<EOF
# managed env
GOCACHE          = Caches/go-build
GOMODCACHE       = Caches/go-mod
ANDROID_HOME     = Android/sdk
EOF

pass=0; fail=0
ck(){ if eval "$2"; then printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); else printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); fi; }

echo "[1] drive present → env --shell emits an export per mapping, resolved under the drive"
OUT="$("$LIMPET" env --shell)"
ck "3 export lines"                  '[ "$(printf "%s\n" "$OUT" | grep -c "^export ")" = 3 ]'
ck "GOCACHE → drive path"            'printf "%s\n" "$OUT" | grep -q "^export GOCACHE=$DRV/Caches/go-build$"'
ck "ANDROID_HOME → drive path"       'printf "%s\n" "$OUT" | grep -q "^export ANDROID_HOME=$DRV/Android/sdk$"'
ck "no unset lines when present"     '! printf "%s\n" "$OUT" | grep -q "^unset "'

echo "[2] eval of --shell actually sets the variables in this shell"
eval "$OUT"
ck "GOCACHE exported correctly"      '[ "${GOCACHE:-}" = "$DRV/Caches/go-build" ]'
ck "GOMODCACHE exported correctly"   '[ "${GOMODCACHE:-}" = "$DRV/Caches/go-mod" ]'

echo "[3] drive ABSENT → no exports; stale inherited vars are unset"
mv "$DRV" "$DRV.away"
OUT="$("$LIMPET" env --shell)"
ck "no export lines when absent"     '! printf "%s\n" "$OUT" | grep -q "^export "'
ck "unset GOCACHE emitted"           'printf "%s\n" "$OUT" | grep -q "^unset GOCACHE"'
ck "unset ANDROID_HOME emitted"      'printf "%s\n" "$OUT" | grep -q "^unset ANDROID_HOME"'
mv "$DRV.away" "$DRV"

echo "[4] env add upserts a mapping; env rm removes it"
"$LIMPET" env add NPM_CONFIG_CACHE Caches/npm >/dev/null
mkdir -p "$DRV/Caches/npm"
OUT="$("$LIMPET" env --shell)"
ck "added var appears"               'printf "%s\n" "$OUT" | grep -q "^export NPM_CONFIG_CACHE=$DRV/Caches/npm$"'
"$LIMPET" env add GOCACHE Caches/go-build2 >/dev/null    # upsert existing
mkdir -p "$DRV/Caches/go-build2"
OUT="$("$LIMPET" env --shell)"
ck "upsert changes existing path"    'printf "%s\n" "$OUT" | grep -q "^export GOCACHE=$DRV/Caches/go-build2$"'
ck "upsert did not duplicate"        '[ "$(printf "%s\n" "$OUT" | grep -c "^export GOCACHE=")" = 1 ]'
"$LIMPET" env rm GOCACHE >/dev/null
OUT="$("$LIMPET" env --shell)"
ck "removed var is gone"             '! printf "%s\n" "$OUT" | grep -q "^export GOCACHE="'

echo "[5] invalid identifiers are rejected (config not corrupted)"
ck "rejects bad var name"            '! "$LIMPET" env add "9bad name" foo >/dev/null 2>&1'
ck "rejects empty path"              '! "$LIMPET" env add GOOD "" >/dev/null 2>&1'

echo "[5b] hand-edited env.conf: malformed / injectable names are NEVER emitted to the rc eval"
# env.conf is hand-editable (limpet env edit) and its output is eval'd in every shell.
# printf (not heredoc) so the $(...) payload lands literally in the file, not run at test-setup.
rm -f "$SB/INJECTED"
printf 'GOCACHE = Caches/go-build\nx$(touch %s/INJECTED) = Caches/evil\nMY VAR = Caches/typo\n   # GRADLE_USER_HOME = Caches/indented\n' "$SB" > "$SB/.config/limpet/env.conf"
OUT="$("$LIMPET" env --shell)"
ck "valid var still emitted"         'printf "%s\n" "$OUT" | grep -q "^export GOCACHE="'
ck "no command-substitution emitted" '! printf "%s\n" "$OUT" | grep -q "touch"'
eval "$OUT"
ck "eval is inert (no injection)"    '[ ! -e "$SB/INJECTED" ]'
ck "space-in-name not emitted"       '! printf "%s\n" "$OUT" | grep -q "MY VAR"'
ck "indented comment not a mapping"  '! printf "%s\n" "$OUT" | grep -q "GRADLE_USER_HOME"'
ck "exactly the 1 valid export"      '[ "$(printf "%s\n" "$OUT" | grep -c "^export ")" = 1 ]'

echo "[6] not-set-up / absent config → --shell is silent and succeeds (safe in rc)"
rm -f "$SB/.config/limpet/config"
ck "silent when not set up"          '[ -z "$("$LIMPET" env --shell 2>/dev/null)" ] && "$LIMPET" env --shell >/dev/null 2>&1'

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
