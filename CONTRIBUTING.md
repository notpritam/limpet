<!-- ABOUTME: How to contribute to limpet — setup, conventions, and the test gate. -->
<!-- ABOUTME: Keep this short; the architecture and invariants live in AGENTS.md. -->

# Contributing to limpet

Thanks for helping! limpet is intentionally tiny — one pure-bash file — so the bar is "keep it small, safe, and auditable."

## Before you start

Read **[AGENTS.md](AGENTS.md)** — it lists the invariants you must not break (verify-before-delete, never-overwrite-on-merge, guard-needs-no-Full-Disk-Access, bash 3.2 compatibility).

## Dev loop

```bash
git clone https://github.com/notpritam/limpet
cd limpet

# syntax-check on the macOS system bash (3.2) AND a modern bash
/bin/bash -n limpet && bash -n limpet

# run the real-filesystem end-to-end test (sandboxes HOME + a fake drive, no mocks)
bash test/test-guard.sh
```

The test must stay green and must not touch anything outside its temp dir (it bypasses `setup`, so it never registers a launchd agent or edits your shell rc).

## Conventions

- **Pure bash, 3.2-safe.** No associative arrays, no `mapfile`, no `${var^^}`. Expand maybe-empty arrays as `${arr[@]+"${arr[@]}"}`.
- **Two `// ABOUTME:` lines** at the top of every file.
- **macOS built-ins only** (`launchd`, `ditto`, `rsync`, `shasum`, `curl`). No new runtime dependencies.
- **Every new periodic action takes a lock** (`with_lock`) and is safe to run repeatedly.
- Anything that reads/writes the external volume goes in the **terminal-hook** path (guarded by `drive_present`), never in the background guard.

## Pull requests

1. Add/extend a case in `test/test-guard.sh` for the behavior you change.
2. Keep the diff focused; explain *why* in the PR description.
3. If you change the release/update flow, note it in `AGENTS.md`.

## Reporting issues

Tell us your macOS version, the output of `limpet status` and `limpet doctor`, and the relevant lines from `~/.local/state/limpet/limpet.log`.
