#!/usr/bin/env bash
# ABOUTME: One-line installer for limpet — downloads the CLI onto your PATH.
# ABOUTME: curl -fsSL https://raw.githubusercontent.com/notpritam/limpet/main/install.sh | bash
set -euo pipefail

REPO="${LIMPET_REPO:-notpritam/limpet}"
REF="${LIMPET_REF:-main}"
RAW="https://raw.githubusercontent.com/$REPO/$REF/limpet"

say(){ printf '%s\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || { say "limpet is macOS-only (it uses launchd + ditto)."; exit 1; }
command -v curl >/dev/null || { say "curl is required."; exit 1; }

# Prefer a no-sudo, on-PATH bin dir; fall back to ~/.local/bin and note PATH.
pick_bindir() {
  local d
  for d in "$HOME/.local/bin" /usr/local/bin /opt/homebrew/bin; do
    case ":$PATH:" in *":$d:"*) ;; *) continue;; esac
    [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }
  done
  echo "$HOME/.local/bin"
}
BIN="$(pick_bindir)"; mkdir -p "$BIN"; DEST="$BIN/limpet"

say "→ downloading limpet from $REPO ($REF)…"
curl -fsSL "$RAW" -o "$DEST"
chmod +x "$DEST"
say "✓ installed: $DEST"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say "! $BIN is not on your PATH yet — add this line to your ~/.zshrc:"
     say "    export PATH=\"$BIN:\$PATH\"";;
esac

say ""
say "Next:  limpet setup     # pick your drive + folders (interactive)"
say "Docs:  https://github.com/$REPO"
