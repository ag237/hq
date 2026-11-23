#!/usr/bin/env bash
# Shared sandbox for the test scripts (source it). Fake HOME, private tmux server, a stub `claude`, a local bare
# git remote; touches nothing outside a temp dir.
# shellcheck disable=SC2034
set -uo pipefail
exec < /dev/null   # never let a command under test (e.g. hq init) wait for a person on the terminal
HQ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/hq-test.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
SOCK="hqtest-$$"
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$SB"; }   # private socket only, never the default server
trap cleanup EXIT

export HOME="$SB/home" XDG_CONFIG_HOME="$SB/home/.config" XDG_STATE_HOME="$SB/home/.state" HQ_SOCKET="$SOCK" \
       HQ_PM_BOOT_WAIT=1 CLAUDE_JSON="$SB/home/.claude.json" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset TMUX HQ_PROFILE HQ_WORKDIR HQ_STATE_DIR HQ_PROFILES_DIR HQ_SYNC HQ_HOST TMUX_TMPDIR
mkdir -p "$HOME" "$SB/stubs" "$SB/work"
export PATH="$SB/stubs:$HOME/.local/bin:$PATH"
git config --global user.name "Test User"; git config --global user.email "test@example.com"
git config --global init.defaultBranch main

# stub claude: record the arguments, then stay alive like an interactive session
cat > "$SB/stubs/claude" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$SB/claude.log"
exec sleep 600
STUB
chmod +x "$SB/stubs/claude"

PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '        %s\n' "$2"; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d" "command failed: $*"; fi; }
refuse() { local d=$1; shift; if "$@" >/dev/null 2>&1; then bad "$d" "expected failure: $*"; else ok "$d"; fi; }
contains() { grep -qF -- "$2" "$1" 2>/dev/null; }

# sandbox copy of the app (no .git, no worktrees); a fake token is assembled at runtime so no file holds a real-looking one
mkdir -p "$SB/work/hq"; (cd "$HQ_SRC" && tar cf - --exclude=.git --exclude=worktrees .) | (cd "$SB/work/hq" && tar xf -)
HQ="$SB/work/hq/bin/hq"; STATE_REPO="$SB/work/hq-state"
git init -q --bare "$SB/remote.git"
HOST="$(hostname -s)"


mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }   # lint:allow GNU first, BSD/macOS fallback
finish() { echo; echo "passed: $PASS   failed: $FAIL"; [ "$FAIL" = 0 ]; }
