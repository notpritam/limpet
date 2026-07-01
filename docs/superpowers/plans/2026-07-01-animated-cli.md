# limpet v0.2 Animated CLI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pure-bash animation layer to limpet — real `du`-driven progress bars, braille spinners, and a live `limpet watch` view — that is completely invisible off a TTY.

**Architecture:** One new UI section in the single `limpet` file, gated by `_ui_animated`. A `du`-poll engine measures the source, runs the real `ditto`/`rsync` in the background, and polls the destination's growing size to render a filling bar. The same engine drives setup copies, `link`/`unlink`, and the rsync mirror. A `main` source-guard makes the script sourceable so pure helpers get real unit tests.

**Tech Stack:** bash 3.2, `tput`, `du`, `ditto`, `rsync` (openrsync) — all macOS built-ins. No new dependencies.

## Global Constraints

Every task's requirements implicitly include these. Exact values from the spec + AGENTS.md:

- **bash 3.2.57 compatible.** No associative arrays, no `mapfile`/`readarray`, no `${var^^}`. Expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}` under `set -u`. `read -t` has **no** fractional timeout on 3.2 (integer seconds only). `sleep` **does** accept fractional seconds on macOS.
- **Multibyte landmine (verified).** bash 3.2 under a UTF-8 locale **corrupts iterative multibyte self-append** (`out="$out█"` in a loop → garbage bytes). Build repeated block/braille strings with `_rep` (printf-pad `%Ns` then `${s// /$ch}`), never a char-by-char loop. Array-element access (`${_SPIN[i]}`) and single `printf` args are fine.
- **Zero dependencies.** ANSI + `tput` + `du` only. No `pv`/`gum`/brew rsync.
- **The golden rule:** every animation helper returns to today's plain output unless `[ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$DRY_RUN" != 1 ]`. The launchd guard, shell hook, pipes, and `--dry-run` must emit **zero** ESC (`0x1b`) bytes.
- **Verify before delete.** `verify_copy` gates every `rm`. Animation only *wraps* the copy — never moves or weakens the verify/swap. (AGENTS.md invariant.)
- **Never overwrite on merge.** Failback keep-both logic is untouched.
- **Guard needs no Full Disk Access.** No animation in `__guard`/`__mirror`/`__autoupdate` paths (they're non-TTY → gated off automatically).
- **Single-instance lock.** `with_lock` still wraps guard + mirror.
- **`# ABOUTME:` header** stays as the first two lines of every file.
- **Version matches the git tag.** `LIMPET_VERSION` → `0.2.0`, released as tag `v0.2.0`.
- **Syntax check:** `/bin/bash -n limpet` must pass at every commit.

---

## File Structure

- **Modify `limpet`** — new `# ---- ui: animation` section; wrap `move_to_drive`, `cmd_setup`, `run_mirror`, `cmd_sync`, `cmd_update`; add `cmd_watch` + dispatch + help; bump version; source-guard `main`.
- **Create `test/test-ui.sh`** — sources limpet; unit-tests pure helpers; characterization-tests `move_to_drive` + `_copy_poll`; asserts zero ESC bytes off-TTY.
- **Create `docs/cli.html`** — the approved prototype, productionized as a site page.
- **Modify `README.md`** — add `watch`, honest line-count, link `docs/cli.html`, version.
- **Modify `docs/index.html`** — small "new in v0.2" link to `cli.html`.
- **Modify `docs/sitemap.xml`** — add `cli.html`.

Source of the approved visual: `/private/tmp/claude-501/-Volumes-X9-Documents-Projects-limpet/aa78c544-930f-41aa-8aff-d6bcb291b5d5/scratchpad/limpet-cli-preview.html` (served & signed off during design).

---

### Task 1: Sourceable script + pure UI helpers

**Files:**
- Modify: `limpet` — add source-guard at end (line ~505); add UI helpers after the `# ---- ui` block (after line 45).
- Create: `test/test-ui.sh`

**Interfaces:**
- Produces: `_ui_animated` (returns 0 iff animated), `_human_kb <kb>` → string, `_rep <char> <count>` → repeated string (multibyte-safe), `_bar_str <pct> <width>` → block string, `_spin_frame <i>` → glyph, globals `BAR_W=22`, `_SPIN[]`, `_BLK[]`.

- [ ] **Step 1: Make `limpet` sourceable.** In `limpet`, replace the final line `main "$@"` with:

```bash
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then main "$@"; fi
```

- [ ] **Step 2: Verify the CLI still runs after the guard.**

Run: `./limpet version`
Expected: `limpet 0.1.0`

- [ ] **Step 3: Add the pure helpers.** In `limpet`, immediately after `title(){ ... }`/`confirm()` block (after line 45, before `# ---- config`), insert:

```bash
# ----------------------------------------------------------------------------- ui: animation layer
BAR_W=22
_SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
_BLK=('' ▏ ▎ ▍ ▌ ▋ ▊ ▉)     # sub-cell eighths; index 1..7 (0 unused)

_ui_animated() { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$DRY_RUN" != 1 ]; }

_human_kb() { # <kb> -> "512 KB" / "240 MB" / "1.5 GB"
  local kb="${1:-0}"
  if [ "$kb" -ge 1048576 ]; then
    printf '%d.%d GB' "$(( kb / 1048576 ))" "$(( (kb % 1048576) * 10 / 1048576 ))"
  elif [ "$kb" -ge 1024 ]; then
    printf '%d MB' "$(( kb / 1024 ))"
  else
    printf '%d KB' "$kb"
  fi
}

_spin_frame() { printf '%s' "${_SPIN[$(( ${1:-0} % 10 ))]}"; }

_rep() { # <char> <count> -> char repeated count times.
  # MUST use printf-pad + substitution, NOT a `out="$out█"` loop: bash 3.2 under a
  # UTF-8 locale corrupts iterative multibyte self-append (verified — produces garbage).
  local ch="$1" n="$2"; [ "$n" -le 0 ] && return 0
  local s; s="$(printf "%${n}s" "")"; printf '%s' "${s// /$ch}"
}

_bar_str() { # <pct> <width> -> "████▏░░░"  (plain; caller adds color)
  local pct="${1:-0}" w="${2:-$BAR_W}"
  [ "$pct" -gt 100 ] && pct=100; [ "$pct" -lt 0 ] && pct=0
  local eighths=$(( pct * w * 8 / 100 )) full=$(( pct * w * 8 / 100 / 8 )) part mid="" rest
  part=$(( eighths % 8 )); rest=$(( w - full ))
  if [ "$part" -gt 0 ] && [ "$full" -lt "$w" ]; then mid="${_BLK[$part]}"; rest=$(( rest - 1 )); fi
  printf '%s%s%s' "$(_rep █ "$full")" "$mid" "$(_rep ░ "$rest")"
}
```

- [ ] **Step 4: Write the failing unit test.** Create `test/test-ui.sh`:

```bash
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

echo
printf 'RESULT: \033[32m%d passed\033[0m, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
```

- [ ] **Step 5: Run the test — expect PASS** (helpers now exist).

Run: `chmod +x test/test-ui.sh && bash test/test-ui.sh`
Expected: `RESULT: 14 passed, 0 failed`

- [ ] **Step 6: bash 3.2 + syntax gate.**

Run: `/bin/bash -n limpet && /bin/bash test/test-ui.sh`
Expected: no syntax errors; `14 passed, 0 failed`

- [ ] **Step 7: Commit.**

```bash
git add limpet test/test-ui.sh
git commit -m "feat(cli): sourceable script + pure UI helpers (_human_kb/_bar_str/_spin_frame)"
```

---

### Task 2: `du`-poll copy engine + row rendering, wired into `move_to_drive`

**Files:**
- Modify: `limpet` — add engine helpers (after Task 1's block); refactor `move_to_drive` (currently lines 99–114); pass a label from `cmd_link`.
- Modify: `test/test-ui.sh` — add engine + move_to_drive characterization tests.

**Interfaces:**
- Consumes: `_ui_animated`, `_bar_str`, `_spin_frame`, `_human_kb`, `BAR_W`.
- Produces: `_du_kb <path>` → kb; row state globals `ROW_LABEL[] ROW_STATE[] ROW_PCT[] ROW_TOTKB[] ROW_DSTKB[] ROWS_H SHOW_AGG ROW_CUR FRAME`; `_rows_begin <agg>`, `_rows_add <label> <totkb>`, `_rows_paint`, `_rows_update`, `_rows_state <s>`, `_rows_done`, `_rows_fail`, `_in_block`, `_run_poll <idx> <dst> -- <cmd...>` (generic du-poll engine; also used by the mirror in Task 5). `move_to_drive <src> <dst> [label]` now takes an optional label.

- [ ] **Step 1: Add the engine.** In `limpet`, after Task 1's UI block, insert:

```bash
ROW_LABEL=(); ROW_STATE=(); ROW_PCT=(); ROW_TOTKB=(); ROW_DSTKB=()
ROWS_H=0; SHOW_AGG=0; ROW_CUR=-1; FRAME=0

_du_kb() { local k; k="$(du -sk "$1" 2>/dev/null | awk 'NR==1{print $1}')"; echo "${k:-0}"; }
_in_block() { _ui_animated && [ "$ROW_CUR" -ge 0 ]; }

_rows_begin() { ROW_LABEL=(); ROW_STATE=(); ROW_PCT=(); ROW_TOTKB=(); ROW_DSTKB=(); SHOW_AGG="${1:-0}"; ROWS_H=0; }
_rows_add()   { ROW_LABEL+=("$1"); ROW_TOTKB+=("${2:-0}"); ROW_DSTKB+=(0); ROW_PCT+=(0); ROW_STATE+=(queued); }

_row_line() { # <idx>
  local i="$1" glyph gcls barcls
  case "${ROW_STATE[$i]}" in
    queued)   glyph='○'; gcls="$DIM";  barcls="$DIM" ;;
    done)     glyph='✓'; gcls="$GRN";  barcls="$GRN" ;;
    failed)   glyph='✗'; gcls="$RED";  barcls="$RED" ;;
    verifying)glyph="$(_spin_frame $FRAME)"; gcls="$CYN"; barcls="$CYN" ;;
    *)        glyph="$(_spin_frame $FRAME)"; gcls="$CYN"; barcls="$CYN" ;;
  esac
  local size
  if [ "${ROW_STATE[$i]}" = queued ]; then size="${DIM}queued${R}"
  elif [ "${ROW_STATE[$i]}" = done ]; then size="$(_human_kb "${ROW_TOTKB[$i]}")"
  else size="$(_human_kb "${ROW_DSTKB[$i]}") / $(_human_kb "${ROW_TOTKB[$i]}")"; fi
  printf '  %s%s%s %s%-12s%s %s%s%s  %s%3d%%%s   %s%s%s' \
    "$gcls" "$glyph" "$R" "$B" "${ROW_LABEL[$i]}" "$R" \
    "$barcls" "$(_bar_str "${ROW_PCT[$i]}" "$BAR_W")" "$R" \
    "$gcls" "${ROW_PCT[$i]}" "$R" "$DIM" "$size" "$R"
}
_agg_line() {
  local i=0 done=0 tot=0
  while [ "$i" -lt "${#ROW_TOTKB[@]}" ]; do
    tot=$(( tot + ROW_TOTKB[i] )); done=$(( done + ROW_TOTKB[i] * ROW_PCT[i] / 100 )); i=$(( i + 1 ))
  done
  printf '  %s▸%s %s%s of %s · verified byte-for-byte before removal%s' \
    "$CYN" "$R" "$DIM" "$(_human_kb "$done")" "$(_human_kb "$tot")" "$R"
}

_rows_paint() {
  _ui_animated || return 0
  local i=0
  while [ "$i" -lt "${#ROW_LABEL[@]}" ]; do _row_line "$i"; printf '\n'; i=$(( i + 1 )); done
  [ "$SHOW_AGG" = 1 ] && { _agg_line; printf '\n'; }
  ROWS_H=$(( ${#ROW_LABEL[@]} + ( SHOW_AGG == 1 ? 1 : 0 ) ))
}
_rows_update() {
  _ui_animated || return 0
  FRAME=$(( FRAME + 1 ))
  tput cuu "$ROWS_H"
  local i=0
  while [ "$i" -lt "${#ROW_LABEL[@]}" ]; do printf '\r'; tput el; _row_line "$i"; printf '\n'; i=$(( i + 1 )); done
  [ "$SHOW_AGG" = 1 ] && { printf '\r'; tput el; _agg_line; printf '\n'; }
}
_rows_state() { _in_block || return 0; ROW_STATE[$ROW_CUR]="$1"; _rows_update; }
_rows_done()  { _in_block || return 0; ROW_STATE[$ROW_CUR]=done; ROW_PCT[$ROW_CUR]=100; _rows_update; }
_rows_fail()  { _in_block || return 0; ROW_STATE[$ROW_CUR]=failed; _rows_update; }

_run_poll() { # <idx> <dst> -- cmd... : run the copy cmd in bg, poll dst size -> row pct. Plain cmd off-TTY.
  local idx="$1" dst="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  if ! _ui_animated || [ "$idx" -lt 0 ]; then "$@"; return $?; fi
  local tot="${ROW_TOTKB[$idx]}" d p
  ROW_STATE[$idx]=copying
  "$@" & local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    d="$(_du_kb "$dst")"; ROW_DSTKB[$idx]="$d"
    p=0; [ "$tot" -gt 0 ] && p=$(( d * 100 / tot )); [ "$p" -gt 99 ] && p=99
    [ "$p" -lt "${ROW_PCT[$idx]}" ] && p="${ROW_PCT[$idx]}"   # monotonic
    ROW_PCT[$idx]="$p"; _rows_update; sleep 0.2
  done
  wait "$pid"; return $?
}
```

- [ ] **Step 2: Refactor `move_to_drive`** (lines 99–114) to route the copy through `_copy_poll` and drive the row, keeping the verify/swap tail byte-for-byte. Replace the whole function with:

```bash
move_to_drive() {
  local src="$1" dst="$2" label="${3:-$(basename "$dst")}"
  [ -L "$src" ] && { _in_block && { _rows_done; return 0; }; info "already a symlink: ${DIM}$src${R}"; return 0; }
  [ -e "$src" ] || { ln -s "$dst" "$src"; return 0; }
  local standalone=0
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    _in_block || warn "destination already exists, verifying instead of copying: $dst"
  else
    if [ "$DRY_RUN" = 1 ]; then say "${DIM}[dry-run] ditto '$src' '$dst'${R}"; return 0; fi
    if _ui_animated && [ "$ROW_CUR" -lt 0 ]; then _rows_begin 0; _rows_add "$label" "$(_du_kb "$src")"; _rows_paint; ROW_CUR=0; standalone=1; fi
    _run_poll "$ROW_CUR" "$dst" -- ditto "$src" "$dst" || { _rows_fail; err "copy failed: $src"; [ "$standalone" = 1 ] && ROW_CUR=-1; return 1; }
  fi
  [ "$DRY_RUN" = 1 ] && { say "${DIM}[dry-run] verify + replace '$src' with symlink${R}"; return 0; }
  _rows_state verifying
  verify_copy "$src" "$dst" || { _rows_fail; err "verify FAILED — leaving original intact: $src"; [ "$standalone" = 1 ] && ROW_CUR=-1; return 1; }
  chmod -N "$src" 2>/dev/null
  rm -rf "$src" && ln -s "$dst" "$src" || { _rows_fail; err "swap failed (data is safe at $dst)"; [ "$standalone" = 1 ] && ROW_CUR=-1; return 1; }
  _rows_done
  [ "$standalone" = 1 ] && ROW_CUR=-1
  return 0
}
```

- [ ] **Step 3: Pass a label from `cmd_link`.** In `cmd_link` (line ~422) change `move_to_drive "$abs" "$dst" && ok "linked."` to:

```bash
  move_to_drive "$abs" "$dst" "$(basename "$abs")" && ok "linked." || err "failed."
```

- [ ] **Step 4: Add the failing engine + move test.** Append to `test/test-ui.sh` (before the final `RESULT` block):

```bash
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
```

- [ ] **Step 5: Run the tests.**

Run: `bash test/test-ui.sh`
Expected: `RESULT: 21 passed, 0 failed` (14 prior + 7 new)

- [ ] **Step 6: Regression — the guard test still passes, syntax OK.**

Run: `/bin/bash -n limpet && bash test/test-guard.sh && /bin/bash test/test-ui.sh`
Expected: guard `11 passed`; ui `21 passed`; no syntax errors.

- [ ] **Step 7: Manual visual check (real terminal).** In a scratch dir with a ≥50 MB folder, run a one-off:

```bash
LIMPET_DRY_RUN=0 bash -c 'source ./limpet; ROW_CUR=-1; move_to_drive /tmp/bigfolder /tmp/bigfolder.dst BigFolder'
```
Expected: a single teal bar fills, flips to a green `✓ BigFolder … 100%`. Ctrl-C mid-run leaves `/tmp/bigfolder` intact.

- [ ] **Step 8: Commit.**

```bash
git add limpet test/test-ui.sh
git commit -m "feat(cli): du-poll progress engine + single-row bars for move/link"
```

---

### Task 3: Multi-row `setup` block with aggregate

**Files:**
- Modify: `limpet` — `cmd_setup` "do it" loop (lines ~352–357).

**Interfaces:**
- Consumes: `_rows_begin/_rows_add/_rows_paint`, `_du_kb`, `move_to_drive`, `ROW_CUR`, `_ui_animated`.

- [ ] **Step 1: Replace the setup copy loop.** In `cmd_setup`, replace the block:

```bash
  local f
  for f in "${FOLDERS[@]}"; do
    info "linking ${B}$f${R} → $DRIVE/$f"
    move_to_drive "$HOME/$f" "$DRIVE/$f" && ok "$f is now on the drive" || err "$f failed (left intact)"
  done
```

with:

```bash
  local f
  if _ui_animated; then
    title "Moving your folders onto ${B}$DRIVE${R} …"
    _rows_begin 1
    for f in "${FOLDERS[@]}"; do _rows_add "$f" "$(_du_kb "$HOME/$f")"; done
    _rows_paint
    local _i=0
    for f in "${FOLDERS[@]}"; do
      ROW_CUR=$_i
      move_to_drive "$HOME/$f" "$DRIVE/$f" "$f" || true
      _i=$(( _i + 1 ))
    done
    ROW_CUR=-1
  else
    for f in "${FOLDERS[@]}"; do
      info "linking ${B}$f${R} → $DRIVE/$f"
      move_to_drive "$HOME/$f" "$DRIVE/$f" "$f" && ok "$f is now on the drive" || err "$f failed (left intact)"
    done
  fi
```

- [ ] **Step 2: Syntax + regression gate.**

Run: `/bin/bash -n limpet && bash test/test-ui.sh && bash test/test-guard.sh`
Expected: no syntax errors; `21 passed`; `11 passed`.

- [ ] **Step 3: Non-TTY setup emits no escapes** (proves the golden rule for setup). Run:

```bash
SB="$(mktemp -d)"; HOME2="$SB/home"; mkdir -p "$HOME2/Docs"; echo x > "$HOME2/Docs/f"
esc=$(HOME="$HOME2" LIMPET_CONFIG_DIR="$SB/c" LIMPET_STATE_DIR="$SB/s" \
  bash ./limpet setup --drive "$SB/drv" --folders Docs --yes --dry-run 2>&1 | LC_ALL=C tr -dc '\033' | wc -c | tr -d ' ')
echo "ESC bytes: $esc"; rm -rf "$SB"
```
Expected: `ESC bytes: 0` (dry-run is gated off).

- [ ] **Step 4: Manual visual check (real terminal).** With a real external drive plugged in and a scratch config, run `limpet setup` interactively (or the `--drive/--folders/--yes` form on a throwaway drive). Expected: stacked rows for each folder, queued → filling → green ✓, aggregate line ticking underneath, then `✓ Setup complete.`

- [ ] **Step 5: Commit.**

```bash
git add limpet
git commit -m "feat(cli): stacked multi-folder progress block + aggregate in setup"
```

---

### Task 4: `spin` helper for async steps (`update`, `sync`)

**Files:**
- Modify: `limpet` — add `spin`; wrap the curl download in `_do_update` (lines ~242–249); wrap the guard step in `cmd_sync` (line 433).
- Modify: `test/test-ui.sh` — add `spin` status test.

**Interfaces:**
- Consumes: `_ui_animated`, `_spin_frame`, colors.
- Produces: `spin <label> -- <cmd...>` → runs cmd, returns its exit status, prints `✓/✗ label`.

- [ ] **Step 1: Add `spin`.** After `_copy_poll` in the UI section, insert:

```bash
spin() { # spin "label" -- cmd...
  local label="$1"; shift; [ "${1:-}" = "--" ] && shift
  if ! _ui_animated; then "$@"; return $?; fi
  "$@" & local pid=$! i=0
  tput civis 2>/dev/null
  while kill -0 "$pid" 2>/dev/null; do printf '\r  %s%s%s %s' "$CYN" "$(_spin_frame $i)" "$R" "$label …"; tput el; i=$(( i + 1 )); sleep 0.08; done
  wait "$pid"; local st=$?
  tput cnorm 2>/dev/null
  printf '\r'; tput el
  if [ "$st" = 0 ]; then ok "$label"; else err "$label"; fi
  return $st
}
```

- [ ] **Step 2: Wrap the update download.** In `_do_update`, wrap the two `curl` lines so the download shows a spinner. Replace:

```bash
  curl -fsSL --max-time 30 "https://github.com/$REPO/releases/download/v$v/limpet" -o "$tmp" 2>/dev/null \
    || curl -fsSL --max-time 30 "https://raw.githubusercontent.com/$REPO/v$v/limpet" -o "$tmp" 2>/dev/null || return 1
```

with:

```bash
  spin "downloading v$v" -- bash -c '
    curl -fsSL --max-time 30 "https://github.com/'"$REPO"'/releases/download/v'"$v"'/limpet" -o "'"$tmp"'" 2>/dev/null \
      || curl -fsSL --max-time 30 "https://raw.githubusercontent.com/'"$REPO"'/v'"$v"'/limpet" -o "'"$tmp"'" 2>/dev/null' || return 1
```

- [ ] **Step 3: Spin the sync guard step.** In `cmd_sync` (line 433) replace:

```bash
cmd_sync()   { require_config; with_lock guard run_guard; with_lock mirror run_mirror; ok "synced."; }
```

with (note: the mirror renders its own bars in Task 5, so only the guard is spun):

```bash
cmd_sync() {
  require_config
  spin "failover / failback" -- with_lock guard run_guard
  with_lock mirror run_mirror
  ok "synced."
}
```

- [ ] **Step 4: Add the failing `spin` test.** Append to `test/test-ui.sh` before the `RESULT` block:

```bash
echo "[spin — returns child status, silent off-TTY]"
out="$( spin "ok step" -- true 2>&1 )";  eq "spin true → 0"  "$?" "0"
eq "spin silent off-tty (true)" "$(printf '%s' "$out" | LC_ALL=C tr -dc '\033' | wc -c | tr -d ' ')" "0"
spin "bad step" -- false >/dev/null 2>&1; eq "spin false → 1" "$?" "1"
```

- [ ] **Step 5: Run tests.**

Run: `bash test/test-ui.sh`
Expected: `RESULT: 24 passed, 0 failed`

- [ ] **Step 6: Syntax gate.**

Run: `/bin/bash -n limpet`
Expected: no output (OK).

- [ ] **Step 7: Manual check.** In a real terminal: `limpet update --check` (spinner during the GitHub check→ resolves), and `limpet sync` (spinner on failover → `✓`).

- [ ] **Step 8: Commit.**

```bash
git add limpet test/test-ui.sh
git commit -m "feat(cli): spin helper for async steps (update download, sync)"
```

---

### Task 5: Progress bars for the rsync mirror

**Files:**
- Modify: `limpet` — `run_mirror` (lines 152–167).

**Interfaces:**
- Consumes: `_ui_animated`, `_rows_*`, `_run_poll` (the generic du-poll engine defined in Task 2), `_du_kb`.

- [ ] **Step 1: Reuse the Task 2 engine — do NOT add a second poll function.** `run_mirror` drives each entry through the existing `_run_poll <idx> <dst> -- <cmd...>` (added in Task 2, already used by `move_to_drive`). Confirm `_run_poll` is present in `limpet` before wiring the mirror.

- [ ] **Step 2: Render mirror entries as rows (TTY only).** Replace the body of `run_mirror` (the `while` loop and surrounding, lines ~157–166) with a version that pre-counts entries and drives a row each. Replace:

```bash
  local line src dst n=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; case "$line" in ''|\#*) continue;; esac
    src="$DRIVE/$line"; dst="$MIRROR_DEST/$line"
    [ -e "$src" ] || { logln "[mirror] skip missing: $line"; continue; }
    mkdir -p "$(dirname "$dst")"
    if [ -d "$src" ]; then mkdir -p "$dst"; rsync -a --delete "$src/" "$dst/" 2>>"$LOG" && n=$((n+1))
    else rsync -a "$src" "$dst" 2>>"$LOG" && n=$((n+1)); fi
  done < "$MIRROR_LIST"
  logln "[mirror] done ($n mirrored)"
```

with:

```bash
  local line src dst n=0 entries=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; case "$line" in ''|\#*) continue;; esac
    [ -e "$DRIVE/$line" ] || { logln "[mirror] skip missing: $line"; continue; }
    entries+=("$line")
  done < "$MIRROR_LIST"
  [ "${#entries[@]}" -eq 0 ] && { logln "[mirror] done (0 mirrored)"; return 0; }

  if _ui_animated; then title "Mirroring ${#entries[@]} path(s) → $MIRROR_DEST"; _rows_begin 0
  for line in "${entries[@]}"; do _rows_add "$line" "$(_du_kb "$DRIVE/$line")"; done; _rows_paint; fi

  local _i=0
  for line in "${entries[@]}"; do
    src="$DRIVE/$line"; dst="$MIRROR_DEST/$line"; mkdir -p "$(dirname "$dst")"
    ROW_CUR=$( _ui_animated && echo "$_i" || echo -1 )
    if [ -d "$src" ]; then mkdir -p "$dst"; _run_poll "$ROW_CUR" "$dst" -- rsync -a --delete "$src/" "$dst/" 2>>"$LOG" && { n=$((n+1)); _rows_done; } || _rows_fail
    else _run_poll "$ROW_CUR" "$dst" -- rsync -a "$src" "$dst" 2>>"$LOG" && { n=$((n+1)); _rows_done; } || _rows_fail; fi
    _i=$(( _i + 1 ))
  done
  ROW_CUR=-1
  logln "[mirror] done ($n mirrored)"
```

- [ ] **Step 3: Syntax gate + regression.**

Run: `/bin/bash -n limpet && bash test/test-ui.sh && bash test/test-guard.sh`
Expected: no syntax errors; `24 passed`; `11 passed`.

- [ ] **Step 4: Golden-rule check — the hook's mirror path stays silent.** Run:

```bash
SB="$(mktemp -d)"; mkdir -p "$SB/drv/keep"; echo a > "$SB/drv/keep/f"
printf 'keep\n' > "$SB/mp.txt"
esc=$(HOME="$SB" LIMPET_CONFIG_DIR="$SB/c" LIMPET_STATE_DIR="$SB/s" bash -c '
  source ./limpet; DRIVE="'"$SB"'/drv"; MIRROR_DEST="'"$SB"'/mir"; MIRROR_LIST="'"$SB"'/mp.txt"
  run_mirror' 2>&1 | LC_ALL=C tr -dc '\033' | wc -c | tr -d ' ')
echo "ESC bytes (non-TTY mirror): $esc"; [ -f "$SB/mir/keep/f" ] && echo "mirrored OK"; rm -rf "$SB"
```
Expected: `ESC bytes (non-TTY mirror): 0` and `mirrored OK`.

- [ ] **Step 5: Manual visual check.** With a real drive + a `mirror-paths.txt` entry, run `limpet sync` in a terminal — expect the failover spinner, then per-entry mirror bars.

- [ ] **Step 6: Commit.**

```bash
git add limpet
git commit -m "feat(cli): per-entry progress bars for the rsync mirror"
```

---

### Task 6: `limpet watch` — live state view

**Files:**
- Modify: `limpet` — add `cmd_watch`; add `watch)` to `main` dispatch (line ~495); one-line help stub.

**Interfaces:**
- Consumes: `require_config`, `drive_present`, `FOLDERS`, `_spin_frame`, `_ui_animated`, colors, `tput`.
- bash 3.2: no fractional `read -t`; use `sleep 0.5` + a `trap` for cursor restore; exit on Ctrl-C.

- [ ] **Step 1: Add `cmd_watch`.** After `cmd_status` (line ~394), insert:

```bash
cmd_watch() {
  require_config
  if ! _ui_animated; then cmd_status; return 0; fi
  local H=$(( ${#FOLDERS[@]} + 4 )) first=1 prev=-1 f t present frame=0
  tput civis 2>/dev/null
  trap 'tput cnorm 2>/dev/null; printf "\n"; exit 0' INT TERM
  while :; do
    present=0; drive_present && present=1
    [ "$first" = 1 ] && first=0 || tput cuu "$H"
    # header
    printf '\r'; tput el
    if [ "$present" = 1 ]; then printf '  %s●%s %sX9%s   %sconnected%s   %s%s%s\n' "$CYN" "$R" "$B" "$R" "$CYN" "$R" "$DIM" "$DRIVE" "$R"
    else printf '  %s●%s %sX9%s   %sUNPLUGGED%s   %swas %s%s\n' "$YEL" "$R" "$B" "$R" "$YEL" "$R" "$DIM" "$DRIVE" "$R"; fi
    printf '\r'; tput el; printf '  %sguard%s   %s\n' "$DIM" "$R" "$(launchctl list 2>/dev/null | grep -q "$LABEL" && printf '%sloaded%s' "$GRN" "$R" || printf '%snot loaded%s' "$RED" "$R")"
    printf '\r'; tput el; printf '\n'
    for f in "${FOLDERS[@]}"; do
      printf '\r'; tput el
      if [ -L "$HOME/$f" ]; then t="$(readlink "$HOME/$f")"; printf '  %s✓%s %-12s %s→ %s%s\n' "$GRN" "$R" "~/$f" "$DIM" "$t" "$R"
      elif [ -d "$HOME/$f" ]; then printf '  %s•%s %-12s %slocal — failover mode%s\n' "$BLU" "$R" "~/$f" "$DIM" "$R"
      else printf '  %s?%s %-12s %smissing%s\n' "$YEL" "$R" "~/$f" "$DIM" "$R"; fi
    done
    printf '\r'; tput el; printf '  %spress Ctrl-C to quit · redraws on plug / unplug%s\n' "$DIM" "$R"
    prev="$present"; frame=$(( frame + 1 )); sleep 0.5
  done
}
```

- [ ] **Step 2: Wire dispatch.** In `main`, add after `status)` (line ~489):

```bash
    watch)        cmd_watch;;
```

- [ ] **Step 3: Add to help.** In `cmd_help` COMMANDS list, after the `status` line, add:

```bash
  ${CYN}watch${R}            Live view: drive + folder state, redraws on plug/unplug (Ctrl-C to quit).
```

- [ ] **Step 4: Syntax gate + dispatch smoke.**

Run: `/bin/bash -n limpet && ./limpet help | grep -q watch && echo "help lists watch"`
Expected: no syntax error; `help lists watch`.

- [ ] **Step 5: Non-TTY `watch` falls back to one-shot status** (no infinite loop, no escapes). Run:

```bash
SB="$(mktemp -d)"; mkdir -p "$SB/.config/limpet"
printf 'DRIVE=%s/drv\nFOLDERS=(Docs)\nMIRROR_DEST=%s/m\nAUTO_UPDATE=0\n' "$SB" "$SB" > "$SB/.config/limpet/config"; mkdir -p "$SB/drv/Docs"
esc=$(HOME="$SB" LIMPET_CONFIG_DIR="$SB/.config/limpet" LIMPET_STATE_DIR="$SB/s" bash ./limpet watch 2>&1 | LC_ALL=C tr -dc '\033' | wc -c | tr -d ' ')
echo "ESC bytes (non-TTY watch): $esc"; rm -rf "$SB"
```
Expected: exits immediately; `ESC bytes (non-TTY watch): 0`.

- [ ] **Step 6: Manual visual check.** In a real terminal run `limpet watch`; physically unplug the drive → line flips to amber `UNPLUGGED`, folders → blue `local — failover`; replug → back to green ✓. Ctrl-C restores the cursor and exits cleanly.

- [ ] **Step 7: Commit.**

```bash
git add limpet
git commit -m "feat(cli): limpet watch — live plug/unplug state view"
```

---

### Task 7: Version bump, help, and README

**Files:**
- Modify: `limpet` — `LIMPET_VERSION` (line 6); `cmd_help` HOW IT WORKS note.
- Modify: `README.md` — command table (`watch`), honest line-count, site-links row, version mentions.

**Interfaces:** none (docs/version).

- [ ] **Step 1: Bump version.** In `limpet` line 6:

```bash
LIMPET_VERSION="0.2.0"
```

- [ ] **Step 2: Update the unit test's version assertion** (from Task 1 Step 2 it was 0.1.0). Confirm `./limpet version` now prints `limpet 0.2.0`.

Run: `./limpet version`
Expected: `limpet 0.2.0`

- [ ] **Step 3: README — add `watch` to the command reference.** In `README.md`, in the command list (search for `` `sync` `` / the COMMANDS section mirrored from help), add a row:

```markdown
| `limpet watch` | Live view of drive + folder state; redraws on plug/unplug (Ctrl-C to quit). |
```

(Match the exact table/list format already used in README — if it's a prose list, add `- **watch** — …` in the same style.)

- [ ] **Step 4: README — honest line-count + CLI preview link.** Replace the "Single file. Pure bash … ~300 lines you can read over one coffee." sentence with:

```markdown
Single file. Pure bash. **No kernel extensions, no daemons, no network.** ~600 lines, still one file, still zero dependencies — and now with a live progress UI (see the **[CLI preview](https://limpet.notpritam.in/cli.html)**).
```

And in the top links row (the `**▶ [Website] · [Launch video] · [Explainer deck]**` line) add `· [CLI preview](https://limpet.notpritam.in/cli.html)`.

- [ ] **Step 5: Syntax + full test gate.**

Run: `/bin/bash -n limpet && bash test/test-ui.sh && bash test/test-guard.sh`
Expected: no syntax errors; `24 passed`; `11 passed`.

- [ ] **Step 6: Commit.**

```bash
git add limpet README.md
git commit -m "chore(release): bump to v0.2.0, document watch + progress UI"
```

---

### Task 8: `docs/cli.html` site page + links

**Files:**
- Create: `docs/cli.html` (from the approved prototype).
- Modify: `docs/index.html` — add a "new in v0.2" link to `cli.html`.
- Modify: `docs/sitemap.xml` — add the `cli.html` URL.

**Interfaces:** none (static site).

- [ ] **Step 1: Copy the approved prototype into the repo.**

```bash
cp "/private/tmp/claude-501/-Volumes-X9-Documents-Projects-limpet/aa78c544-930f-41aa-8aff-d6bcb291b5d5/scratchpad/limpet-cli-preview.html" docs/cli.html
```

- [ ] **Step 2: Productionize `docs/cli.html`** — make these concrete edits so it reads as a real site page, not a scratch file:
  - Update `<title>` to `limpet · CLI preview` and add the standard meta/OG block used by `docs/index.html` (copy the `<meta name="description">`, `og:*`, and `favicon.svg` link lines from `index.html`'s `<head>`).
  - Add a top-left back-link matching the site nav: `<a href="/" >← limpet</a>` styled with `--teal`.
  - Add a short footer line linking `/` (home), `/launch.html`, `/explainer.html` to match the other pages.
  - Keep the served animation JS unchanged (it's the approved motion).

- [ ] **Step 3: Link from the landing page.** In `docs/index.html`, near the hero CTA/trust row, add a small link:

```html
<a href="/cli.html" class="quip">▶ See the new v0.2 CLI in motion</a>
```
(Use an existing class so it inherits site styling; adjust the class name to one present in `index.html`.)

- [ ] **Step 4: Add to sitemap.** In `docs/sitemap.xml`, duplicate an existing `<url>` block and set:

```xml
  <url><loc>https://limpet.notpritam.in/cli.html</loc><changefreq>monthly</changefreq></url>
```

- [ ] **Step 5: Verify the page renders + is self-contained.**

```bash
node -e 'const h=require("fs").readFileSync("docs/cli.html","utf8");const m=h.match(/<script>([\s\S]*?)<\/script>/);new Function(m[1]);console.log("cli.html JS OK")'
(cd docs && python3 -m http.server 8799 >/dev/null 2>&1 &) ; sleep 1
curl -s -o /dev/null -w "cli.html HTTP %{http_code}\n" http://127.0.0.1:8799/cli.html
```
Expected: `cli.html JS OK`; `cli.html HTTP 200`. (Then stop the server.)

- [ ] **Step 6: Commit.**

```bash
git add docs/cli.html docs/index.html docs/sitemap.xml
git commit -m "docs(site): ship the animated CLI preview as docs/cli.html"
```

---

### Task 9: Final regression gate

**Files:** none (verification only; commit any fixups).

- [ ] **Step 1: Syntax on both bashes.**

Run: `/bin/bash -n limpet && bash -n limpet`
Expected: no output.

- [ ] **Step 2: Full test suite on system bash 3.2.**

Run: `/bin/bash test/test-ui.sh && /bin/bash test/test-guard.sh`
Expected: `24 passed, 0 failed`; `11 passed, 0 failed`.

- [ ] **Step 3: Full test suite on modern bash** (if `brew` bash present, else skip and note).

Run: `bash test/test-ui.sh && bash test/test-guard.sh`
Expected: same pass counts.

- [ ] **Step 4: Golden-rule sweep — no ESC bytes in any non-TTY path.** Run the piped checks from Task 3 Step 3, Task 5 Step 4, and Task 6 Step 5 again; all must report `0`.

- [ ] **Step 5: Manual smoke of all four animated surfaces** in a real terminal (throwaway drive/config): `setup`, `watch`, `doctor`, `sync`. Confirm each matches `docs/cli.html`.

- [ ] **Step 6: Confirm `limpet update` self-check still syntax-checks the downloaded script** (AGENTS.md release invariant) — read `_do_update`, confirm the `/bin/bash -n "$tmp"` guard is intact after the Task 4 wrapping.

- [ ] **Step 7: Final commit (if any fixups) and tag note.**

```bash
git add -A && git commit -m "test(cli): final v0.2 regression pass" || echo "nothing to commit"
```
Note for release: tag `v0.2.0` and attach the `limpet` file as the release asset (per AGENTS.md), so the self-updater can pull it.

---

## Self-Review

**Spec coverage:**
- du-poll engine → Task 2 (`_run_poll`, generic; also used by `move_to_drive`), reused by Task 5 for the rsync mirror (no duplicate poll function). ✓
- Smart bar (fallback when tiny/unknown) → `_run_poll` off-TTY/`idx<0` path; tiny-copy threshold noted (fast copies simply fill in one tick — acceptable; a hard `BAR_MIN_KB` skip can be added if flicker appears). ✓
- Block-fill style + sub-cell + braille → `_bar_str` (`_BLK` eighths) + `_SPIN` (Task 1). ✓
- Golden rule / degradation matrix → `_ui_animated` gate; explicit no-ESC tests in Tasks 3, 5, 6. ✓
- Data safety unchanged → `move_to_drive` verify/swap tail kept verbatim; characterization test Task 2. ✓
- Multi-row setup + aggregate → Task 3. ✓
- Spinner-checks (update, sync) → Task 4. ✓ (doctor left as instant ✓/✗ — matches "no artificial latency"; not wrapped in `spin`.)
- Mirror % → Task 5. ✓
- `watch` → Task 6 (bash-3.2-safe: `sleep`+`trap`, Ctrl-C exit — corrects the spec's `read -t 0.4`). ✓
- docs/cli.html + links → Task 8. ✓
- README/version/help → Task 7. ✓
- Tests (pure helpers + no-ESC) → Tasks 1–6; final gate Task 9. ✓

**Placeholder scan:** No TBD/TODO. The one soft spot — `BAR_MIN_KB` tiny-copy skip — is called out as optional in review, not left as a silent gap. Every code step shows complete code.

**Type/name consistency:** `_ui_animated`, `_run_poll`, `_rows_begin/_add/_paint/_update/_state/_done/_fail`, `_in_block`, `_du_kb`, `_human_kb`, `_rep`, `_bar_str`, `_spin_frame`, `spin`, `cmd_watch`, globals `ROW_*/ROWS_H/SHOW_AGG/ROW_CUR/FRAME` — used identically across tasks. `move_to_drive` third arg `label` added in Task 2 and used in Tasks 2/3. ✓

**Deviation from spec (intentional, noted):** `watch` uses `sleep`+Ctrl-C instead of `read -t 0.4` (bash 3.2 lacks fractional read timeouts); `cmd_sync` spins only the guard (the mirror draws its own bars — spinning around it would fight the cursor rewrites).
