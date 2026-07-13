# AGENTS.md — limpet

Reference for AI agents and contributors working **on** limpet's code or driving it **for** a user. Read this before editing `limpet` or running it on someone's machine.

## What this is

`limpet` makes an external drive the primary location for chosen home folders on macOS, and keeps the user working when the drive is unplugged. One pure-bash file (`limpet`), no build step, no dependencies beyond macOS built-ins (`launchd`, `ditto`, `rsync`, `shasum`, `curl`).

## Architecture (the whole thing)

```
limpet (single script)
├── config         ~/.config/limpet/config         DRIVE, FOLDERS[], MIRROR_DEST, AUTO_UPDATE, GUARD_INTERVAL
│                  ~/.config/limpet/mirror-paths.txt  drive-relative paths to mirror offline
│                  ~/.config/limpet/env.conf          VAR = drive-relative path  (build-cache offload)
├── state/logs     ~/.local/state/limpet/           logs, throttle stamps, *.lock.d, update flag
├── guard          launchd com.limpet.guard         RunAtLoad + WatchPaths /Volumes (+ optional StartInterval) → `limpet __guard`
└── terminal hooks two blocks in ~/.zshrc / ~/.bashrc
                   • self-heal (backgrounded): throttled `__guard` + `__mirror` + `__autoupdate`
                   • env       (foreground):   `eval "$(limpet env --shell)"` — sets cache vars in the shell
```

`limpet env` points chosen env-vars (GOCACHE, GRADLE_USER_HOME, …) at the drive when present and **unsets**
them when absent, so build tools fall back to their internal-disk cache offline instead of erroring. The
`env` block runs in the **foreground** (it must mutate the current shell), unlike the backgrounded
self-heal block. `env --shell` is the machine contract consumed by that block.

Two execution contexts, by design:

1. **Background guard** (`launchd`) — fires on any mount/unmount. Only stats the mountpoint and does **local** symlink swaps, so it works **without Full Disk Access**. It cannot reliably write to the external volume (macOS TCC).
2. **Terminal hook** — runs the same code from an interactive shell, which **does** have disk access, so it completes the parts the background agent can't: merging offline files back onto the drive and refreshing the mirror.

## Invariants — do not break these

- **Verify before delete.** Any move-onto-drive must `ditto` → byte-verify a path+size manifest (excluding `.DS_Store` and `._*`) → only then remove the source. See `move_to_drive` / `verify_copy`. Never delete unverified.
- **Never overwrite on merge.** Failback (`_guard_one`) moves offline files back; on a name clash it renames to `name.local-<timestamp>`. Keep-both, always.
- **The guard must not require Full Disk Access.** Keep `__guard` limited to `stat`/`readlink`/local `ln`/`mkdir`/`rmdir`. Anything needing to read/write the external volume's contents belongs in the terminal-hook path, guarded by `drive_present`.
- **`drive_present` is mount-aware.** For a real `/Volumes/*` drive it requires a live `mount` table entry, not just `[ -d ]` — a hollow mountpoint left by an unclean eject must read as *absent* so failover fires (otherwise apps/dev-servers see an empty tree and can't load files). Non-`/Volumes` paths (the test harness) fall back to `[ -d ]`. Do not revert to a bare directory check.
- **`env --shell` is side-effect-free and shell-clean.** It runs foreground in every new shell. No logging, locks, network, or `mkdir`: read config + `env.conf`, then print only `export VAR="$DRIVE/path"` (drive present) or `unset VAR` (absent). Nothing else may reach stdout, or it corrupts the `eval`.
- **Single-instance lock.** `with_lock <name>` (mkdir-based, steals if stale >2min) wraps guard and mirror so launchd + terminal runs never collide. Keep new periodic work under a lock.
- **No module-level surprises / idempotency.** Every command must be safe to run repeatedly. `setup` detects an existing install and adopts already-symlinked folders rather than re-copying.
- **Bash 3.2 compatible.** macOS ships bash 3.2. No associative arrays, no `mapfile`, no `${var^^}`. Expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}` under `set -u`. CI/local check: `/bin/bash -n limpet`.
- **`// ABOUTME:` header.** Keep the two ABOUTME comment lines at the top of every file.

## Driving limpet for a user (non-interactive)

Everything is scriptable — never assume a TTY when automating:

```bash
limpet setup --drive /Volumes/<NAME> --folders Documents,Downloads,Desktop --yes
limpet link <abs-path> --yes          # move any path onto the drive + symlink
limpet status --json                  # { setup, drive, drive_present, agent_loaded, folders[] }
limpet sync                           # reconcile now
limpet doctor                         # health report (also auto-offers agent reinstall under --yes)
```

- Use `--yes` to suppress prompts and `--dry-run` to preview without changing anything.
- Parse `limpet status --json` rather than scraping human output.
- Before destructive guidance, prefer `limpet doctor` to detect the drive-rename gotcha (`/Volumes/X9 1`).

## Verification policy (how to prove a change works)

Use a **real filesystem**, not mocks. The canonical test sandboxes `HOME` + a fake drive dir and exercises the full cycle:

```bash
bash test/test-guard.sh     # symlink → unplug → offline edit → replug → merge-back/keep-both; 11 assertions
bash test/test-env.sh       # env --shell present/absent, eval, add/rm/upsert, validation; 16 assertions
bash test/test-ui.sh        # animation layer resolves child exit + stays silent off-TTY
```

When changing guard/mirror/move logic, extend `test/test-guard.sh` with the new case and keep it green on both `/bin/bash` (3.2) and a modern bash. Do **not** test by registering the real `launchd` agent or editing the user's real shell rc — the test bypasses `setup` and writes config directly so it touches nothing outside its temp dir.

## Release / update mechanism

- Versions are GitHub Releases tagged `vX.Y.Z`; `LIMPET_VERSION` in the script must match the tag.
- `limpet update` pulls the release asset `limpet` (falls back to the raw script at the tag), **syntax-checks it**, then swaps the binary.
- `__autoupdate` (daily, via the hook) auto-applies only when `AUTO_UPDATE=1`, else records availability for a one-line notice. Keep the syntax-check-before-swap guard.
- Bumping a release: update `LIMPET_VERSION`, tag `vX.Y.Z`, attach the `limpet` file as a release asset.

## Gotchas

- `WatchPaths /Volumes` fires on *any* volume change, not just the target drive — `__guard` must no-op cheaply when nothing relevant changed.
- The terminal hook runs backgrounded; never make it print to stdout on a normal shell start (keep it `>/dev/null 2>&1`).
- `SELF` is the absolute path of the installed script, baked into the plist and hook. If the binary moves, `limpet doctor` should catch it; re-running `setup` re-points them.
