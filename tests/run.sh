#!/usr/bin/env bash
# Run the safe-agent regression suite in a throwaway fixture.
# Uses a fake HOME, so it never touches real agent state or credentials.
# Requires bubblewrap (bwrap) and must run outside any other sandbox.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The fixture must live outside /tmp: the sandbox mounts a fresh tmpfs on
# /tmp, which would hide a fake HOME placed there.
mkdir -p "$REPO_DIR/.test-fixtures"
FIXTURE="$(mktemp -d "$REPO_DIR/.test-fixtures/run.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/project"
cp "$REPO_DIR/safe-agent" "$FIXTURE/project/"
cp -r "$REPO_DIR/profiles" "$FIXTURE/project/"

"$REPO_DIR/tests/suite.sh" "$FIXTURE"
