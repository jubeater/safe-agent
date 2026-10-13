#!/usr/bin/env bash
# Install safe-agent, its profiles and the multicall symlinks.
# Safe to re-run: refreshes installed files and keeps unrelated profiles.
# Run on the host, outside any sandbox.
#
#   ./install.sh                 # installs into ~/.local/bin
#   PREFIX=/opt/bin ./install.sh # installs elsewhere
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"

command -v bwrap >/dev/null || echo "warning: bwrap (bubblewrap) not found on PATH" >&2

mkdir -p "$PREFIX/profiles"
install -m 755 "$SRC_DIR/safe-agent" "$PREFIX/safe-agent"
install -m 644 "$SRC_DIR"/profiles/*.sh "$PREFIX/profiles/"

for profile in "$SRC_DIR"/profiles/*.sh; do
  link="$PREFIX/safe-$(basename "$profile" .sh)"
  # Never clobber a real file (e.g. an older standalone wrapper): back it up once.
  if [[ -e "$link" && ! -L "$link" ]]; then
    if [[ -e "$link.bak" ]]; then
      echo "skip: $link is a regular file and $link.bak already exists" >&2
      continue
    fi
    mv "$link" "$link.bak"
    echo "backed up existing $link to $link.bak" >&2
  fi
  ln -sfn safe-agent "$link"
done

echo "installed safe-agent into $PREFIX"
