<!-- ABOUTME: Design spec for limpet v0.4 — `limpet organize`, an opt-in automatic file organizer (sort idle files by type/rule). -->
<!-- ABOUTME: Off by default. User-chosen sort mode + timing, per-type destinations, keep-both safety, move-log undo, daily hook run. -->

# limpet v0.4 — `limpet organize` (opt-in auto file organizer)

**Status:** approved design, ready to plan
**Date:** 2026-07-14
**Branch:** `feat/v0.4-organize`

---

## 1. Summary

An opt-in file organizer built into limpet: it watches folders you choose (default `~/Downloads`), decides
whether each top-level file is safe to move (a user-selected strategy — `quick` / `aged` / `aged-idle`),
and sorts idle files into destinations by **ordered extension→destination rules**. Off by default; when
enabled it runs once a day from the terminal hook (TCC-safe, like the mirror), and can be previewed/run/
undone manually anytime. Pure bash, single file, zero deps, reusing limpet's animated tables and its
keep-both/lock/logging patterns.

Market research (Hazel = ordered rules on aged files; organize-tool = YAML rules + dry-run; Sparkle = 3-day
"Recents" aging window; `lsof` = is-file-open check) informed this. limpet's differentiators: pure-bash,
no subscription, no cloud/AI, and it lives alongside the SSD-offload it already manages.

## 2. Goals / non-goals

**Goals**
- Fully user-controlled: choose the sort **mode** and **timing**, and choose **where each type goes**.
- Two destination styles, mixable: auto **by-type** subfolders in-place, and **per-type explicit** folders.
- Safety-first: never move a live/partial/open file; never overwrite; every move undoable.
- Off by default; daily auto when enabled + manual `preview`/`run`/`undo`.
- A clear dashboard, an interactive `setup` wizard, and granular commands.

**Non-goals (YAGNI — note as future)**
- Content-hash duplicate detection.
- Date-templated destinations (`Images/2026/`).
- Recursing into existing subfolders (v1 organizes **top-level files only**).
- Name/regex/size/content rules (v1 keys off **extension** only; Hazel-style rich conditions later).
- Any network/AI/cloud.

## 3. Config (two files under `$CONFIG_DIR`)

`organize.conf` (sourced; written by `save_organize_config`):
```
ORGANIZE_ENABLED=0          # off by default
ORGANIZE_MODE=aged-idle     # quick | aged | aged-idle
ORGANIZE_IDLE_DAYS=7        # threshold for aged / aged-idle
ORGANIZE_QUICK_MINUTES=30   # threshold for quick
ORGANIZE_WATCH=(Downloads)  # folders (relative to $HOME, or absolute)
ORGANIZE_BY_TYPE=1          # blank-dest rules auto-create <root>/<Category>/
ORGANIZE_DEST_ROOT=         # empty = in-place (inside each watched folder); else absolute root
ORGANIZE_SCHEDULE=daily     # daily | manual
```

`organize-rules.conf` (ordered, first-match wins; `Category | ext,ext | destination`):
```
# destination blank + BY_TYPE=1  →  <DEST_ROOT-or-watched-folder>/<Category>/
Images       | jpg,jpeg,png,gif,heic,webp,svg,bmp,tiff,ico |
Documents    | pdf,doc,docx,txt,md,rtf,odt,pages            |
Spreadsheets | xls,xlsx,csv,numbers                         |
Presentations| ppt,pptx,key                                 |
Video        | mp4,mov,mkv,avi,webm,m4v                     |
Audio        | mp3,wav,flac,aac,m4a,ogg                     |
Archives     | zip,tar,gz,tgz,bz2,rar,7z                    |
Installers   | dmg,pkg                                      |
Code         | sh,py,js,ts,go,rs,c,h,cpp,json,yaml,yml      |
```
Seeded (commented header + these defaults) on first `organize setup`/`enable`. Parsed with the same
tolerant reader as `env.conf` (trim, skip blank/`#`, CRLF-safe); **Category and extensions validated**
(no shell metachars) before use.

## 4. Sort modes (the "is it in use" core)

A candidate is a **top-level regular file** in a watched folder. It is **eligible to move** only if ALL hold:
- not a partial download / temp: name not matching `*.crdownload *.part *.download *.tmp *.partial *.opdownload` and not `.DS_Store`/`._*`;
- not currently being written: size stable across a ~1s recheck;
- age test per **mode**:
  - `quick` — `mtime` older than `ORGANIZE_QUICK_MINUTES`;
  - `aged` — `mtime` older than `ORGANIZE_IDLE_DAYS`;
  - `aged-idle` — `aged` **and** `lsof -- <file>` reports no open handle (not open by any process).
- not a symlink; not hidden (dotfile) unless a rule explicitly targets it (v1: skip dotfiles);
- not itself one of the destination/category folders.

`lsof` is only invoked in `aged-idle` and only per-candidate that already passed the age test (bounded cost).
Files with no matching rule are **left in place** (reported as "unsorted"), never moved.

## 5. Destinations & moving

For an eligible file matching rule `R`:
- `dest = R.destination` if set (tilde/`$HOME` expanded, absolute); else if `ORGANIZE_BY_TYPE=1`,
  `dest = ${ORGANIZE_DEST_ROOT:-<watched-folder>}/<R.Category>`; else the file is left (no implicit dest).
- `mkdir -p "$dest"`; target = `$dest/<basename>`. **Keep-both:** if target exists, insert a timestamp
  (`name.<YYYYmmdd-HHMMSS>.ext`) — never overwrite (limpet invariant).
- Move with `mv` (same-volume = atomic rename; cross-volume = copy-then-unlink, source preserved on failure).
- Append to the move log: `RUNID\tSRC\tDST`. A run shares one `RUNID` (a timestamp, passed in — scripts
  cannot call `date` at will under the workflow constraint, but the CLI can; RUNID = `date +%s` at run start).

**Undo:** `organize undo` reads the log's most-recent RUNID block and reverses each move (last→first),
keep-both if the origin is now occupied, and marks the block reverted.

**Drive-absent guard:** if a watched folder (or its dest) is unreachable because the drive is unplugged,
skip that folder and log it — never fail over or error.

## 6. Command surface

| Command | Behavior |
|---|---|
| `limpet organize` | Dashboard: enabled?, mode+timing, watched folders, rule count, last run, # pending (a fast dry-count). |
| `limpet organize setup` | Interactive wizard: folders → mode → timing → by-type vs per-type dests → enable. Flags for automation: `--folders a,b --mode aged-idle --days N --by-type on --yes`. |
| `limpet organize enable` / `disable` | Toggle `ORGANIZE_ENABLED`; enable seeds rules if absent + ensures the hook. |
| `limpet organize preview` | Dry-run; animated table grouped by destination + a skipped/unsorted summary. Changes nothing. |
| `limpet organize run` | Execute (confirm unless `--yes`); same table live; writes the move log. |
| `limpet organize undo` | Revert the last run. |
| `limpet organize log` | Recent moves (from the log). |
| `limpet organize mode <quick\|aged\|aged-idle> [--days N\|--minutes N]` | Set mode/timing. |
| `limpet organize watch add\|rm\|list <folder>` | Manage watched folders. |
| `limpet organize rule add "<Category> <ext,…> [dest]"` / `rule rm <Category>` / `rule list` / `rule move <Category> <pos>` | Manage ordered rules. |
| `limpet organize set by-type on\|off` / `set dest-root <path>` / `set schedule daily\|manual` | Settings. |
| `__organize` (internal) | Called by the hook; runs only if `ORGANIZE_ENABLED=1`, throttled per `ORGANIZE_SCHEDULE`. |

All under `with_lock organize` so hook + manual runs never collide. `preview`/dashboard are read-only.

## 7. Automation (hook integration)

`install_hook`'s self-heal block gains one throttled line (guarded so it's inert when disabled):
`"$SELF" __organize >/dev/null 2>&1` — `__organize` itself checks `ORGANIZE_ENABLED` and the schedule
stamp (`organize.stamp`, 86400s for daily), so a disabled or manual config is a cheap no-op. No new
LaunchAgent (background launchd can't write external volumes under TCC — same reason the mirror runs here).

## 8. UX

- `organize setup` wizard mirrors `limpet setup`'s style (numbered prompts, `--yes`/flags for scripting).
- `preview`/`run` reuse the `_rows_*` animation: one row per destination with file count + size, a dim
  "skipped (open · downloading · too new)" line, and a footer with totals + the run/undo hint. Off-TTY /
  `--json` gives plain machine output for the dashboard and agents.
- Dashboard (`limpet organize`) is the at-a-glance control center.

## 9. Testing (`test/test-organize.sh`, real FS, no mocks)

Sandbox `HOME` + a watched dir; create files with controlled extensions and mtimes (`touch -t`):
1. aged image/pdf/zip move into the right `by-type` subfolders; a fresh file (mtime now) is **skipped**.
2. explicit per-rule destination honored (e.g. `Installers → $SB/Apps`).
3. partial download (`x.crdownload`) and `.DS_Store` skipped.
4. name clash → **keep-both** (both files survive, timestamped).
5. unmatched extension left in place (unsorted).
6. `undo` restores every moved file to its origin; nothing lost.
7. `--json` dashboard shape.
Plus: `bash -n`, and `test/test-lint.sh` stays green (no `cmd | grep -q` status pipes; capture-first).

## 10. Invariants (preserve)

Bash 3.2 (guard array expansions `${arr[@]+…}`); no `set -o pipefail` + `grep -q`/`head` whose status is
used (capture first); never overwrite (keep-both); verify move didn't clobber; `with_lock`; `// ABOUTME:`
headers; every new interactive path scriptable via flags + `--yes`; off-TTY silent/plain.

## 11. Ordered task plan

1. Config: `organize.conf` + `organize-rules.conf` schema, `load/save_organize_config`, `seed_organize_rules`, tolerant+validated rule parser (`_org_each_rule`).
2. Core: candidate scan (`_org_scan` — top-level files, skip filters), eligibility (`_org_eligible` — mode/age/lsof/partial/size-stable), rule match (`_org_match_rule`), destination resolve (`_org_dest`), keep-both mover (`_org_move`) + move-log.
3. Actions: `preview` (dry-run + animated table), `run` (confirm/`--yes`), `undo`, `log`.
4. Controls: `enable/disable`, `mode`, `watch`, `rule add/rm/list/move`, `set`, dashboard (`cmd_organize` + `--json`).
5. Wizard: `organize setup` (interactive + flags).
6. Hook: throttled `__organize` line; `__organize` gate on enabled+schedule; dispatch entries; help text.
7. Tests: `test/test-organize.sh`; keep guard/env/ui/update/lint green.
8. Docs: README (`organize` section + command table row), AGENTS.md (architecture + invariants), version bump 0.3.2→0.4.0, `docs/index.html` softwareVersion, line-count.
9. Release: commit, tag `v0.4.0`, push + `gh release create` (notpritam account dance), reinstall, verify.
