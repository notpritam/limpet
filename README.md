<!-- ABOUTME: Public README for limpet — the what/why/how, install, and command reference. -->
<!-- ABOUTME: Audience-facing and generic; per-machine specifics live in the user's own config. -->

# 🐚 limpet

**Use an external drive as your primary storage on macOS — without it breaking when you unplug.**

A limpet is the little mollusk that clamps tight to its rock, yet detaches and re-attaches cleanly with the tide. That's the idea: your folders cling to the external drive, but they survive every unplug and re-attach themselves when the drive comes back.

```
~/Documents ─▶ /Volumes/X9/Documents      drive connected → you work straight off the SSD
~/Documents ─▶ (real local folder)         drive unplugged → saving still works, no errors
~/Documents ─▶ /Volumes/X9/Documents      drive back → offline work merged in, never overwritten
```

Single file. Pure bash. **No kernel extensions, no daemons, no network.**

---

## The problem

Macs ship with small, expensive internal storage, so a lot of people put their `Documents`, `Downloads`, `Desktop`, and project folders on a cheap external SSD and symlink to it. It works great — until the drive is unplugged.

The moment that happens, a plain symlink points to **nothing**:

- saves fail and apps throw errors,
- your Desktop and Documents look empty,
- and a reboot can silently recreate empty folders, **splitting your files across two places**.

macOS has never had a "work offline, sync when it's back" mechanism for this (the way Windows has Offline Files). So the usual options are: babysit the cable, or give up and keep everything on the internal disk.

## The solution

`limpet` makes the external drive your **primary** storage and adds an automatic safety net:

- **Connected** → your folders are symlinks straight to the drive. Zero overhead, full speed.
- **Unplugged** → within a second, limpet turns each folder back into a **real local folder** so every save keeps working.
- **Reconnected** → limpet moves whatever you created while offline back onto the drive, **keeping both copies on any name clash** — it never overwrites.

It's *offline mode for your drive.*

---

## Quick start

```bash
# 1. install
curl -fsSL https://raw.githubusercontent.com/notpritam/limpet/main/install.sh | bash

# 2. set it up (interactive: pick a drive, pick folders)
limpet setup

# 3. check anytime
limpet status
```

That's it. `limpet setup` moves the folders you choose onto the drive (verified copy first — see [Safety](#safety--security)), replaces them with symlinks, and installs the background guard plus a terminal hook. Open a new terminal afterward to activate the hook.

> Prefer not to pipe to bash? Clone the repo and run `./install.sh`, or just copy the single `limpet` file anywhere on your `PATH`.

---

## How it works

Two small, cooperating pieces — that's the whole tool.

### 1. The guard (instant failover)

A launchd agent with `WatchPaths /Volumes`. macOS fires it the instant **any** drive mounts or unmounts, so limpet reacts to a plug/unplug within a second:

- **drive gone** → symlinked folder becomes a real local folder (saves keep working),
- **drive back** → folder becomes a symlink again, after merging anything you saved offline.

It only *stats* the mountpoint and does local symlink swaps, so it needs **no Full Disk Access**.

### 2. The terminal hook (finishes the job)

macOS security (TCC) blocks background agents from writing to external volumes. So the part that copies your offline work back **onto** the drive runs from your terminal instead — which is allowed — via a tiny throttled hook in your shell rc. It also refreshes an offline-readable mirror of any critical paths you nominate, and does the daily update check.

```
        plug/unplug event
               │
      ┌────────▼─────────┐         ┌───────────────────────┐
      │   guard (launchd) │  ◀────  │  terminal hook (rc)   │
      │  instant failover │         │  merge-back + mirror  │
      └───────────────────┘         │  + daily update check │
                                    └───────────────────────┘
```

A `mkdir`-based lock means the two never collide.

---

## Commands

| Command | What it does |
|---|---|
| `limpet setup` | Interactive wizard: pick a drive + folders, move them over, install the guard. |
| `limpet status` | Drive + folder state. `--json` for machine-readable output. |
| `limpet list` | Managed folders + any ad-hoc links you've made into the drive. |
| `limpet link <path>` | Move **any** extra file/folder onto the drive and symlink it back. |
| `limpet unlink <path>` | Bring a symlinked path back onto the local disk. |
| `limpet doctor` | Health-check and offer fixes (agent loaded? drive renamed?). |
| `limpet sync` | Run the failover/failback + mirror right now. |
| `limpet update` | Update limpet to the latest release (`--check` only checks). |
| `limpet uninstall` | Remove the guard + hook (optionally restore folders to local). |

Global flags: `--yes` (never prompt), `--dry-run` (print actions, change nothing).

---

## Do it yourself, or let an agent do it

limpet is built so a person can drive it interactively **and** a script or AI agent can drive it non-interactively — same tool, no GUI required.

**Interactive (you):**
```bash
limpet setup            # answers a couple of prompts
```

**Non-interactive (scripts / agents):**
```bash
limpet setup --drive /Volumes/X9 --folders Documents,Downloads,Desktop --yes
limpet link  /Volumes/X9/Projects/my-app --yes
limpet status --json
```

### Linking any path

You're not limited to `Documents`/`Downloads`/`Desktop`. Point anything at the drive:

```bash
limpet link ~/Dev            # move ~/Dev onto the drive, leave a symlink
limpet link ~/Movies/4k.mov  # single files work too
limpet list                  # see everything that's linked
```

Already symlinked things by hand? `limpet setup` and `limpet link` **detect existing links and adopt them** instead of re-copying.

---

## Self-update

```bash
limpet update           # check GitHub Releases and install the latest
limpet update --check   # just tell me if there's a newer version
```

Turn on automatic checks during `limpet setup` (or set `AUTO_UPDATE=1` in the config). With it on, limpet checks once a day from your terminal and either applies the update silently or shows a one-line notice — your choice. Every downloaded version is **syntax-checked before it replaces the running binary.**

---

## Safety & security

- **Verified copy before delete.** When moving a folder onto the drive, limpet does a `ditto` copy, then byte-verifies a manifest of every file before removing the original. If verification fails, the original is left untouched.
- **Never overwrites.** On reconnect, a file that exists in both places is kept as `name.local-<timestamp>` — you never lose either version.
- **No elevation, no extensions.** No kernel extensions, no background servers, no network calls (except the optional update check). It's ~300 lines of bash you can read in one sitting.
- **Not a backup.** limpet keeps your data *available and resilient to unplugs* — it is **not** a substitute for Time Machine or an offsite backup. Keep one.

---

## Caveats (the honest list)

- **Eject cleanly.** If a drive is yanked without ejecting, macOS may remount it as `"X9 1"`. limpet keys off the exact mount path, so `limpet doctor` will flag this — eject and replug to restore the name.
- **The drive still holds your data.** Failover keeps you *working*; it doesn't conjure the files that live on an absent drive. Nominate critical paths for the offline mirror if you need them readable while unplugged.
- **macOS only.** It relies on `launchd`, `ditto`, and APFS behavior.

---

## Uninstall

```bash
limpet uninstall        # removes the guard + terminal hook
                        # offers to turn folders back into normal local folders
```

Your config stays at `~/.config/limpet/` until you delete it.

---

## How it's built

- `limpet` — the entire CLI, one pure-bash file.
- `install.sh` — the curl-able installer.
- `test/test-guard.sh` — real-filesystem end-to-end test (no mocks): symlink → unplug → offline edit → replug → merge-back with keep-both. Run it with `bash test/test-guard.sh`.
- `share/com.limpet.guard.plist.tmpl` — the LaunchAgent, shown for transparency.
- `AGENTS.md` — architecture + invariants for humans and AI agents working on the code.

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Pritam Sharma
