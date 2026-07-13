<!-- ABOUTME: Public README for limpet — the what/why/how, install, and command reference. -->
<!-- ABOUTME: Audience-facing and generic; per-machine specifics live in the user's own config. -->

<div align="center">

# limpet

### Run your Mac off an external SSD as primary storage — without it breaking when you unplug.

<p>
  <a href="https://limpet.notpritam.in/"><img alt="Website" src="https://img.shields.io/badge/site-limpet.notpritam.in-2dd4bf?style=flat-square"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-f6f8fb?style=flat-square">
  <img alt="Language" src="https://img.shields.io/badge/pure-bash-34d399?style=flat-square">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-60a5fa?style=flat-square"></a>
  <img alt="Dependencies" src="https://img.shields.io/badge/dependencies-0-fbbf24?style=flat-square">
</p>

**▶ [Website](https://limpet.notpritam.in/) · [Launch video](https://limpet.notpritam.in/launch.html) · [Explainer deck](https://limpet.notpritam.in/explainer.html) · [CLI preview](https://limpet.notpritam.in/cli.html)**

</div>

> **Rich enough for the Mac, not rich enough for the 2 TB upgrade?** Same. So I put my `Documents`, `Downloads`, `Desktop` and projects on a cheap external SSD — and got tired of everything breaking every time the cable slipped. limpet is the fix.

A limpet is the little mollusk that clamps tight to its rock, yet detaches and re-attaches cleanly with the tide. That's the idea: your folders cling to the external drive, but they survive every unplug and re-attach themselves when the drive comes back.

```
~/Documents ─▶ /Volumes/X9/Documents      drive connected → you work straight off the SSD
~/Documents ─▶ (real local folder)         drive unplugged → saving still works, no errors
~/Documents ─▶ /Volumes/X9/Documents      drive back → offline work merged in, never overwritten
```

Single file. Pure bash. **No kernel extensions, no daemons, no network.** ~890 lines, still one file, still zero dependencies — with a live progress UI (see the **[CLI preview](https://limpet.notpritam.in/cli.html)**) and drive-aware **build-cache offload** (`limpet env`).

---

## The problem

Macs ship with small, expensive internal storage. So a lot of us put `Documents`, `Downloads`, `Desktop`, and project folders on a cheap **external SSD** and symlink to them. It works great — until the drive is unplugged.

The moment that happens, a plain symlink points to **nothing**:

- saves fail and apps throw errors,
- your Desktop and Documents look empty,
- and a reboot can silently recreate empty folders, **splitting your files across two places**.

macOS has never had a "work offline, sync when it's back" mechanism for external volumes (the way Windows has Offline Files). So the usual options are: babysit the cable, or give up and cram everything back onto the internal disk.

## The solution

`limpet` makes the external drive your **primary** storage and adds an automatic safety net:

- **Connected** → your folders are symlinks straight to the drive. Zero overhead, full speed.
- **Unplugged** → within a second, limpet turns each folder back into a **real local folder** so every save keeps working.
- **Reconnected** → limpet moves whatever you created while offline back onto the drive, **keeping both copies on any name clash** — it never overwrites.

It's *offline mode for your external drive.*

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
| `limpet watch` | Live view of drive + folder state; redraws on plug/unplug (Ctrl-C to quit). |
| `limpet list` | Managed folders + any ad-hoc links you've made into the drive. |
| `limpet link <path>` | Move **any** extra file/folder onto the drive and symlink it back. |
| `limpet unlink <path>` | Bring a symlinked path back onto the local disk. |
| `limpet env` | Offload build-cache env-vars (Go, Gradle, npm, Android) to the drive. `env add VAR path` · `env rm VAR` · `env edit`. |
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

### Offloading build caches

Big, regenerable caches — Go, Gradle, npm, the Android SDK — belong on the drive too, but as
**environment variables**, not symlinks (that's how those tools expect to find them, and it fails over
cleanly). `limpet env` manages them for you:

```bash
limpet env add GOCACHE          Caches/go-build
limpet env add GRADLE_USER_HOME Caches/gradle
limpet env add NPM_CONFIG_CACHE Caches/npm
limpet env                      # show what's mapped + whether it's active
```

When the drive is **connected**, each variable points at `DRIVE/<path>`. When it's **unplugged**, limpet
leaves the variable unset so the tool falls back to its normal internal-disk cache — your builds keep
working offline instead of erroring on a cache that isn't there. The mapping is applied by a tiny hook in
your shell rc (added at `setup`), so a new shell always reflects the current drive state.

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
- **No elevation, no extensions.** No kernel extensions, no background servers, no network calls (except the optional update check). It's ~890 lines of bash you can read in one sitting.
- **Not a backup.** limpet keeps your data *available and resilient to unplugs* — it is **not** a substitute for Time Machine or an offsite backup. Keep one.

---

## FAQ

**Wait — is this safe? Will I lose files?**
No. limpet byte-verifies every copy before it deletes the original, and if two files ever clash it keeps *both*, timestamped. It's not a backup, though — keep your Time Machine.

**Who is this actually for?**
Honestly? Me. It runs on my machine every day. I made it public because you're probably in the same boat — small internal disk, big external SSD. If it helps, ⭐ the repo or say hi.

**Does it work with any drive and any folders?**
Any external volume, and whatever home folders you pick. `limpet link <path>` moves anything else onto the drive too.

**Do I have to babysit it?**
No. The guard + terminal hook handle everything. Unplug, replug, reboot with the drive gone — it sorts itself out.

---

## Caveats (the honest list)

- **Eject cleanly.** If a drive is yanked without ejecting, macOS may remount it as `"X9 1"` or leave a hollow empty `/Volumes/X9` mountpoint behind. limpet checks the live mount table (not just "does the folder exist"), so it treats a hollow mountpoint as *unplugged* and fails over instead of pointing your apps at an empty tree — and `limpet doctor` flags both cases with a fix.
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

---

## Why I made this

I bought a Mac, looked at Apple's storage-upgrade prices, quietly closed the tab, and bought an external SSD instead. Then it kept breaking every time the cable moved. This is the tool I wish had existed that afternoon. It's a personal project — I run it on my own machine — but I made it public so anyone in the same spot can use it. Built by [Pritam](https://www.notpritam.in/) · [blog](https://blog.notpritam.in/).

## License

[MIT](LICENSE) © Pritam Sharma
