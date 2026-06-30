#!/usr/bin/env bash
# ABOUTME: End-to-end test for limpet's failover/failback core on a REAL temp filesystem (no mocks).
# ABOUTME: Sandboxes HOME + a fake drive; asserts symlink/failover/offline-edit/failback/keep-both/no-data-loss.
set -uo pipefail

LIMPET="$(cd "$(dirname "$0")/.." && pwd)/limpet"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export HOME="$SB"                       # sandbox home — the guard keys off $HOME
export LIMPET_STATE_DIR="$SB/state"     # keep logs/locks in the sandbox
DRV="$SB/X9"; mkdir -p "$DRV"           # fake external drive

mkdir -p "$SB/.config/limpet"
cat > "$SB/.config/limpet/config" <<EOF
DRIVE=$DRV
FOLDERS=(Documents Downloads)
MIRROR_DEST=$SB/.limpet/mirror
AUTO_UPDATE=0
EOF

pass=0; fail=0
ck(){ if eval "$2"; then printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); else printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); fi; }

echo "[1] drive present → folders become symlinks to the drive"
"$LIMPET" __guard
ck "~/Documents is a symlink"        '[ -L "$SB/Documents" ]'
ck "~/Documents → drive/Documents"   '[ "$(readlink "$SB/Documents")" = "$DRV/Documents" ]'
ck "~/Downloads is a symlink"        '[ -L "$SB/Downloads" ]'

echo "[2] writing through the symlink physically lands on the drive"
echo "hello" > "$SB/Documents/a.txt"
ck "a.txt exists on the drive"       '[ -f "$DRV/Documents/a.txt" ]'

echo "[3] UNPLUG → folder becomes a real local dir so saves keep working"
mv "$DRV" "$DRV.away"                 # simulate unmount (data preserved, just absent)
"$LIMPET" __guard
ck "~/Documents is now a real dir"   '[ -d "$SB/Documents" ] && [ ! -L "$SB/Documents" ]'
echo "made-offline" > "$SB/Documents/b.txt"
ck "b.txt saved while drive away"    '[ -f "$SB/Documents/b.txt" ]'
echo "local-version" > "$SB/Documents/a.txt"   # conflicts with the a.txt already on the drive

echo "[4] REPLUG → failback merges offline work, keeps both on conflict, never overwrites"
mv "$DRV.away" "$DRV"
"$LIMPET" __guard
ck "~/Documents is a symlink again"  '[ -L "$SB/Documents" ]'
ck "offline b.txt merged to drive"   '[ -f "$DRV/Documents/b.txt" ]'
ck "original a.txt NOT overwritten"  'grep -q hello "$DRV/Documents/a.txt"'
ck "conflicting copy kept-both"      'ls "$DRV/Documents"/a.txt.local-* >/dev/null 2>&1'

echo "[5] no data was lost across the whole cycle"
ck "both versions of a.txt survive"  '[ "$(cat "$DRV/Documents/a.txt")" = hello ] && grep -rq local-version "$DRV/Documents"/a.txt.local-*'

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
