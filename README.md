# safe-agent

A small [bubblewrap](https://github.com/containers/bubblewrap) sandbox
launcher for AI coding-agent CLIs. One entrypoint,
`safe-agent <profile> -- <command>`, runs an agent so that it can write
only to the current project directory and its own state directories. The
rest of the host is read-only, and common credentials are hidden.

Bundled profiles: [opencode](https://opencode.ai), Qoder CLI (`qodercli`)
and pi. Adding another agent means adding one small profile file.

## Requirements

- Linux with unprivileged user namespaces enabled
- `bwrap` (bubblewrap) on `PATH`
- Bash 4+ and GNU coreutils (`realpath`)

## Install

Run on the host, outside any sandbox:

```bash
git clone https://github.com/jubeater/safe-agent.git
cd safe-agent
./install.sh                  # installs into ~/.local/bin
PREFIX=/opt/bin ./install.sh  # or somewhere else
```

The installer copies `safe-agent` and `profiles/` into `$PREFIX`, then
creates a `safe-<profile>` symlink for each profile. It is safe to re-run.
If a regular file already exists where a symlink should go (for example an
older standalone wrapper), it is moved to `<name>.bak` once and never
overwritten.

To uninstall, remove `safe-agent`, the `safe-*` symlinks and the
`profiles/` directory from `$PREFIX`.

## Layout

```text
safe-agent          # launcher: parsing, validation, bwrap policy, env filtering, exec
profiles/
  opencode.sh       # XDG data/cache/state opencode + SAFE_OPENCODE=1;
                    # forces a private in-sandbox server (see below)
  qoder.sh          # ~/.qoder + ~/.config/qoder; executable trees read-only
  pi.sh             # ~/.pi/agent; launcher + install trees read-only
install.sh          # copies launcher + profiles, creates safe-* symlinks
tests/
  run.sh            # builds a fake-HOME fixture and runs the suite
  suite.sh          # regression suite
```

`safe-agent` resolves `profiles/` relative to its own real path
(`realpath $0`), so keep `profiles/` next to the installed binary.

Each profile declares `WRITABLE_DIRS` (state the agent may write),
`READONLY_DIRS` (executable trees overlaid read-only inside writable
state), `MASKED_FILES` (files inside its own writable state hidden from the
sandbox), `EXTRA_ENV` (static `NAME=VALUE` entries), and `DEFAULT_BIN`
(used by the multicall symlink and `doctor`). A profile may also define a
`profile_adjust_cmd` function, which can rewrite the `CMD` array or `fail`
on invocations that would escape the sandbox.

## Usage

```bash
safe-agent opencode -- opencode --version
safe-agent opencode -- opencode serve --port 4096
safe-agent qoder -- qodercli --version
safe-agent pi -- pi --version
safe-agent doctor opencode|qoder|pi
```

Multicall (via symlink basename):

```bash
safe-opencode [args...]   # == safe-agent opencode -- opencode [args...]
safe-qoder [args...]      # == safe-agent qoder -- qodercli [args...]
safe-pi [args...]         # == safe-agent pi -- pi [args...]
```

`safe-qoder` defaults to `qodercli`, not the `qoder` dispatcher: the
dispatcher routes subcommands such as chat/serve-web to the IDE, while
`qodercli` is the CLI. The explicit form still accepts either binary.

Test helper (prints the bwrap command instead of executing):

```bash
SAFE_AGENT_DRY_RUN=1 ./safe-agent opencode -- opencode --version
```

## Policy boundaries (explicit)

- Host filesystem is readable; writable only at the workspace (current
  directory) plus the selected profile's state dirs. Launching from `/`,
  `$HOME`, or an ancestor of `$HOME` fails closed, as do profile paths
  resolving there.
  Unlike the original standalone `safe-opencode` wrapper (which ran from any
  working directory including `$HOME`), `safe-agent` refuses `$HOME` as
  workspace to prevent making the entire home directory writable. Editor or
  extension configurations (such as VS Code tasks) must launch with cwd set
  to a project directory rather than `$HOME`.
- Executable protection: Qoder/Pi executable trees (`~/.qoder/entry`,
  `~/.qoder/bin`, `~/.qoder/.bin`, `~/.qoder/app`, `~/.pi/agent/bin`,
  `~/.pi/agent/install`) are overlaid read-only, and protected paths must be
  direct children of a declared writable bind root (not symlinks). To ensure
  no mutable ancestor allows redirecting execution lookup, the launcher
  enforces that no component of a declared writable or protected path below
  HOME may be a symlink, and a protected entry's writable bind root cannot
  lie strictly inside the workspace or strictly inside another writable bind
  root. Any layout violating these invariants is refused at launch.
  Auth, settings, sessions, cache and logs stay writable.
- Code-bearing writable state: several files and directories remain writable
  for normal agent/extension functionality, but can execute host commands or
  affect later unsandboxed runs:
  - `~/.qoder/mcp.json` (launches MCP servers as host commands)
  - `~/.qoder/settings.json`
  - `~/.qoder/extensions`
  - `~/.qoder/plugins`
  - `~/.pi/agent/settings.json`
  - `~/.pi/agent/skills`
  Always launch agent CLIs via `safe-*`, or inspect these files before
  running unsandboxed on the host.
- Self-update blocked in sandbox: because executable and installation roots
  (`~/.qoder/bin`, `~/.qoder/.bin`, `~/.pi/agent/install`) are protected by
  read-only overlays, in-sandbox self-update commands (such as `pi update` or
  `qodercli` updates) will fail with permission errors. Update Qoder and Pi
  directly on the host outside `safe-agent`.
- Peer profile credential isolation: other agents' state roots (auth,
  sessions) are hidden via tmpfs mounts derived from each profile's
  `WRITABLE_DIRS`. If a peer state root overlaps the current workspace or
  selected profile state, `safe-agent` refuses to launch with a clear
  diagnostic instead of silently omitting the peer mask.
- Credential files are masked with content from throwaway descriptors on
  `/dev/null` (no predictable cache file is created or trusted). Git
  credentials (`~/.git-credentials`, `~/.config/git/credentials`, and
  `$XDG_CONFIG_HOME/git/credentials`), gh and gcloud (`~/.config/{gh,gcloud}`
  and `$XDG_CONFIG_HOME/{gh,gcloud}`), and keyrings (`~/.local/share/keyrings`
  and `$XDG_DATA_HOME/keyrings`) are masked at both default and resolved
  custom XDG locations. Netrc (`~/.netrc`), npm (`~/.npmrc`), PyPI (`~/.pypirc`),
  and Cargo (`~/.cargo/credentials{,.toml}`) credentials are masked at their
  standard HOME locations. Symlinked sensitive paths are canonicalised to
  their targets before masking so aliases remain hidden without bubblewrap
  symlink mount failures, and duplicate destination masks are deduplicated.
- Environment is rebuilt from an allowlist (`--clearenv`); only the
  documented variables plus `SAFE_AGENT=1`, `SAFE_AGENT_PROFILE=<name>`
  (and `SAFE_OPENCODE=1` for opencode) are set.
- Network is intentionally shared (no `--unshare-net`): agents need it,
  and editor integrations need localhost.
- Agent work must run *inside* the sandbox, not just the UI. OpenCode 2.x
  clients (TUI, `run`, `mini`, `api`, `models`, `stats`, `reload`) attach by
  default to a shared host "background service" (`opencode serve --service`,
  found through `~/.local/state/opencode/service.json`), and that server
  executes every tool call. A sandboxed client attached to it confines
  nothing. The opencode profile therefore adds `--standalone` (a private
  server spawned inside the sandbox), hides `service.json` (the host
  server's URL + password), and refuses `--server`, `opencode service` and
  `opencode pair`. `opencode serve` already runs its server in-process and
  passes through unchanged. On the host, avoid bare `opencode`: it starts
  the unconfined background service (stop it with `opencode service stop`).
  The discovery file is only masked if it exists at launch.
- Launch diagnostics go to stderr, so child stdout stays machine-readable.
- Profiles are trusted executable Bash. The host stays broadly readable
  except for explicitly masked paths; this is a containment wrapper, not
  a full sandbox redesign.

## Verifying an install

```bash
safe-opencode --version
safe-agent opencode -- opencode --version
safe-agent qoder -- qodercli --version
safe-agent pi -- pi --version
```

Inside each sandbox:

```bash
echo "$SAFE_AGENT"            # expect 1
echo "$SAFE_AGENT_PROFILE"    # expect profile name
echo "$SAFE_OPENCODE"         # expect 1 (opencode only)

touch ./safe-agent-test         # expect success (workspace writable)
touch ~/safe-agent-should-fail  # expect failure (host read-only)
ls ~/.ssh                       # expect empty/hidden
cat ~/.git-credentials          # expect empty/masked
```

Editor integrations that launch `safe-opencode` (for example the VS Code
extension) keep working, but must start it with the working directory set
to a project, because launching from `$HOME` is refused.

## Tests

```bash
tests/run.sh
```

The suite builds a throwaway fixture with a fake `HOME` under
`.test-fixtures/` and runs the launcher against it, so real agent state and
credentials are never touched. It covers executable protection,
credential masking (including symlinked and custom-XDG paths), peer-profile
isolation, workspace refusal, dry-run quoting, install repeatability and
the multicall symlinks. It needs `bwrap` and must run outside any other
sandbox.

## Known limitations

- **Network is shared.** A sandboxed agent can still send anything it can
  read over the network. The host filesystem stays broadly readable apart
  from the masked paths: browser profiles, password-manager data and other
  application tokens are *not* masked by default.
- **Missing protected entries are not created.** If a protected executable
  directory (such as `~/.qoder/entry`) does not exist at launch, it is
  skipped, and the sandboxed agent could create it. Run each agent's
  installer on the host before first using it through `safe-agent`.
- **`$XDG_RUNTIME_DIR` is hidden.** Tools that live there (for example
  `fnm` multishell shims under `/run/user/<uid>/fnm_multishells`) are not
  reachable inside the sandbox even if they are on `PATH`.
- **Multicall names are mapped in the launcher.** A new profile works with
  `safe-agent <profile> -- <command>` immediately. A `safe-<profile>`
  shortcut also needs an entry in `multicall_profile()`.
- This is a containment wrapper for everyday use, not a hardened security
  boundary. Profiles are trusted Bash.

## License

MIT
