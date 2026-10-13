#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)"
FAKE_HOME="$FIXTURE_DIR/home"
PROJECT_DIR="$FIXTURE_DIR/project"
INSTALL_DIR="$FIXTURE_DIR/install"
STUB_BIN="$FIXTURE_DIR/stub_bin"
LAUNCHER="$PROJECT_DIR/safe-agent"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  local test_cmd="$2"
  if eval "$test_cmd"; then
    echo "  [PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $desc"
    FAIL=$((FAIL + 1))
  fi
}

run_sandbox() {
  (
    cd "$PROJECT_DIR"
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME SAFE_AGENT SAFE_AGENT_PROFILE SAFE_OPENCODE
    HOME="$FAKE_HOME" "$LAUNCHER" "$@"
  )
}

echo "=== Running safe-agent Verification Suite v2 ==="

# ---------------------------------------------------------------------------
# Test Group 1: D & E - Executable Protection & Invariants (with Child Markers)
# ---------------------------------------------------------------------------
echo "--- Group 1: D & E (Pi & Qoder Executable Protection) ---"
rm -rf "$FAKE_HOME" && mkdir -p "$FAKE_HOME"

# Setup Pi dirs
mkdir -p "$FAKE_HOME/.pi/agent/bin" "$FAKE_HOME/.pi/agent/install"
echo "REAL_PI_BIN" > "$FAKE_HOME/.pi/agent/bin/pi"
chmod 755 "$FAKE_HOME/.pi/agent/bin/pi"
echo "v1.0.0" > "$FAKE_HOME/.pi/agent/install/current-version"
chmod 644 "$FAKE_HOME/.pi/agent/install/current-version"
echo '{"token":"secret"}' > "$FAKE_HOME/.pi/agent/auth.json"
chmod 600 "$FAKE_HOME/.pi/agent/auth.json"

PI_BIN_HASH=$(sha256sum "$FAKE_HOME/.pi/agent/bin/pi" | cut -d' ' -f1)
PI_BIN_MODE=$(stat -c %a "$FAKE_HOME/.pi/agent/bin/pi")
PI_VER_HASH=$(sha256sum "$FAKE_HOME/.pi/agent/install/current-version" | cut -d' ' -f1)
PI_VER_MODE=$(stat -c %a "$FAKE_HOME/.pi/agent/install/current-version")

# Test D: Direct write to Pi bin/pi must fail specifically on write denial
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox pi -- /bin/bash -c 'touch "$PWD/child_marker" && { echo PWNED > "$HOME/.pi/agent/bin/pi"; } || exit 42' 2>/dev/null
RET=$?
set -e
assert "Pi direct write: child marker proves child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Pi direct write: exit status confirms write denial (42)" '[ $RET -eq 42 ]'
assert "Pi direct write: host bin bytes exact match" '[ "$(sha256sum "$FAKE_HOME/.pi/agent/bin/pi" | cut -d" " -f1)" = "$PI_BIN_HASH" ]'
assert "Pi direct write: host bin mode unchanged (755)" '[ "$(stat -c %a "$FAKE_HOME/.pi/agent/bin/pi")" = "$PI_BIN_MODE" ]'

# Test D: Direct write to Pi install/current-version must fail specifically on write denial
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox pi -- /bin/bash -c 'touch "$PWD/child_marker" && { echo PWNED > "$HOME/.pi/agent/install/current-version"; } || exit 42' 2>/dev/null
RET=$?
set -e
assert "Pi install version write: child marker proves child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Pi install version write: exit status confirms write denial (42)" '[ $RET -eq 42 ]'
assert "Pi install version write: host bytes exact match" '[ "$(sha256sum "$FAKE_HOME/.pi/agent/install/current-version" | cut -d" " -f1)" = "$PI_VER_HASH" ]'
assert "Pi install version write: host mode unchanged (644)" '[ "$(stat -c %a "$FAKE_HOME/.pi/agent/install/current-version")" = "$PI_VER_MODE" ]'

# Test D: Rename of Pi agent parent inside sandbox must fail specifically on rename denial
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox pi -- /bin/bash -c 'touch "$PWD/child_marker" && { mv "$HOME/.pi/agent" "$HOME/.pi/agent.old"; } || exit 43' 2>/dev/null
RET=$?
set -e
assert "Pi ancestor rename: child marker proves child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Pi ancestor rename: exit status confirms rename denial (43)" '[ $RET -eq 43 ]'
assert "Pi ancestor rename: host agent dir not renamed" '[ -d "$FAKE_HOME/.pi/agent/bin" ] && [ ! -d "$FAKE_HOME/.pi/agent.old" ]'
assert "Pi ancestor rename: host bin bytes intact" '[ "$(sha256sum "$FAKE_HOME/.pi/agent/bin/pi" | cut -d" " -f1)" = "$PI_BIN_HASH" ]'

# Test D: State write inside sandbox succeeds
set +e
run_sandbox pi -- /bin/bash -c 'echo "{\"new_token\":\"valid\"}" > "$HOME/.pi/agent/auth.json" && touch "$HOME/.pi/agent/new_state"' 2>/dev/null
RET=$?
set -e
assert "Pi state write inside sandbox succeeds (exit 0)" '[ $RET -eq 0 ]'
assert "Host Pi auth file updated with new token" 'grep -q "new_token" "$FAKE_HOME/.pi/agent/auth.json"'
assert "Host Pi new state file exists" '[ -f "$FAKE_HOME/.pi/agent/new_state" ]'

# Setup Qoder protected trees (all 4: entry, bin, .bin, app)
mkdir -p "$FAKE_HOME/.qoder/entry" "$FAKE_HOME/.qoder/bin" "$FAKE_HOME/.qoder/.bin" "$FAKE_HOME/.qoder/app"
echo "REAL_ENTRY" > "$FAKE_HOME/.qoder/entry/qoder"; chmod 755 "$FAKE_HOME/.qoder/entry/qoder"
echo "REAL_BIN" > "$FAKE_HOME/.qoder/bin/qodercli"; chmod 755 "$FAKE_HOME/.qoder/bin/qodercli"
echo "REAL_DOTBIN" > "$FAKE_HOME/.qoder/.bin/helper"; chmod 755 "$FAKE_HOME/.qoder/.bin/helper"
echo "REAL_APP" > "$FAKE_HOME/.qoder/app/resource"; chmod 644 "$FAKE_HOME/.qoder/app/resource"

Q_ENTRY_HASH=$(sha256sum "$FAKE_HOME/.qoder/entry/qoder" | cut -d' ' -f1)
Q_BIN_HASH=$(sha256sum "$FAKE_HOME/.qoder/bin/qodercli" | cut -d' ' -f1)
Q_DOTBIN_HASH=$(sha256sum "$FAKE_HOME/.qoder/.bin/helper" | cut -d' ' -f1)
Q_APP_HASH=$(sha256sum "$FAKE_HOME/.qoder/app/resource" | cut -d' ' -f1)

# Test Qoder 1: entry
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox qoder -- /bin/bash -c 'touch "$PWD/child_marker" && { echo PWNED > "$HOME/.qoder/entry/qoder"; } || exit 42' 2>/dev/null
RET=$?
set -e
assert "Qoder entry write: child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Qoder entry write: exit status confirms write denial (42)" '[ $RET -eq 42 ]'
assert "Qoder entry write: host bytes exact match" '[ "$(sha256sum "$FAKE_HOME/.qoder/entry/qoder" | cut -d" " -f1)" = "$Q_ENTRY_HASH" ]'

# Test Qoder 2: bin
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox qoder -- /bin/bash -c 'touch "$PWD/child_marker" && { echo PWNED > "$HOME/.qoder/bin/qodercli"; } || exit 42' 2>/dev/null
RET=$?
set -e
assert "Qoder bin write: child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Qoder bin write: exit status confirms write denial (42)" '[ $RET -eq 42 ]'
assert "Qoder bin write: host bytes exact match" '[ "$(sha256sum "$FAKE_HOME/.qoder/bin/qodercli" | cut -d" " -f1)" = "$Q_BIN_HASH" ]'

# Test Qoder 3: .bin
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox qoder -- /bin/bash -c 'touch "$PWD/child_marker" && { echo PWNED > "$HOME/.qoder/.bin/helper"; } || exit 42' 2>/dev/null
RET=$?
set -e
assert "Qoder .bin write: child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Qoder .bin write: exit status confirms write denial (42)" '[ $RET -eq 42 ]'
assert "Qoder .bin write: host bytes exact match" '[ "$(sha256sum "$FAKE_HOME/.qoder/.bin/helper" | cut -d" " -f1)" = "$Q_DOTBIN_HASH" ]'

# Test Qoder 4: app
rm -f "$PROJECT_DIR/child_marker"
set +e
run_sandbox qoder -- /bin/bash -c 'touch "$PWD/child_marker" && { echo PWNED > "$HOME/.qoder/app/resource"; } || exit 42' 2>/dev/null
RET=$?
set -e
assert "Qoder app write: child ran" '[ -f "$PROJECT_DIR/child_marker" ]'
assert "Qoder app write: exit status confirms write denial (42)" '[ $RET -eq 42 ]'
assert "Qoder app write: host bytes exact match" '[ "$(sha256sum "$FAKE_HOME/.qoder/app/resource" | cut -d" " -f1)" = "$Q_APP_HASH" ]'

# Test E: Symlink in READONLY_DIRS leaf must fail closed
mkdir -p "$FAKE_HOME/.qoder/real_bin"
ln -s "$FAKE_HOME/.qoder/real_bin" "$FAKE_HOME/.qoder/test_leaf_symlink"
cat > "$PROJECT_DIR/profiles/test-leaf-symlink.sh" << 'EOF'
DEFAULT_BIN="bash"
WRITABLE_DIRS=("$HOME/.qoder")
READONLY_DIRS=("$HOME/.qoder/test_leaf_symlink")
EOF
set +e
OUTPUT=$(run_sandbox test-leaf-symlink -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "Symlink leaf in READONLY_DIRS rejected" '[ $RET -ne 0 ]'
assert "Symlink leaf diagnostic is clear" 'echo "$OUTPUT" | grep -q "must not be a symlink"'
rm -f "$PROJECT_DIR/profiles/test-leaf-symlink.sh" "$FAKE_HOME/.qoder/test_leaf_symlink" && rm -rf "$FAKE_HOME/.qoder/real_bin"

# Test E: Protected path whose parent is not an OWN_BINDS root must fail closed
cat > "$PROJECT_DIR/profiles/test-bad-parent.sh" << 'EOF'
DEFAULT_BIN="bash"
WRITABLE_DIRS=("$HOME/.badtest")
READONLY_DIRS=("$HOME/.badtest/sub/bin")
EOF
mkdir -p "$FAKE_HOME/.badtest/sub/bin"
set +e
OUTPUT=$(run_sandbox test-bad-parent -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "Protected path parent mismatch rejected" '[ $RET -ne 0 ]'
assert "Parent mismatch diagnostic is clear" 'echo "$OUTPUT" | grep -q "must equal a declared writable root"'
rm -f "$PROJECT_DIR/profiles/test-bad-parent.sh" && rm -rf "$FAKE_HOME/.badtest"

# ---------------------------------------------------------------------------
# Test Group 2: B & C - Sensitive Paths, Multi-Symlinks, Deduplication & Modes
# ---------------------------------------------------------------------------
echo "--- Group 2: B & C (Sensitive Files, Symlinks, Deduplication) ---"
rm -rf "$FAKE_HOME" && mkdir -p "$FAKE_HOME"

# Setup Git credentials in standard & custom locations
mkdir -p "$FAKE_HOME/.config/git" "$FAKE_HOME/custom_xdg/git"
echo "token_home" > "$FAKE_HOME/.git-credentials"; chmod 600 "$FAKE_HOME/.git-credentials"
echo "token_cfg" > "$FAKE_HOME/.config/git/credentials"; chmod 640 "$FAKE_HOME/.config/git/credentials"
echo "token_custom" > "$FAKE_HOME/custom_xdg/git/credentials"; chmod 600 "$FAKE_HOME/custom_xdg/git/credentials"

GIT_HOME_HASH=$(sha256sum "$FAKE_HOME/.git-credentials" | cut -d' ' -f1)
GIT_CFG_HASH=$(sha256sum "$FAKE_HOME/.config/git/credentials" | cut -d' ' -f1)
GIT_CUST_HASH=$(sha256sum "$FAKE_HOME/custom_xdg/git/credentials" | cut -d' ' -f1)

# Test B: Masking standard and custom Git credentials
READ_DEFAULT=$(run_sandbox opencode -- /bin/bash -c 'cat "$HOME/.git-credentials" "$HOME/.config/git/credentials"' 2>/dev/null)
assert "Default git credentials masked (empty)" '[ -z "$READ_DEFAULT" ]'
assert "Host default git credentials bytes unchanged" '[ "$(sha256sum "$FAKE_HOME/.git-credentials" | cut -d" " -f1)" = "$GIT_HOME_HASH" ]'
assert "Host default git credentials mode 0600 unchanged" '[ "$(stat -c %a "$FAKE_HOME/.git-credentials")" = "600" ]'
assert "Host default config git credentials bytes unchanged" '[ "$(sha256sum "$FAKE_HOME/.config/git/credentials" | cut -d" " -f1)" = "$GIT_CFG_HASH" ]'
assert "Host default config git credentials mode 0640 unchanged" '[ "$(stat -c %a "$FAKE_HOME/.config/git/credentials")" = "640" ]'

READ_CUSTOM=$(
  cd "$PROJECT_DIR"
  XDG_CONFIG_HOME="$FAKE_HOME/custom_xdg" HOME="$FAKE_HOME" "$LAUNCHER" opencode -- /bin/bash -c 'cat "$XDG_CONFIG_HOME/git/credentials"' 2>/dev/null
)
assert "Custom XDG git credentials masked (empty)" '[ -z "$READ_CUSTOM" ]'
assert "Host custom XDG git credentials bytes unchanged" '[ "$(sha256sum "$FAKE_HOME/custom_xdg/git/credentials" | cut -d" " -f1)" = "$GIT_CUST_HASH" ]'
assert "Host custom XDG git credentials mode 0600 unchanged" '[ "$(stat -c %a "$FAKE_HOME/custom_xdg/git/credentials")" = "600" ]'

# Test B/C: Multiple symlinks pointing to one target file (deduplication & modes)
mkdir -p "$FAKE_HOME/dotfiles"
echo "SHARED_SECRET_TOKEN" > "$FAKE_HOME/dotfiles/shared_credentials"
chmod 600 "$FAKE_HOME/dotfiles/shared_credentials"
SHARED_HASH=$(sha256sum "$FAKE_HOME/dotfiles/shared_credentials" | cut -d' ' -f1)

ln -sf "$FAKE_HOME/dotfiles/shared_credentials" "$FAKE_HOME/.git-credentials"
ln -sf "$FAKE_HOME/dotfiles/shared_credentials" "$FAKE_HOME/.config/git/credentials"

READ_MULTI_SYM=$(run_sandbox opencode -- /bin/bash -c 'cat "$HOME/.git-credentials" && cat "$HOME/.config/git/credentials" && cat "$HOME/dotfiles/shared_credentials"' 2>/dev/null)
assert "Multiple symlinks to one target: masked empty" '[ -z "$READ_MULTI_SYM" ]'
assert "Multiple symlinks to one target: host bytes unchanged" '[ "$(sha256sum "$FAKE_HOME/dotfiles/shared_credentials" | cut -d" " -f1)" = "$SHARED_HASH" ]'
assert "Multiple symlinks to one target: host mode 0600 unchanged" '[ "$(stat -c %a "$FAKE_HOME/dotfiles/shared_credentials")" = "600" ]'

# Test C: Symlinked sensitive directory (~/.ssh -> dotfiles/ssh)
mkdir -p "$FAKE_HOME/dotfiles/ssh"
echo "SECRET_SSH_KEY" > "$FAKE_HOME/dotfiles/ssh/id_rsa"; chmod 600 "$FAKE_HOME/dotfiles/ssh/id_rsa"
SSH_KEY_HASH=$(sha256sum "$FAKE_HOME/dotfiles/ssh/id_rsa" | cut -d' ' -f1)
ln -s "$FAKE_HOME/dotfiles/ssh" "$FAKE_HOME/.ssh"

SSH_OUT=$(run_sandbox opencode -- /bin/bash -c 'ls -A "$HOME/.ssh" && ls -A "$HOME/dotfiles/ssh"' 2>/dev/null)
assert "Symlinked SSH dir and target appear empty in sandbox" '[ -z "$SSH_OUT" ]'
assert "Host SSH key bytes intact" '[ "$(sha256sum "$FAKE_HOME/dotfiles/ssh/id_rsa" | cut -d" " -f1)" = "$SSH_KEY_HASH" ]'
assert "Host SSH key mode 0600 intact" '[ "$(stat -c %a "$FAKE_HOME/dotfiles/ssh/id_rsa")" = "600" ]'

# Test C: Dangling symlinks handled cleanly without crash
ln -s "$FAKE_HOME/nonexistent" "$FAKE_HOME/.kube"
ln -s "$FAKE_HOME/nonexistent-file" "$FAKE_HOME/.netrc"
set +e
run_sandbox opencode -- /bin/bash -c 'true' 2>/dev/null
RET=$?
set -e
assert "Dangling symlinks handled without error" '[ $RET -eq 0 ]'

# Test C: Sensitive path symlinked to / or HOME rejected
rm -rf "$FAKE_HOME/.ssh"
ln -s "/" "$FAKE_HOME/.ssh"
set +e
OUTPUT=$(run_sandbox opencode -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "Sensitive path pointing to / rejected" '[ $RET -ne 0 ]'
assert "Clear diagnostic for / target" 'echo "$OUTPUT" | grep -q "must not be /, HOME, or an ancestor"'

rm -rf "$FAKE_HOME/.ssh"
ln -s "$FAKE_HOME" "$FAKE_HOME/.ssh"
set +e
OUTPUT=$(run_sandbox opencode -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "Sensitive path pointing to HOME rejected" '[ $RET -ne 0 ]'
assert "Clear diagnostic for HOME target" 'echo "$OUTPUT" | grep -q "must not be /, HOME, or an ancestor"'

# ---------------------------------------------------------------------------
# Test Group 3: G - Peer Profile Isolation (Checking Both Pi and OpenCode)
# ---------------------------------------------------------------------------
echo "--- Group 3: G (Peer Isolation & Overlap Refusal) ---"
rm -rf "$FAKE_HOME" && mkdir -p "$FAKE_HOME"
mkdir -p "$FAKE_HOME/.pi/agent" "$FAKE_HOME/.local/share/opencode" "$FAKE_HOME/.qoder"
echo "SECRET_PI_AUTH" > "$FAKE_HOME/.pi/agent/auth.json"
echo "SECRET_OPENCODE_AUTH" > "$FAKE_HOME/.local/share/opencode/auth.json"
echo "SECRET_QODER_AUTH" > "$FAKE_HOME/.qoder/auth.json"

# Qoder profile cannot read Pi auth AND cannot read OpenCode auth
QODER_PI_AUTH=$(run_sandbox qoder -- /bin/bash -c 'cat "$HOME/.pi/agent/auth.json" 2>/dev/null || echo HIDDEN' 2>/dev/null)
assert "Qoder cannot read Pi peer auth" '[ "$QODER_PI_AUTH" = "HIDDEN" ]'
QODER_OC_AUTH=$(run_sandbox qoder -- /bin/bash -c 'cat "$HOME/.local/share/opencode/auth.json" 2>/dev/null || echo HIDDEN' 2>/dev/null)
assert "Qoder cannot read OpenCode peer auth" '[ "$QODER_OC_AUTH" = "HIDDEN" ]'

# Pi profile cannot read OpenCode auth AND cannot read Qoder auth
PI_OC_AUTH=$(run_sandbox pi -- /bin/bash -c 'cat "$HOME/.local/share/opencode/auth.json" 2>/dev/null || echo HIDDEN' 2>/dev/null)
assert "Pi cannot read OpenCode peer auth" '[ "$PI_OC_AUTH" = "HIDDEN" ]'
PI_Q_AUTH=$(run_sandbox pi -- /bin/bash -c 'cat "$HOME/.qoder/auth.json" 2>/dev/null || echo HIDDEN' 2>/dev/null)
assert "Pi cannot read Qoder peer auth" '[ "$PI_Q_AUTH" = "HIDDEN" ]'

# Overlap refusal: workspace inside Pi state
mkdir -p "$FAKE_HOME/.pi/agent/workspace"
set +e
OUTPUT=$(cd "$FAKE_HOME/.pi/agent/workspace" && HOME="$FAKE_HOME" "$LAUNCHER" opencode -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "Workspace overlapping peer state root is refused" '[ $RET -ne 0 ]'
assert "Clear diagnostic on peer overlap" 'echo "$OUTPUT" | grep -q "overlaps workspace or selected profile state; refusing to launch"'

# ---------------------------------------------------------------------------
# Test Group 4: R1 & R2 Regressions (Symlinked Ancestors & Overlapping Roots)
# ---------------------------------------------------------------------------
echo "--- Group 4: R1 & R2 Regressions ---"
rm -rf "$FAKE_HOME" && mkdir -p "$FAKE_HOME"

# R1: Pi profile with symlinked ancestor below HOME (~/.pi/agent is symlink)
mkdir -p "$FAKE_HOME/.pi" "$FAKE_HOME/ext_pi_install/bin" "$FAKE_HOME/ext_pi_install/install"
ln -s "$FAKE_HOME/ext_pi_install" "$FAKE_HOME/.pi/agent"
set +e
OUTPUT=$(run_sandbox pi -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "R1: Pi profile with symlink ~/.pi/agent rejected" '[ $RET -ne 0 ]'
assert "R1: Pi symlink diagnostic clear" 'echo "$OUTPUT" | grep -q "path component below HOME must not be a symlink"'
rm -rf "$FAKE_HOME/.pi" "$FAKE_HOME/ext_pi_install"

# R1: Qoder profile with symlinked ancestor below HOME (~/.qoder is symlink)
mkdir -p "$FAKE_HOME/ext_qoder_install/bin"
ln -s "$FAKE_HOME/ext_qoder_install" "$FAKE_HOME/.qoder"
set +e
OUTPUT=$(run_sandbox qoder -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "R1: Qoder profile with symlink ~/.qoder rejected" '[ $RET -ne 0 ]'
assert "R1: Qoder symlink diagnostic clear" 'echo "$OUTPUT" | grep -q "path component below HOME must not be a symlink"'
rm -rf "$FAKE_HOME/.qoder" "$FAKE_HOME/ext_qoder_install"

# R2: Writable bind root strictly inside workspace (Pi case)
mkdir -p "$PROJECT_DIR/vendor/pi_state/bin" "$PROJECT_DIR/vendor/pi_state/install"
cat > "$PROJECT_DIR/profiles/test-r2-workspace-pi.sh" << EOF
DEFAULT_BIN="bash"
WRITABLE_DIRS=("$PROJECT_DIR/vendor/pi_state")
READONLY_DIRS=("$PROJECT_DIR/vendor/pi_state/bin" "$PROJECT_DIR/vendor/pi_state/install")
EOF
set +e
OUTPUT=$(run_sandbox test-r2-workspace-pi -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "R2: Bind root strictly inside workspace rejected (Pi)" '[ $RET -ne 0 ]'
assert "R2: Workspace overlap diagnostic clear (Pi)" 'echo "$OUTPUT" | grep -q "lies strictly inside workspace"'
rm -f "$PROJECT_DIR/profiles/test-r2-workspace-pi.sh" && rm -rf "$PROJECT_DIR/vendor"

# R2: Writable bind root strictly inside workspace (Qoder case)
mkdir -p "$PROJECT_DIR/vendor/qoder_state/bin"
cat > "$PROJECT_DIR/profiles/test-r2-workspace-qoder.sh" << EOF
DEFAULT_BIN="bash"
WRITABLE_DIRS=("$PROJECT_DIR/vendor/qoder_state")
READONLY_DIRS=("$PROJECT_DIR/vendor/qoder_state/bin")
EOF
set +e
OUTPUT=$(run_sandbox test-r2-workspace-qoder -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "R2: Bind root strictly inside workspace rejected (Qoder)" '[ $RET -ne 0 ]'
assert "R2: Workspace overlap diagnostic clear (Qoder)" 'echo "$OUTPUT" | grep -q "lies strictly inside workspace"'
rm -f "$PROJECT_DIR/profiles/test-r2-workspace-qoder.sh" && rm -rf "$PROJECT_DIR/vendor"

# R2: Generic nested profile (bind root strictly inside another OWN_BINDS root)
mkdir -p "$FAKE_HOME/state/group/agent/bin"
cat > "$PROJECT_DIR/profiles/test-r2-nested.sh" << 'EOF'
DEFAULT_BIN="bash"
WRITABLE_DIRS=("$HOME/state" "$HOME/state/group/agent")
READONLY_DIRS=("$HOME/state/group/agent/bin")
EOF
set +e
OUTPUT=$(run_sandbox test-r2-nested -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "R2: Bind root strictly inside another bind root rejected" '[ $RET -ne 0 ]'
assert "R2: Nested root diagnostic clear" 'echo "$OUTPUT" | grep -q "lies strictly inside another writable root"'
rm -f "$PROJECT_DIR/profiles/test-r2-nested.sh" && rm -rf "$FAKE_HOME/state"

# ---------------------------------------------------------------------------
# Test Group 5: K - Dry Run Output Quoting
# ---------------------------------------------------------------------------
echo "--- Group 5: K (Dry Run Output Quoting) ---"
DRY_OUT=$(cd "$PROJECT_DIR" && SAFE_AGENT_DRY_RUN=1 HOME="$FAKE_HOME" "$LAUNCHER" opencode -- echo "hello world" '$TEST' "foo bar" 2>/dev/null)
assert "Dry run output contains properly quoted arguments" 'echo "$DRY_OUT" | grep -F -q "hello\\ world"'
assert "Dry run output preserves special variables" 'echo "$DRY_OUT" | grep -F -q "\\\$TEST"'

# ---------------------------------------------------------------------------
# Test Group 6: F - Full Repeatable Install and Safe Rollback
# ---------------------------------------------------------------------------
echo "--- Group 6: F (Repeatable Install & Safe Rollback) ---"
rm -rf "$INSTALL_DIR" && mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/home"
echo "ORIGINAL_SAFE_OPENCODE" > "$INSTALL_DIR/bin/safe-opencode"
chmod 755 "$INSTALL_DIR/bin/safe-opencode"

ORIG_OPENCODE_HASH=$(sha256sum "$INSTALL_DIR/bin/safe-opencode" | cut -d' ' -f1)
AGENT_SRC_HASH=$(sha256sum "$LAUNCHER" | cut -d' ' -f1)

# First full install (executing README block verbatim adapted to fixture paths)
if [ ! -e "$INSTALL_DIR/home/safe-opencode.bak" ] && [ -f "$INSTALL_DIR/bin/safe-opencode" ] && [ ! -L "$INSTALL_DIR/bin/safe-opencode" ]; then
  cp "$INSTALL_DIR/bin/safe-opencode" "$INSTALL_DIR/home/safe-opencode.bak"
fi
cp "$LAUNCHER" "$INSTALL_DIR/bin/safe-agent"
chmod +x "$INSTALL_DIR/bin/safe-agent"
mkdir -p "$INSTALL_DIR/bin/profiles" && cp "$PROJECT_DIR"/profiles/*.sh "$INSTALL_DIR/bin/profiles/"
ln -sf safe-agent "$INSTALL_DIR/bin/safe-opencode"
ln -sf safe-agent "$INSTALL_DIR/bin/safe-qoder"
ln -sf safe-agent "$INSTALL_DIR/bin/safe-pi"

assert "First install created backup with exact original bytes" '[ "$(sha256sum "$INSTALL_DIR/home/safe-opencode.bak" | cut -d" " -f1)" = "$ORIG_OPENCODE_HASH" ]'
assert "First install created safe-opencode symlink" '[ -L "$INSTALL_DIR/bin/safe-opencode" ] && [ "$(readlink "$INSTALL_DIR/bin/safe-opencode")" = "safe-agent" ]'

# Second full install (repeating FULL README install block)
if [ ! -e "$INSTALL_DIR/home/safe-opencode.bak" ] && [ -f "$INSTALL_DIR/bin/safe-opencode" ] && [ ! -L "$INSTALL_DIR/bin/safe-opencode" ]; then
  cp "$INSTALL_DIR/bin/safe-opencode" "$INSTALL_DIR/home/safe-opencode.bak"
fi
cp "$LAUNCHER" "$INSTALL_DIR/bin/safe-agent"
chmod +x "$INSTALL_DIR/bin/safe-agent"
mkdir -p "$INSTALL_DIR/bin/profiles" && cp "$PROJECT_DIR"/profiles/*.sh "$INSTALL_DIR/bin/profiles/"
ln -sf safe-agent "$INSTALL_DIR/bin/safe-opencode"
ln -sf safe-agent "$INSTALL_DIR/bin/safe-qoder"
ln -sf safe-agent "$INSTALL_DIR/bin/safe-pi"

assert "Second full install preserved original backup bytes" '[ "$(sha256sum "$INSTALL_DIR/home/safe-opencode.bak" | cut -d" " -f1)" = "$ORIG_OPENCODE_HASH" ]'
assert "Second full install kept safe-opencode symlink intact" '[ "$(readlink "$INSTALL_DIR/bin/safe-opencode")" = "safe-agent" ]'

# Rollback (executing README rollback block verbatim)
if [ -f "$INSTALL_DIR/home/safe-opencode.bak" ]; then
  rm -f "$INSTALL_DIR/bin/safe-opencode"
  cp "$INSTALL_DIR/home/safe-opencode.bak" "$INSTALL_DIR/bin/safe-opencode"
  chmod +x "$INSTALL_DIR/bin/safe-opencode"
fi

assert "Rollback restored safe-opencode as regular file" '[ ! -L "$INSTALL_DIR/bin/safe-opencode" ] && [ -f "$INSTALL_DIR/bin/safe-opencode" ]'
assert "Restored safe-opencode bytes exact match to original" '[ "$(sha256sum "$INSTALL_DIR/bin/safe-opencode" | cut -d" " -f1)" = "$ORIG_OPENCODE_HASH" ]'
assert "Rollback preserved safe-agent bytes byte-for-byte unchanged" '[ "$(sha256sum "$INSTALL_DIR/bin/safe-agent" | cut -d" " -f1)" = "$AGENT_SRC_HASH" ]'
assert "Rollback preserved safe-qoder symlink target" '[ -L "$INSTALL_DIR/bin/safe-qoder" ] && [ "$(readlink "$INSTALL_DIR/bin/safe-qoder")" = "safe-agent" ]'
assert "Rollback preserved safe-pi symlink target" '[ -L "$INSTALL_DIR/bin/safe-pi" ] && [ "$(readlink "$INSTALL_DIR/bin/safe-pi")" = "safe-agent" ]'

# ---------------------------------------------------------------------------
# Test Group 7: Multicall Stubs on PATH (Exact Argv & Exit Status)
# ---------------------------------------------------------------------------
echo "--- Group 7: Multicall with Harmless PATH Stubs ---"
rm -rf "$STUB_BIN" && mkdir -p "$STUB_BIN"

# Create harmless stubs that log invocation to stub_invoked.log in the working dir and exit with status 77
cat > "$STUB_BIN/opencode" << 'EOF'
#!/usr/bin/env bash
printf "%s\n" "$0" "$@" > "$PWD/stub_invoked.log"
exit 77
EOF
chmod 755 "$STUB_BIN/opencode"

cat > "$STUB_BIN/qodercli" << 'EOF'
#!/usr/bin/env bash
printf "%s\n" "$0" "$@" > "$PWD/stub_invoked.log"
exit 77
EOF
chmod 755 "$STUB_BIN/qodercli"

cat > "$STUB_BIN/pi" << 'EOF'
#!/usr/bin/env bash
printf "%s\n" "$0" "$@" > "$PWD/stub_invoked.log"
exit 77
EOF
chmod 755 "$STUB_BIN/pi"

ln -sf safe-agent "$PROJECT_DIR/safe-opencode"
ln -sf safe-agent "$PROJECT_DIR/safe-qoder"
ln -sf safe-agent "$PROJECT_DIR/safe-pi"

STUB_OUT_FILE="$PROJECT_DIR/stub_invoked.log"

# Test multicall 1: safe-opencode -> opencode stub
rm -f "$STUB_OUT_FILE"
set +e
(
  cd "$PROJECT_DIR"
  PATH="$STUB_BIN:$PATH" HOME="$FAKE_HOME" "$PROJECT_DIR/safe-opencode" alpha "beta gamma"
) 2>/dev/null
MC_RET=$?
set -e
assert "Multicall safe-opencode exit status 77 from stub" '[ $MC_RET -eq 77 ]'
assert "Multicall safe-opencode executed opencode binary" '[ -f "$STUB_OUT_FILE" ] && head -n 1 "$STUB_OUT_FILE" | grep -q "opencode"'
assert "Multicall safe-opencode passed exact arguments" 'grep -Fxq "alpha" "$STUB_OUT_FILE" && grep -Fxq "beta gamma" "$STUB_OUT_FILE"'

# Test multicall 2: safe-qoder -> qodercli stub
rm -f "$STUB_OUT_FILE"
set +e
(
  cd "$PROJECT_DIR"
  PATH="$STUB_BIN:$PATH" HOME="$FAKE_HOME" "$PROJECT_DIR/safe-qoder" delta "epsilon zeta"
) 2>/dev/null
MC_RET=$?
set -e
assert "Multicall safe-qoder exit status 77 from stub" '[ $MC_RET -eq 77 ]'
assert "Multicall safe-qoder executed qodercli binary" '[ -f "$STUB_OUT_FILE" ] && head -n 1 "$STUB_OUT_FILE" | grep -q "qodercli"'
assert "Multicall safe-qoder passed exact arguments" 'grep -Fxq "delta" "$STUB_OUT_FILE" && grep -Fxq "epsilon zeta" "$STUB_OUT_FILE"'

# Test multicall 3: safe-pi -> pi stub
rm -f "$STUB_OUT_FILE"
set +e
(
  cd "$PROJECT_DIR"
  PATH="$STUB_BIN:$PATH" HOME="$FAKE_HOME" "$PROJECT_DIR/safe-pi" eta "theta iota"
) 2>/dev/null
MC_RET=$?
set -e
assert "Multicall safe-pi exit status 77 from stub" '[ $MC_RET -eq 77 ]'
assert "Multicall safe-pi executed pi binary" '[ -f "$STUB_OUT_FILE" ] && head -n 1 "$STUB_OUT_FILE" | grep -q "/pi"'
assert "Multicall safe-pi passed exact arguments" 'grep -Fxq "eta" "$STUB_OUT_FILE" && grep -Fxq "theta iota" "$STUB_OUT_FILE"'

rm -f "$PROJECT_DIR/safe-opencode" "$PROJECT_DIR/safe-qoder" "$PROJECT_DIR/safe-pi" "$STUB_OUT_FILE"
rm -rf "$STUB_BIN"

# ---------------------------------------------------------------------------
# Test Group 8: Workspace & Invocation Checks
# ---------------------------------------------------------------------------
echo "--- Group 8: Workspace & Invocation Checks ---"
set +e
OUTPUT=$(cd "$FAKE_HOME" && HOME="$FAKE_HOME" "$LAUNCHER" opencode -- /bin/bash -c 'true' 2>&1)
RET=$?
set -e
assert "Running from HOME rejected" '[ $RET -ne 0 ]'
assert "Running from HOME diagnostic is clear" 'echo "$OUTPUT" | grep -q "must not be /, HOME, or an ancestor"'

# Child stdout cleanliness
STDOUT_TEST=$(run_sandbox opencode -- /bin/echo "ONLY_STDOUT" 2>/dev/null)
assert "Child stdout contains only child output" '[ "$STDOUT_TEST" = "ONLY_STDOUT" ]'

# ---------------------------------------------------------------------------
# Test Group 9: OpenCode background-service isolation
# ---------------------------------------------------------------------------
echo "--- Group 9: OpenCode Background Service Isolation ---"
rm -rf "$FAKE_HOME" && mkdir -p "$FAKE_HOME/.local/state/opencode"
SERVICE_JSON="$FAKE_HOME/.local/state/opencode/service.json"
echo '{"url":"http://127.0.0.1:1","password":"HOST_SERVICE_SECRET"}' > "$SERVICE_JSON"
SERVICE_HASH=$(sha256sum "$SERVICE_JSON" | cut -d' ' -f1)

set +e
OUTPUT=$(run_sandbox opencode -- /bin/bash -c 'cat "$HOME/.local/state/opencode/service.json"; echo x > "$HOME/.local/state/opencode/service.json" || exit 42' 2>/dev/null)
RET=$?
set -e
assert "service.json content hidden inside sandbox" '! echo "$OUTPUT" | grep -q HOST_SERVICE_SECRET'
assert "service.json write denied inside sandbox (42)" '[ $RET -eq 42 ]'
assert "Host service.json bytes unchanged" '[ "$(sha256sum "$SERVICE_JSON" | cut -d" " -f1)" = "$SERVICE_HASH" ]'
set +e
run_sandbox opencode -- /bin/bash -c 'touch "$HOME/.local/state/opencode/new_state"' 2>/dev/null
RET=$?
set -e
assert "OpenCode state dir otherwise still writable" '[ $RET -eq 0 ] && [ -f "$FAKE_HOME/.local/state/opencode/new_state" ]'

# Command rewriting (dry-run; a stub opencode on PATH satisfies the lookup).
mkdir -p "$STUB_BIN" && printf '#!/bin/sh\nexit 0\n' > "$STUB_BIN/opencode" && chmod 755 "$STUB_BIN/opencode"
oc_dry() {
  (cd "$PROJECT_DIR" && SAFE_AGENT_DRY_RUN=1 PATH="$STUB_BIN:$PATH" HOME="$FAKE_HOME" "$LAUNCHER" opencode -- opencode "$@" 2>&1)
}
assert "TUI forced onto private server" 'oc_dry | grep -q -- "-- opencode --standalone$"'
assert "TUI with directory forced onto private server" 'oc_dry . | grep -q -- "-- opencode --standalone \.$"'
assert "run gets --standalone after subcommand" 'oc_dry --log-level debug run hi | grep -q -- "-- opencode --log-level debug run --standalone hi$"'
assert "Existing --standalone not duplicated" 'oc_dry run --standalone hi | grep -q -- "-- opencode run --standalone hi$"'
assert "serve passes through unchanged" 'oc_dry serve --port 4100 | grep -q -- "-- opencode serve --port 4100$"'
assert "Non-opencode command left alone" '(cd "$PROJECT_DIR" && SAFE_AGENT_DRY_RUN=1 HOME="$FAKE_HOME" "$LAUNCHER" opencode -- /bin/true 2>&1) | grep -q -- "-- /bin/true$"'
assert "Dry-run masks service.json" 'oc_dry | grep -q -- "--ro-bind-data [0-9]* $SERVICE_JSON"'
for refused in "--server http://127.0.0.1:1" "run --server=http://127.0.0.1:1 hi" "--standalone --server http://x" "service start" "pair"; do
  set +e
  # shellcheck disable=SC2086
  OUTPUT=$(oc_dry $refused)
  RET=$?
  set -e
  assert "Refused: opencode $refused" '[ $RET -ne 0 ] && echo "$OUTPUT" | grep -q "^safe-agent:" && ! echo "$OUTPUT" | grep -q "^dry-run:"'
done
rm -rf "$STUB_BIN"

echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -eq 0 ]; then
  exit 0
else
  exit 1
fi
