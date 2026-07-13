<!-- ABOUTME: Design spec for limpet v0.3 — `limpet env` (offload build-cache env-vars to the drive) + optional guard interval. -->
<!-- ABOUTME: Also records the one-time migration of the author's hand-rolled x9-* subsystem onto limpet as the canonical owner. -->

# limpet v0.3 — `limpet env` (cache offload) + guard hardening

**Status:** approved design, ready to plan
**Date:** 2026-07-13
**Branch:** `feat/v0.3-env-offload`

---

## 1. Summary

limpet already makes an external drive your primary storage for **folders** (`Documents`, `Downloads`,
`Desktop`, and any `limpet link` path) with instant local failover. But a real "run my Mac off the SSD"
setup also puts **build caches** on the drive — Go, Gradle, npm, the Android SDK — via environment
variables (`GOCACHE`, `GOMODCACHE`, `GRADLE_USER_HOME`, `NPM_CONFIG_CACHE`, `ANDROID_HOME`). Today limpet
has no concept of these, so users hand-roll a `.zshrc` block. That block is fragile, invisible to
`limpet status`, and doesn't fail over when the drive is unplugged.

v0.3 adds **`limpet env`**: a config-driven, drive-aware set of environment exports that point at the
drive when it's connected and fall back to the tool defaults when it's not — managed the same way the
self-heal hook is (one marked block in your shell rc), fully visible in `limpet status`/`doctor`.

Still one file, pure bash, zero dependencies, invisible off a TTY.

This spec also records a **one-time migration**: the author (me) currently runs a hand-rolled `x9-*`
subsystem that predates limpet. limpet fully subsumes it. We retire the `x9-*` machinery and make limpet
the single owner — driven entirely through `limpet` commands so the state stays observable.

## 2. Goals / non-goals

**Goals**
- A generic `limpet env` feature: declare `VAR → path-relative-to-drive`; limpet exports each to
  `$DRIVE/<path>` when the drive is present, and leaves it unset (tool default) when absent.
- Config-as-source-of-truth (`~/.config/limpet/env.conf`); editing it takes effect on the next shell,
  no rc rewrite.
- Surface env state in `limpet status` and `limpet doctor`.
- Optional belt-and-suspenders: a configurable guard `StartInterval` so a *missed* mount/unmount event
  (e.g. across sleep/wake) still self-corrects without needing a terminal. Off by default; conservative.
- One-time: migrate the author's machine off `x9-*` onto limpet, non-destructively, reversibly.
- Ship it: v0.3.0 tagged + pushed + GitHub release + reinstalled on PATH.

**Non-goals (YAGNI)**
- A local *fallback cache directory* when unplugged. Unset → tool default (matches the existing
  hand-rolled behavior and is least-surprising). Can be added later if requested.
- Managing arbitrary shell config (aliases, `PATH`, functions). limpet owns *storage-relevant* env only.
- Cross-shell beyond `zsh`/`bash` (limpet is macOS-only; fish etc. out of scope).
- Migrating personal navigation aliases into limpet — those are machine-specific shortcuts, not linkage
  (see §6).

## 3. Locked decisions

| Decision | Choice |
|---|---|
| Mechanism | **Environment variables**, not symlinks. Go/Gradle/npm/Android respect their cache env-vars; cache *symlinks* are less reliable and would pointlessly ride the folder-failover path. |
| rc integration | A **dynamic** marked block: `eval "$(limpet env --shell)"` at shell start. Config is the source of truth; the block never needs rewriting when `env.conf` changes. |
| Offline behavior | Drive absent → emit nothing → vars stay unset → tools use their internal-disk defaults. |
| Config format | `~/.config/limpet/env.conf`, one `VAR = relative/path` per line, `#` comments. Seeded with commented examples on `setup`. |
| Guard interval | New optional `GUARD_INTERVAL` config → plist `StartInterval`. Default `0` (unset; unchanged public behavior). Author's machine: `300`. |
| Personal aliases | Kept in `.zshrc`, relocated to a clean "personal shortcuts" section, out of the retired x9 blocks. Not limpet's domain. |

## 4. Design — `limpet env`

### 4.1 Config (`$CONFIG_DIR/env.conf`)

```
# limpet env — environment variables to point at the drive when it is connected.
#   VAR = relative/path/under/drive     → export VAR="$DRIVE/<path>" when the drive is present
# When the drive is unplugged the variable is left UNSET (tools use their internal-disk defaults).
# '#' = comment. Edits take effect in the next shell (or run `limpet env` to preview).
#
# GOCACHE          = Caches/go-build
# GOMODCACHE       = Caches/go-mod
# GRADLE_USER_HOME = Caches/gradle
# NPM_CONFIG_CACHE = Caches/npm
# ANDROID_HOME     = Android/sdk
# ANDROID_SDK_ROOT = Android/sdk
```

Parsing: split on the first `=`, trim whitespace around key and value, skip blank/`#` lines, ignore a
trailing `\r`. Reuse the tolerant read pattern already used by the mirror list.

### 4.2 Shell block (managed, like the self-heal hook)

```
# >>> limpet env >>>
# limpet: point build-cache env-vars at the external drive when it is connected.
command -v limpet >/dev/null 2>&1 && eval "$(command limpet env --shell 2>/dev/null)"
# <<< limpet env <<<
```

Installed/removed by `install_hook`/`uninstall_hook` alongside the existing self-heal block (both blocks,
one function pass). Idempotent (guarded by the begin/end markers, same as today).

### 4.3 Commands

| Command | Behavior |
|---|---|
| `limpet env` | Human view: each `VAR`, its resolved target, and `active`/`inactive` (drive present + path exists). Shows a hint if the rc block is missing. |
| `limpet env --shell` | Machine output for `eval`: prints `export VAR="$DRIVE/path"` per entry **only when the drive is present**; nothing otherwise. Never prints errors to stdout. |
| `limpet env add VAR path` | Upsert a mapping into `env.conf` (validates `VAR` is a shell-safe identifier). |
| `limpet env rm VAR` | Remove a mapping. |
| `limpet env edit` | Open `env.conf` in `$EDITOR` (fallback `nano`). |

`--shell` must be side-effect-free and fast (it runs in every new shell): `load_config`, read `env.conf`,
print. No logging, no locks, no network.

### 4.4 status / doctor / setup integration

- **`status`** gains an "env offload" section: `N vars → drive` with per-var active/inactive; `--json`
  gains an `"env"` array (`{name,target,active}`).
- **`doctor`** checks the `>>> limpet env >>>` block is present when `env.conf` has ≥1 active mapping;
  offers to reinstall the hook if missing.
- **`setup`** seeds `env.conf` (commented examples) if absent and prints a one-line pointer. Setup stays
  non-interactive-friendly; no new prompts required for automation.

## 5. Design — guard hardening (optional interval)

`install_agent` learns an optional `StartInterval`:

- `save_config` persists `GUARD_INTERVAL` (default `0`).
- When `> 0`, the generated plist adds `<key>StartInterval</key><integer>$GUARD_INTERVAL</integer>`.
- The guard is already idempotent and cheap (stat the mountpoint + local symlink swaps, **no** Full Disk
  Access, mkdir-lock against the hook). A periodic run only *corrects* a missed transition; it never
  duplicates work. `share/com.limpet.guard.plist.tmpl` updated to show the optional key.

Rationale for "never breaks again": WatchPaths + RunAtLoad + terminal-hook already cover plug/unplug and
active use, but a transition that happens entirely while the Mac is asleep can be missed until the next
event. A modest interval (author: 300 s) closes that gap for headless stretches. Kept **off by default**
so the public tool's behavior is unchanged unless a user opts in.

## 6. Migration (author's machine — one-time, reversible)

Everything below is driven through `limpet` (or is a clean removal of the superseded prototype), so the
result is observable via `limpet status`/`watch`/`doctor`.

**Retire the `x9-*` subsystem** (archive first to `~/.local/state/limpet-migration-backup-<ts>/`):
- `launchctl bootout` + archive `~/Library/LaunchAgents/com.notpritamm.x9-storage-guard.plist`.
- Archive `~/.local/bin/x9-storage-guard.sh`, `~/.local/bin/x9-critical-mirror.sh`.
- Remove the two x9 blocks from `.zshrc` (the `=== X9 external SSD storage ===` env block and the
  `=== X9 storage self-heal ===` hook). **Back up `.zshrc` first.**
- **Keep** the X9 quick-nav / SSD-extras aliases (`x9`, `xdev`, `e1`, `fil`, `mo`, `x9cd`, `ssd`, `docs`,
  `projs`, `proj`) — relocated to a "personal shortcuts" section. They are navigation, not linkage.

**Stand limpet up** (all via limpet):
1. Install v0.3.0 to `~/.local/bin/limpet` (replaces the stale v0.1.0), so the rc/plist `$SELF` is stable.
2. `limpet setup --drive /Volumes/X9 --folders Documents,Downloads,Desktop --yes` — **adopts** the
   existing symlinks (no re-copy, no data movement), installs the guard + self-heal + env hooks.
3. Seed mirror: add `Documents/scripts` to `~/.config/limpet/mirror-paths.txt` (from the old
   `x9-critical-paths.txt`).
4. Seed env: write the 5 cache vars (+ `ANDROID_SDK_ROOT`) into `env.conf`.
5. Set `GUARD_INTERVAL=300`, reinstall the agent.
6. Verify: `limpet status` (drive connected, guard loaded, folders ✓, env active), `limpet doctor` clean.

**Invariant:** the drive is mounted and links are valid throughout, so there is never a window where no
guard owns the folders.

## 7. Release (v0.3.0)

1. `LIMPET_VERSION=0.3.0`; bump every version string (`grep -rn 0.2.0` across `limpet`, `README.md`,
   `docs/*.html` JSON-LD `softwareVersion`, `docs/llms.txt`, `docs/sitemap.xml` as applicable).
2. README: add `env` to the command table + a short "Cache offload" section. `AGENTS.md`: document the
   env feature + the `--shell` contract + guard interval. Help text updated.
3. Test: add `test/test-env.sh` — pure, no drive needed: given an `env.conf` and a fake present/absent
   `DRIVE`, assert `env --shell` emits the right exports (present) and nothing (absent). Keep
   `test/test-guard.sh` green.
4. Commit on `feat/v0.3-env-offload`, open/merge to `main` (fast-forward is fine for a solo repo), tag
   `v0.3.0`, push branch + tag.
5. `gh release create v0.3.0 ./limpet --title "v0.3.0 — cache offload (limpet env)" --notes …`
   (asset **must** be the `limpet` file so `install.sh`/`limpet update` can fetch it).
6. Re-verify `limpet update --check` reports latest and the PATH binary is v0.3.0.

## 8. Testing / verification

- `bash test/test-env.sh` and `bash test/test-guard.sh` pass.
- `bash -n limpet` (syntax) clean.
- Live: `limpet status --json` shows `drive_present:true`, `agent_loaded:true`, all folders `symlink`,
  env vars `active`; a **new shell** has `GOCACHE` etc. pointing under `/Volumes/X9`.
- Unplug rehearsal (documented, not destructive in this session): `limpet watch` flips folders to
  failover and `env --shell` emits nothing.

## 9. Risks & rollback

| Risk | Mitigation |
|---|---|
| Two guards briefly co-exist during migration | Remove x9 agent *before* `limpet setup`; both are idempotent + mkdir-locked; drive stays mounted. |
| `.zshrc` edit breaks the shell | Timestamped backup; only marked/known blocks touched; `bash -n`/`zsh -n` the result. |
| `env --shell` slows shell startup | Single fast `limpet` exec, no I/O beyond reading two small files; measured target < 30 ms. |
| gh release under the one-m `notpritam` repo vs `notpritamm` CLI account | git push is SSH (independent). If `gh release create -R notpritam/limpet` hits perms, surface it and fall back to web/API. |
| Adopting existing links misfires | `move_to_drive` already short-circuits on `-L` (existing symlink) → no copy; `--dry-run` available. |

## 10. Ordered task plan

1. **Feature:** implement `limpet env` (config parse, `--shell`, `env`/`add`/`rm`/`edit`, dispatch), wire
   into `install_hook`/`uninstall_hook`, `status` (+json), `doctor`, `setup` seeding.
2. **Feature:** `GUARD_INTERVAL` in config + `install_agent` + plist template.
3. **Tests + docs:** `test/test-env.sh`; README/AGENTS/help + version bumps.
4. **Migration:** archive + remove x9 subsystem; clean `.zshrc`; install v0.3.0; `limpet setup`; seed
   mirror + env; `GUARD_INTERVAL=300`; verify with `status`/`doctor`.
5. **Release:** commit, tag `v0.3.0`, push, `gh release create`, re-verify PATH + update check.
