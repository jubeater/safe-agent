# DeepSeek Harness (dsh) profile for safe-agent.
#
# dsh keeps all user data under one root, DSH_HOME (default ~/.dsh): every
# dsh profile (profiles/<name>/ with its plugins, cordis.patch.yml and
# package.json), sessions, logs, skills, storages and the provider
# credentials store (.credentials.yaml). The whole root is writable so any
# dsh profile (`safe-dsh web`, `safe-dsh ofm-test`, ...) boots, keeps its
# sessions, and can manage its plugins.
#
# The dsh binary itself lives in the Node installation (npm global), outside
# any writable bind, so there is no executable tree to protect here.
# Code-bearing writable state (runs on the next boot, sandboxed or not):
# profiles/*/node_modules, profiles/*/cordis.patch.yml (`!!js` expressions),
# profiles/*/package.json, the .env layer and skills/.

DEFAULT_BIN="dsh"

_dsh_home="${DSH_HOME:-$HOME/.dsh}"

WRITABLE_DIRS+=(
  "$_dsh_home"
)

EXTRA_ENV+=(
  "SAFE_DSH=1"
  # No TTY and no credential helper inside the sandbox: without this an
  # HTTPS `git push` blocks forever on a username prompt instead of failing.
  "GIT_TERMINAL_PROMPT=0"
)

# dsh reads these bootstrap variables only from the launching environment
# (never from a .env file), so pass them through when set.
[[ -z "${DSH_HOME:-}" ]] || EXTRA_ENV+=("DSH_HOME=$DSH_HOME")
[[ -z "${DSH_PERMISSION_MODE:-}" ]] || EXTRA_ENV+=("DSH_PERMISSION_MODE=$DSH_PERMISSION_MODE")

# Plugin management (`dsh plugin ...`, the web plugin manager) runs pnpm in
# the profile directory. Give it a store and cache inside DSH_HOME instead of
# making the shared host pnpm store writable, which a sandboxed install could
# otherwise poison for every later host project.
EXTRA_ENV+=(
  "pnpm_config_store_dir=$_dsh_home/.safe-agent/pnpm-store"
  "pnpm_config_cache_dir=$_dsh_home/.safe-agent/pnpm-cache"
)

# Version managers such as fnm put node/dsh on PATH through per-shell
# symlinks under XDG_RUNTIME_DIR (/run/user/<uid>/fnm_multishells/...), which
# safe-agent hides. Resolve those entries to their real directories so
# `dsh`, its `#!/usr/bin/env node` shebang and pnpm still resolve inside the
# sandbox; entries that only exist under the hidden runtime dir are dropped.
_dsh_runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
_dsh_path=""
IFS=: read -ra _dsh_parts <<<"$PATH"
for _p in "${_dsh_parts[@]}"; do
  if [[ "$_p" == "$_dsh_runtime"/* ]]; then
    _p="$(realpath -q -- "$_p")" || continue
    [[ "$_p" != "$_dsh_runtime"/* ]] || continue
  fi
  _dsh_path+="${_dsh_path:+:}$_p"
done
EXTRA_ENV+=("PATH=$_dsh_path")
unset _dsh_home _dsh_runtime _dsh_path _dsh_parts _p

# Git over SSH: forward the host's ssh-agent socket (not the key files, which
# stay hidden). Keys loaded with e.g. `ssh-add -t 1h` are usable through it
# until they expire or are removed, so the host-side agent is the gate. Only a
# socket inside an already-masked directory (~/.ssh/agent/..., or under
# XDG_RUNTIME_DIR) can be re-exposed; anything else (e.g. /tmp/ssh-*) is
# skipped with a notice instead of failing the launch. ~/.ssh/known_hosts is
# re-exposed read-only so host keys (github.com) can be verified.
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  _dsh_sock="$(realpath -q -- "$SSH_AUTH_SOCK")" || _dsh_sock=""
  _dsh_ssh="$(realpath -q -- "$HOME/.ssh")" || _dsh_ssh=""
  _dsh_rt="$(realpath -q -- "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}")" || _dsh_rt=""
  if [[ -S "$_dsh_sock" && ( ( -n "$_dsh_ssh" && "$_dsh_sock" == "$_dsh_ssh"/* ) || ( -n "$_dsh_rt" && "$_dsh_sock" == "$_dsh_rt"/* ) ) ]]; then
    POST_MASK_BINDS+=("$_dsh_sock")
    EXTRA_ENV+=("SSH_AUTH_SOCK=$_dsh_sock")
    [[ ! -f "$HOME/.ssh/known_hosts" ]] || POST_MASK_BINDS+=("$HOME/.ssh/known_hosts")
    echo "   ssh-agent: forwarding $SSH_AUTH_SOCK" >&2
  else
    echo "   ssh-agent: not forwarded ($SSH_AUTH_SOCK is not a socket under ~/.ssh or \$XDG_RUNTIME_DIR)" >&2
  fi
  unset _dsh_sock _dsh_ssh _dsh_rt
fi
