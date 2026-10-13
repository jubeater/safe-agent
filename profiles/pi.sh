# Pi profile for safe-agent.
#
# `pi --help` documents PI_CODING_AGENT_DIR (default ~/.pi/agent) for
# config/auth/sessions, so ~/.pi/agent is the required writable tree. Bound
# directly at ~/.pi/agent (rather than ~/.pi) so that the agent directory
# itself is a mountpoint and cannot be renamed.
#
# Read-only overlays protect the executable trees inside ~/.pi/agent:
# - bin/              the `pi` launcher executed by host-side invocations
# - install/          version selector (current-version) + release binaries
# A sandboxed agent therefore cannot persist a modified launcher/binary
# that a later unsandboxed invocation would execute.
# Auth (~/.pi/agent/auth.json), sessions, settings and skills remain
# writable. API keys can also come from env, but the base policy
# intentionally uses clearenv + allowlist (same as the trusted
# safe-opencode); the auth file is the supported path inside the sandbox.

DEFAULT_BIN="pi"

WRITABLE_DIRS+=(
  "$HOME/.pi/agent"
)

READONLY_DIRS+=(
  "$HOME/.pi/agent/bin"
  "$HOME/.pi/agent/install"
)
