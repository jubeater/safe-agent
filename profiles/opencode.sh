# OpenCode profile for safe-agent.
# Mirrors the writable state of the original standalone safe-opencode
# wrapper that safe-agent replaced.
#
# The opencode binary itself is a system install (/usr/bin, outside any
# writable bind), so no executable tree needs protecting here.
# Keep this small: writable dirs + default binary + static extra env only.

DEFAULT_BIN="opencode"

WRITABLE_DIRS+=(
  "${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
  "${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
  "${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
)

EXTRA_ENV+=(
  "SAFE_OPENCODE=1"
)
