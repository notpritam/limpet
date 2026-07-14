#!/usr/bin/env bash
# ABOUTME: End-to-end test for `limpet organize` on a REAL temp filesystem (no mocks).
# ABOUTME: aged eligibility, by-type + explicit dests, partial/DS_Store/fresh skips, keep-both, unsorted, undo, preview.
set -uo pipefail

LIMPET="$(cd "$(dirname "$0")/.." && pwd)/limpet"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export HOME="$SB"; export LIMPET_STATE_DIR="$SB/state"
mkdir -p "$SB/.config/limpet" "$SB/Downloads" "$SB/Apps" "$SB/X9"

cat > "$SB/.config/limpet/config" <<EOF
DRIVE=$SB/X9
FOLDERS=(Documents Downloads)
MIRROR_DEST=$SB/.limpet/mirror
AUTO_UPDATE=0
GUARD_INTERVAL=0
EOF
cat > "$SB/.config/limpet/organize.conf" <<EOF
ORGANIZE_ENABLED=1
ORGANIZE_MODE=aged
ORGANIZE_IDLE_DAYS=1
ORGANIZE_QUICK_MINUTES=30
ORGANIZE_WATCH=(Downloads)
ORGANIZE_BY_TYPE=1
ORGANIZE_DEST_ROOT=
ORGANIZE_SCHEDULE=manual
EOF
cat > "$SB/.config/limpet/organize-rules.conf" <<EOF
Images     | jpg,png,gif |
Documents  | pdf,txt     |
Installers | dmg,pkg     | $SB/Apps
EOF

OLD=202601010000     # 2026-01-01 — well over 1 day old vs. test run
mkold(){ printf 'content-%s' "$1" > "$SB/Downloads/$1"; touch -t "$OLD" "$SB/Downloads/$1"; }
mkold photo.png; mkold paper.pdf; mkold notes.txt; mkold app.dmg; mkold data.xyz
printf 'fresh' > "$SB/Downloads/fresh.png"                                          # now → too new
printf 'partial' > "$SB/Downloads/big.crdownload"; touch -t "$OLD" "$SB/Downloads/big.crdownload"
printf 'ds' > "$SB/Downloads/.DS_Store"; touch -t "$OLD" "$SB/Downloads/.DS_Store"
mkdir -p "$SB/Downloads/Images"; printf 'ORIGINAL' > "$SB/Downloads/Images/photo.png"   # clash target

pass=0; fail=0
ck(){ if eval "$2"; then printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); else printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); fi; }

echo "[1] preview is read-only (nothing moves)"
"$LIMPET" organize preview >/dev/null 2>&1
ck "paper.pdf still in Downloads (preview moved nothing)" '[ -f "$SB/Downloads/paper.pdf" ]'

echo "[2] run sorts aged files by type; explicit dest honored"
"$LIMPET" organize run --yes >/dev/null 2>&1
ck "paper.pdf → Documents/"        '[ -f "$SB/Downloads/Documents/paper.pdf" ]'
ck "notes.txt → Documents/"        '[ -f "$SB/Downloads/Documents/notes.txt" ]'
ck "app.dmg → explicit \$SB/Apps"  '[ -f "$SB/Apps/app.dmg" ]'
ck "app.dmg left Downloads"        '[ ! -f "$SB/Downloads/app.dmg" ]'

echo "[3] skips: fresh, partial download, .DS_Store, and unmatched"
ck "fresh.png stays (too new)"     '[ -f "$SB/Downloads/fresh.png" ]'
ck "big.crdownload stays"          '[ -f "$SB/Downloads/big.crdownload" ]'
ck ".DS_Store stays in Downloads"  '[ -f "$SB/Downloads/.DS_Store" ]'
ck "unmatched data.xyz stays"      '[ -f "$SB/Downloads/data.xyz" ]'

echo "[4] keep-both on name clash (never overwrite)"
ck "existing Images/photo.png intact" 'grep -q ORIGINAL "$SB/Downloads/Images/photo.png"'
ck "moved photo kept-both (timestamped)" 'ls "$SB/Downloads/Images/"photo.*.png >/dev/null 2>&1'

echo "[5] undo restores everything to origin; nothing lost"
"$LIMPET" organize undo --yes >/dev/null 2>&1
ck "paper.pdf back in Downloads"   '[ -f "$SB/Downloads/paper.pdf" ]'
ck "notes.txt back in Downloads"   '[ -f "$SB/Downloads/notes.txt" ]'
ck "app.dmg back in Downloads"     '[ -f "$SB/Downloads/app.dmg" ]'
ck "Apps/app.dmg removed on undo"  '[ ! -f "$SB/Apps/app.dmg" ]'
ck "original clash file survived"  'grep -q ORIGINAL "$SB/Downloads/Images/photo.png"'

echo "[6] dashboard --json shape"
J="$("$LIMPET" organize --json 2>/dev/null)"
ck "json has enabled+mode"         'printf "%s" "$J" | grep -q "\"enabled\":true" && printf "%s" "$J" | grep -q "\"mode\":\"aged\""'

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
