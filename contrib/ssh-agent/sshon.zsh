# Unlock my SSH key for a while so agents can push to GitHub.
# The key goes into a dedicated agent (systemd user unit safe-agent-ssh, socket
# $XDG_RUNTIME_DIR/safe-agent-ssh.sock) that safe-dsh forwards into its sandbox.
# It expires (default 1h), works for github.com only, and unless SSHON_CONFIRM=0
# pops up a confirmation every time it is used.  Usage: sshon [duration]
sshon() {
  local sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/safe-agent-ssh.sock"
  local -a opts=(-t "${1:-1h}" -h github.com)
  [[ "${SSHON_CONFIRM:-1}" == 0 ]] || opts+=(-c)
  SSH_AUTH_SOCK=$sock ssh-add "${opts[@]}" "${SSHON_KEY:-$HOME/.ssh/id_ed25519}" && export SSH_AUTH_SOCK=$sock
}
# Remove the key from the sandbox agent right away.
sshoff() {
  SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/safe-agent-ssh.sock" ssh-add -D
}
