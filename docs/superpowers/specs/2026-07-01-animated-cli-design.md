<!-- ABOUTME: Design spec for limpet v0.2 — the animated CLI (progress bars, spinners, live watch view). -->
<!-- ABOUTME: Approved visual direction lives in docs/cli.html (proto). This is the buildable spec. -->

# limpet v0.2 — Animated CLI (progress · spinners · live watch)

**Status:** approved design, ready to plan
**Date:** 2026-07-01
**Branch:** `feat/v0.2-animated-cli`
**Visual spec:** the approved interactive prototype (served during design; lands as `docs/cli.html`) —
every frame in this doc maps to it.

---

## 1. Summary

limpet's heavy moments — the first `setup` copy, `link`, and the `mirror` — currently print a
static line and then appear frozen while gigabytes move. v0.2 adds a **pure-bash animation layer**:
real filling progress bars driven by a byte count, braille spinners for async steps, ✓/✗ resolution,
and a new live `watch` view that reacts to the drive being plugged/unplugged. No new dependencies,
still one file, and **completely invisible off a TTY** (the launchd guard, the shell hook, pipes,
`NO_COLOR`, `--dry-run`) so nothing leaks into logs or breaks automation.

## 2. Goals / non-goals

**Goals**
- Real *percentage* progress for the copies that actually take time (`setup`, `link`, `unlink`, `mirror`).
- A live, animated `limpet watch` showing connected ⇄ unplugged ⇄ merging state per folder.
- Spinner + ✓/✗ resolution for genuinely-async steps (`update` download, `sync`, `doctor` where it waits).
- Ship the approved prototype as a real site page (`docs/cli.html`).

**Non-goals (YAGNI)**
- Parallel multi-folder copying (disk-bound; no speedup, more complexity).
- Any external dependency (`pv`, `gum`, `dialog`, brew rsync).
- Color theming/config (we already honor `NO_COLOR`).
- Progress on non-macOS platforms (limpet is macOS-only).

## 3. Locked decisions

| Decision | Choice |
|---|---|
| Bar style | **Block fill** (`████░░`) with braille spinner + sub-cell eighths for smooth fill |
| Percentage mechanism | **Smart bar**: real % via `du` polling; spinner-fallback when total unknown/tiny |
| Packaging | **Inline, single file** (~505 → ~620 lines). README line-count claim updated honestly |
| Site | **Yes** — polish the proto into `docs/cli.html`, linked from README + landing |
| Version | `LIMPET_VERSION` 0.1.0 → **0.2.0** |

## 4. Constraints & invariants (must not break)

1. **bash 3.2.57** — macOS's shell. No associative arrays, no `mapfile`/`readarray`, no `${x^^}`.
   Indexed arrays + integer arithmetic only.
2. **Zero dependencies** — animation is ANSI + `tput` + `du` (all already present) only.
3. **The golden rule — off-TTY is byte-for-byte the old behavior.** Every animation helper early-returns
   to today's plain one-line output unless `[ -t 1 ] && [ -z "${NO_COLOR:-}" ]`. The guard/hook run their
   code paths with stdout to `/dev/null` and non-interactive — they must emit **zero** escape bytes.
4. **Data safety is untouched.** Animation only *wraps* copy/verify/swap. `verify_copy` still gates every
   deletion; an interrupted copy still leaves the source intact.
5. **`--dry-run` unchanged** — prints intended actions, no bars.

## 5. Architecture — the UI layer

One new section in `limpet`, directly below the existing `# ---- ui` block (lines 22–45), containing:

```
_ui_animated   # gate: returns 0 only when [ -t 1 ] && [ -z NO_COLOR ] && DRY_RUN != 1
_human_kb      # KB integer -> "240 MB" / "1.8 GB"   (pure, unit-tested)
_bar_str       # pct,width -> "████▌░░░" string with sub-cell eighth (pure, unit-tested)
_spin_frame    # frame index -> braille glyph
spin           # spin "label" -- cmd...      (async step -> ✓/✗)
_copy_with_bar # label,src,dst -> run ditto/rsync in bg, du-poll dest, render row(s), verify
_rows_render   # repaint the stacked multi-row block in place (tput cuu/el)
cmd_watch      # the live view loop
```

Everything funnels through `_ui_animated`. Callers that already print (`move_to_drive`, `run_mirror`,
`cmd_doctor`, `cmd_update`, `cmd_sync`) call the wrappers; the wrappers themselves decide animate-vs-plain.

## 6. The progress engine (`du`-poll) — the core

`ditto` and openrsync emit no byte progress, and openrsync lacks `--info=progress2`. The only pure-bash
route to a real percentage is to **measure the source, then watch the destination grow**. One engine
serves both `ditto` copies and `rsync` mirror entries.

```
_copy_with_bar <label> <src> <dst> -- <cmd...>      # <cmd...> is the real copy, e.g. ditto "$src" "$dst"
  if ! _ui_animated:                                # off-TTY / dry-run / NO_COLOR
      run <cmd...>; return $?                        # ← today's behavior, plain

  total_kb = du -sk "$src"                           # pre-measure
  if total_kb < BAR_MIN_KB (≈ 8192):                 # too small to bother — would just flash
      run <cmd...>; return $?

  <cmd...> &                                          # copy in background
  pid=$!
  trap cleanup INT TERM                               # kill $pid, tput cnorm, newline
  while kill -0 $pid 2>/dev/null:
      dst_kb = du -sk "$dst" 2>/dev/null || 0
      pct = min(99, dst_kb*100/total_kb)              # cap 99 until verified
      render row(label, pct, "copying", dst_kb/total_kb)
      sleep 0.2
  wait $pid; st=$?

  if st == 0:
      render row(label, 99, "verifying")              # verify_copy can take seconds on big trees
      # (caller runs verify_copy; on pass ->) render row(label,100,"done" ✓)
  else:
      render row(label, pct, "failed" ✗)
  return st
```

Key points:
- **Cap at 99%** during copy; 100%/✓ only after `wait` succeeds *and* the caller's `verify_copy` passes.
  This is why the aggregate line reads "verified byte-for-byte before removal."
- **Poll cadence is self-throttling** — on huge trees `du` itself takes longer than 0.2s; updates just
  get chunkier. Acceptable.
- **rsync `--delete` can shrink then grow** the dest → clamp pct **monotonically** (`pct = max(prev,new)`).

**Responsibility boundary (unambiguous):** `_copy_with_bar` drives the row through `copying → verifying`
and returns the copy's exit status. The **caller** (`move_to_drive`) then runs the existing `verify_copy`
exactly where it does today and flips the row to `done` (✓) or `failed` (✗). Verification logic is not
moved into the engine — the engine only *shows* a "verifying…" state while the caller verifies.

## 7. Multi-row setup display

`setup` copies N folders. Copies stay **sequential** (parallel gives no speedup to one disk and tangles
the display), but the display is a **persistent N-row block**:

1. Print all N rows once, all `queued` (○, empty bar), plus a queued aggregate footer line.
2. For folder *i*: mark it `copying`, run `_copy_with_bar` for it. On each poll tick, call `_rows_render`
   which does `tput cuu $BLOCK_H` → repaint every row with `tput el` → cursor ends back at the bottom.
   Full-block repaint each tick (like the proto) — simplest, flicker-free at 0.2s.
3. Aggregate footer = Σ(done_kb) / Σ(total_kb), updated every tick.
4. On completion the row resolves to ✓ (green) and stays; the next folder begins.

State machine per row: `queued → copying → verifying → done` (or `failed`). Glyphs: `○ ⠋…⠏ ✓ ✗`.

`_rows_render` reads parallel indexed arrays: `ROW_LABEL[i] ROW_PCT[i] ROW_STATE[i] ROW_TOTKB[i] ROW_DSTKB[i]`.

## 8. Spinner helper

```
spin <label> -- <cmd...>
  if ! _ui_animated: run <cmd...>; print plain "✓/✗ label"; return $?
  print "⠋ label …"
  <cmd...> &  pid=$!
  while kill -0 $pid: rewrite line (tput cuu1; tput el) with next frame; sleep 0.08
  wait $pid; st=$?
  rewrite final: ✓ label   (st==0)   |   ✗ label   (st!=0)
  return st
```

Applied to **genuinely async** work: the `update` curl download, `sync`'s guard+mirror run.
`doctor`'s checks are near-instant — they reveal immediately as ✓/✗ with an optional tiny (~60ms)
stagger for a "typed-out" feel. **No artificial latency** is added to fake work being slow.

## 9. `limpet watch` — the live view

New command. Interactive only (if `! _ui_animated`, print a one-shot `status` and exit).

```
cmd_watch
  require_config
  tput civis                          # hide cursor
  trap 'tput cnorm; echo' INT TERM EXIT
  prev_present = unset
  loop:
      present = drive_present ? 1 : 0
      gather per-folder state (symlink→target / local / missing)   # cheap: readlink + [ -d ]
      if present changed since prev: queue a transient log line
          unplug:  "! drive unplugged — failing over…"  (warn)
          replug:  "▸ drive back — merging offline work…" (blue)
      _rows_render the block:
          "● X9  connected/UNPLUGGED"  (● pulses via frame-based brightness)
          "guard loaded"
          per folder: ✓ symlink→target | • local — failover | ? missing
          help/log line
      read -t 0.4 -n 1 key            # doubles as frame delay + quit
      [ "$key" = q ] && break
      prev_present = present
```

- The **pulse** comes from redrawing every ~0.4s and alternating the `●` color intensity by frame parity.
- `read -t 0.4 -n 1` is the sleep *and* the `q`-to-quit handler in one — no busy loop.
- `watch` only *observes*; the launchd guard still does the real symlink flipping. This keeps `watch`
  read-only and safe to run anywhere.

## 10. Mirror % integration

`run_mirror` already loops `MIRROR_LIST` entries and `rsync`es each. Wrap each entry's rsync in
`_copy_with_bar` (source under `$DRIVE`, dest under `$MIRROR_DEST`), labeled `path (i/N)`. Because the
whole thing is behind `_ui_animated`, the **hook's** non-TTY mirror run is unaffected (plain, silent),
while `limpet sync` / `limpet mirror` from a terminal shows bars. The TTY gate does the split for free.

## 11. Integration points

| Surface | Change |
|---|---|
| `move_to_drive` | `ditto "$src" "$dst"` → `_copy_with_bar "$label" "$src" "$dst" -- ditto "$src" "$dst"`; verify then ✓ |
| `cmd_setup` | wrap the folder loop in the N-row block + aggregate footer |
| `cmd_link` / `cmd_unlink` | single-row `_copy_with_bar` |
| `run_mirror` | per-entry `_copy_with_bar` (TTY only) |
| `cmd_sync` | `spin` around the **guard** step only; the mirror renders its own per-entry bars (spinning around it would fight its cursor rewrites) |
| `cmd_update` / `_do_update` | `spin` around the curl download (stretch: real download bar via `Content-Length`) |
| `cmd_doctor` | checks reveal as ✓/✗ (optional micro-stagger) |
| `cmd_watch` | **new** command + `main()` dispatch + help + README entry |
| `cmd_help` / README | add `watch`; bump version; update line-count claim; link `docs/cli.html` |

## 12. Degradation matrix (the golden rule)

| Context | `_ui_animated`? | Output |
|---|---|---|
| Interactive terminal | yes | animated bars/spinners/watch |
| `\| pipe`, `> file`, `$(...)` | no (`! -t 1`) | plain lines (today's output) |
| `NO_COLOR=1` | no | plain lines |
| `--dry-run` | no | intended-action lines |
| launchd guard (`__guard`) | no (stdout→/dev/null, non-tty) | unchanged, zero escapes |
| shell hook (`__guard`/`__mirror`/`__autoupdate`) | no | unchanged, zero escapes |

## 13. Data-safety guarantee

Animation wraps, never replaces, the copy/verify/swap logic. `verify_copy` still runs before any `rm`.
A `Ctrl-C` mid-copy triggers the trap: kill the background `ditto`/`rsync`, restore the cursor
(`tput cnorm`), print a newline — and because the source is only removed *after* verify, the interrupted
copy leaves everything intact (the partial dest is overwritten/cleaned on the next run, as today).

## 14. Helper API reference

```bash
_ui_animated()            # 0 iff [ -t 1 ] && [ -z NO_COLOR ] && [ "$DRY_RUN" != 1 ]
_human_kb <kb>            # 1887436 -> "1.8 GB" ; 245760 -> "240 MB" ; 512 -> "512 KB"
_bar_str <pct> <width>    # 50 20 -> "██████████░░░░░░░░░░" (with eighth partial cell)
_spin_frame <i>           # i -> ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏[i % 10]
spin <label> -- <cmd...>  # async step, resolves ✓/✗ by exit code
_copy_with_bar <label> <src> <dst> -- <cmd...>   # du-poll progress around a real copy
_rows_render                                       # repaint the stacked block in place
cmd_watch                                          # live view loop
```

**Integer math (no floats in bash 3.2):**
- `pct = dst_kb * 100 / total_kb` (guard `total_kb>0`)
- sub-cell: `eighths = dst_kb * width * 8 / total_kb`; `full = eighths/8`; `partial = eighths%8`
- `_human_kb`: GB branch (`kb>=1048576`) prints `whole.tenth GB` where
  `whole=kb/1048576`, `tenth=(kb%1048576)*10/1048576`.

## 15. Edge cases

- **Tiny copies** (`total_kb < BAR_MIN_KB`) → skip the bar, run plainly (no flash).
- **`du` returns 0 / dest missing early** → treat as 0%, don't divide by zero.
- **Dest pre-exists** (verify-instead-of-copy path in `move_to_drive`) → no copy happens; show an instant
  `verifying → ✓` instead of a fill.
- **Terminal too narrow** → bar width is `min(22, COLUMNS-overhead)`; never wraps.
- **Window resize mid-copy** → next full repaint self-corrects (we don't cache pixel positions).
- **Multiple rows + Ctrl-C** → trap restores cursor and leaves the block visible with a failed marker.

## 16. `docs/cli.html` (site page)

Polish the prototype into a site page in the existing visual language (Geist Mono, teal/emerald palette,
`.macwin` chrome — already matched). Add:
- link from `README.md`'s site-links row (`▶ CLI preview`),
- a "new in v0.2" pointer from `docs/index.html`,
- an entry in `docs/sitemap.xml`.
Self-contained (fonts via the same Google Fonts link, `ui-monospace` fallback). This is a distinct work
item from the bash change and can land in the same release.

## 17. Testing

New `test/test-ui.sh` (extends the `test/test-guard.sh` pattern), all runnable without a TTY:
- **Pure helpers:** `_human_kb` (KB/MB/GB boundaries), `_bar_str` (0/50/100%, width, eighth partial),
  `_spin_frame` (wraps at 10), pct integer math.
- **Golden-rule guard:** run a copy path with stdout piped (`limpet setup --dry-run | cat`, and a real
  `_copy_with_bar` with a stub `cmd`), assert **zero** `0x1b` (ESC) bytes in output.
- **Non-regression:** existing `test-guard.sh` still passes unchanged (animation is additive).

## 18. Footprint, README & version

- File grows ~505 → ~620 lines. Update README: the "~300 lines" line becomes an honest "~600 lines,
  still one file, still zero dependencies."
- Add `watch` to README command reference and `cmd_help`.
- Bump `LIMPET_VERSION="0.2.0"`.
- One-line changelog entry (README or CHANGELOG) for the release.

## 19. Rollout

Land on `feat/v0.2-animated-cli`: (1) UI layer + engine, (2) command wiring, (3) `watch`, (4) tests,
(5) `docs/cli.html` + site links, (6) README/version. Tag `v0.2.0` for the GitHub release the self-updater
pulls from.

## 20. Out of scope

Parallel copies · non-macOS · color theming · a TUI framework · progress for the guard/hook paths
(they're intentionally silent).
