# OpenCode profile for safe-agent.
# Mirrors the writable state of the original standalone safe-opencode
# wrapper that safe-agent replaced.
#
# The opencode binary itself is a system install (/usr/bin, outside any
# writable bind), so no executable tree needs protecting here.
# Keep this small: writable dirs + default binary + static extra env, plus
# the client/server handling below.

DEFAULT_BIN="opencode"

WRITABLE_DIRS+=(
  "${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
  "${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
  "${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
)

# OpenCode 2.x clients (TUI, run, mini, ...) attach by default to a shared
# host-side "background service" (`opencode serve --service`) discovered via
# this file, and that server runs every tool call. A sandboxed client talking
# to an unsandboxed server confines nothing, so the discovery file (URL +
# password) is hidden and clients are forced onto a private in-sandbox server.
MASKED_FILES+=(
  "${XDG_STATE_HOME:-$HOME/.local/state}/opencode/service.json"
)

EXTRA_ENV+=(
  "SAFE_OPENCODE=1"
)

# Rewrite the opencode command line so every server it uses runs inside this
# sandbox. Only applies when the command is opencode itself (the explicit
# `safe-agent opencode -- <other>` form is left alone).
profile_adjust_cmd() {
  [[ "$(basename -- "${CMD[0]}")" == "opencode" ]] || return 0

  local i a sub="" sub_idx=0 has_standalone=0
  for ((i = 1; i < ${#CMD[@]}; i++)); do
    a="${CMD[i]}"
    case "$a" in
      --server | --server=*)
        fail "opencode --server attaches to a server outside the sandbox; refusing (use 'safe-opencode serve' and connect to that)"
        ;;
      --standalone) has_standalone=1 ;;
    esac
  done
  [[ "$has_standalone" -eq 0 ]] || return 0

  # First positional argument = subcommand (or the TUI's directory).
  for ((i = 1; i < ${#CMD[@]}; i++)); do
    a="${CMD[i]}"
    case "$a" in
      --) break ;;
      --log-level | --completions | --session | -s | --prompt) ((i++)) || true ;;
      -*) ;;
      *) sub="$a"; sub_idx=$i; break ;;
    esac
  done

  case "$sub" in
    service | pair)
      fail "'opencode $sub' manages/exposes the host background service; not available inside safe-agent (run 'safe-opencode serve' instead)"
      ;;
    run | mini | api | models | stats | reload)
      # Client subcommands: private server, inserted right after the subcommand.
      CMD=("${CMD[@]:0:sub_idx+1}" --standalone "${CMD[@]:sub_idx+1}")
      ;;
    serve | acp | auth | mcp | session | plugin | debug | upgrade | update | uninstall)
      # Run in-process or only touch local state.
      ;;
    *)
      # TUI (no subcommand, or a directory argument).
      [[ " ${CMD[*]:1} " == *" --help "* || " ${CMD[*]:1} " == *" -h "* ]] && return 0
      [[ " ${CMD[*]:1} " == *" --version "* || " ${CMD[*]:1} " == *" -v "* ]] && return 0
      CMD=("${CMD[0]}" --standalone "${CMD[@]:1}")
      ;;
  esac
}
