# Qoder profile for safe-agent.
#
# DEFAULT_BIN is qodercli, not the `qoder` dispatcher: the installed
# `qoder` (~/.qoder/entry/qoder) routes subcommands such as chat/serve-web
# to the IDE, while qodercli (~/.local/bin/qodercli ->
# ~/.qoder/bin/qodercli/qodercli-<version>) is the actual CLI.
# The explicit `safe-agent qoder -- <command>` form still accepts `qoder`.
#
# Writable state (observed on this machine):
# - ~/.qoder holds auth (~/.qoder/.auth/), settings, projects, cache, logs.
#   Bound broadly, with the executable trees below overlaid read-only.
# - ~/.config/qoder exists on disk (Crashpad/Local State); kept writable in
#   case the CLI shares state there.
# Deliberately NOT writable:
# - ~/.config/com.qoder.app.stable (desktop/Electron profile; no observed
#   CLI need).
# - ~/.cache/qoder, ~/.local/state/qoder (do not exist; no observed need).
#
# Read-only overlays protect the executable trees inside ~/.qoder:
# - entry/            dispatcher script executed by host-side invocations
# - bin/              versioned qodercli binaries
# - .bin/             bundled runtime helper binary
# - app/              bundled resources
# A sandboxed agent therefore cannot persist a modified binary/launcher
# that a later unsandboxed invocation would execute. Auth, settings,
# sessions, cache and logs under ~/.qoder remain writable.
# Limitation: ~/.qoder/extensions and ~/.qoder/plugins stay writable so
# extension management keeps working; treat them as code-bearing state.

DEFAULT_BIN="qodercli"

WRITABLE_DIRS+=(
  "$HOME/.qoder"
  "${XDG_CONFIG_HOME:-$HOME/.config}/qoder"
)

READONLY_DIRS+=(
  "$HOME/.qoder/entry"
  "$HOME/.qoder/bin"
  "$HOME/.qoder/.bin"
  "$HOME/.qoder/app"
)
