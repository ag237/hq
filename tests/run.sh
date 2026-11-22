#!/usr/bin/env bash
# Test suite. Runs hq end to end in a sandbox: fake HOME, private tmux server, a stub `claude`, a local bare git
# remote. Touches nothing outside a temp dir. Usage: tests/run.sh
set -uo pipefail
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

echo "init"
refuse "init refuses workdir == \$HOME" "$HQ" init --name t --workdir "$HOME"
check "init --state-repo" "$HQ" init --name t --team TST --user-name Tess --state-repo "$STATE_REPO" --remote "$SB/remote.git"
check "state repo is a separate git repo" test -d "$STATE_REPO/.git"
check "env points at state repo" contains "$HOME/.config/hq/env" "HQ_STATE_DIR=$STATE_REPO/state/$HOST"
check "sync enabled once origin exists" contains "$HOME/.config/hq/env" "HQ_SYNC=on"
check "profile created in state repo" test -f "$STATE_REPO/profiles/t/profile.env"
check "USER_NAME written to profile" contains "$STATE_REPO/profiles/t/profile.env" "USER_NAME=Tess"
check "doctor passes" "$HQ" doctor

echo "generated config"
check "pm.md rendered" test -s "$SB/work/.claude/agents/pm.md"
if grep -rn '{{' "$SB/work/.claude" >/dev/null 2>&1; then bad "no unrendered {{placeholders}}" "$(grep -rn '{{' "$SB/work/.claude" | head -3)"; else ok "no unrendered {{placeholders}}"; fi
check "settings.json is valid JSON" python3 -I -c 'import json,sys;json.load(open(sys.argv[1]))' "$SB/work/.claude/settings.json"
check "PM addressed by USER_NAME" contains "$SB/work/.claude/agents/pm.md" "Tess"
check "no HQ_BIN placeholder text leaked" bash -c '! grep -q "HQ_BIN" "$1"' _ "$SB/work/.claude/settings.json"

echo "input validation (no injection, no traversal)"
S="$SB/work/hq/bin/spawn-worker"
refuse "issue id with command substitution" "$S" --ops 'X$(touch PWNED)' "b"
refuse "issue id with ; and quotes"        "$S" --ops "A';touch PWNED;'" "b"
refuse "issue id path traversal"           "$S" --ops '../../etc' "b"
refuse "issue id leading dash"             "$S" --ops '-rf' "b"
refuse "repo path traversal"               "$S" '../x' ABC-1 "b"
refuse "repo with slash"                   "$S" 'a/b' ABC-1 "b"
refuse "hq park rejects bad id"            "$HQ" park 'x;y'
refuse "hq revive rejects bad id"          "$HQ" revive '$(id)'
refuse "hq adopt rejects bad id"           "$HQ" adopt 11111111-1111-1111-1111-111111111111 'a b'
refuse "reap-worker rejects bad id"        "$SB/work/hq/bin/reap-worker" '../x'
check "nothing was created by the attempts" bash -c '! find "$1" -name PWNED | grep -q .' _ "$SB"
check "board still empty" test ! -s "$STATE_REPO/state/$HOST/board.tsv"

echo "workers"
check "hq up starts the PM" "$HQ" up
sleep 1
check "PM window exists" bash -c 'tmux -L "$1" list-windows -t hq -F "#W" | grep -qx pm' _ "$SOCK"
check "PM launched on the profile model" contains "$SB/claude.log" "--model opus --agent pm"
check "spawn ops worker (shell metachars stay inert in the brief)" "$S" --ops OPS-1 'do $(touch PWNED) `touch PWNED2` "quoted"'
sleep 1
check "worker window exists" bash -c 'tmux -L "$1" list-windows -t hq -F "#W" | grep -qx OPS-1' _ "$SOCK"
check "worker on the profile worker model" contains "$SB/claude.log" "--model sonnet --session-id"
check "brief kept verbatim in file only" contains "$STATE_REPO/state/$HOST/briefs/OPS-1.md" '$(touch PWNED)'
check "brief injection did not execute" bash -c '! find "$1" -name "PWNED*" | grep -q .' _ "$SB"
refuse "duplicate spawn refused" "$S" --ops OPS-1 "again"
check "spawn --plan" "$S" --ops --plan PLAN-1 "plan it"
sleep 1
check "plan worker: plan mode on opusplan" contains "$SB/claude.log" "--model opusplan --permission-mode plan"
check "plan worker model pinned for resumes" contains "$STATE_REPO/state/$HOST/models/PLAN-1" "opusplan"
check "spawn --model override" "$S" --ops --model haiku MOD-1 "x"
sleep 1
check "override model used" contains "$SB/claude.log" "--model haiku --session-id"
check "park closes window, keeps row" bash -c '"$1" park OPS-1 && ! tmux -L "$2" list-windows -t hq -F "#W" | grep -qx OPS-1 && grep -q "OPS-1.*parked" "$3"' _ "$HQ" "$SOCK" "$STATE_REPO/state/$HOST/board.tsv"
check "revive reopens, pinned model kept" bash -c '"$1" revive PLAN-1 >/dev/null; "$1" park PLAN-1 >/dev/null; "$1" revive PLAN-1' _ "$HQ"
sleep 1
check "revive re-applied the pinned model" bash -c 'grep -c -- "--model opusplan" "$1" | grep -qv "^[01]$"' _ "$SB/claude.log"
check "hq down" "$HQ" down
check "hq up rebuilds active workers" bash -c '"$1" up >/dev/null; sleep 1; tmux -L "$2" list-windows -t hq -F "#W" | grep -qx MOD-1' _ "$HQ" "$SOCK"

echo "worktree worker + trust"
git init -q "$SB/work/demo"; (cd "$SB/work/demo" && git commit -q --allow-empty -m init)
printf '{"projects":{}}\n' > "$CLAUDE_JSON"
check "spawn worktree worker (repo untrusted)" "$S" demo WT-1 "change"
check "worktree created" test -d "$SB/work/hq/worktrees/demo/WT-1"
check "untrusted repo: worktree NOT auto-trusted" bash -c '! grep -q WT-1 "$1"' _ "$CLAUDE_JSON"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$SB/work/demo" > "$CLAUDE_JSON"
check "spawn second worker (repo trusted)" "$S" demo WT-2 "change"
check "trusted repo: worktree auto-trusted" contains "$CLAUDE_JSON" "WT-2"
check "reap removes worktree" "$SB/work/hq/bin/reap-worker" WT-2
check "reap removed trust entry" bash -c '! grep -q WT-2 "$1"' _ "$CLAUDE_JSON"
check "reap keeps the row as done" grep -q 'WT-2.*done' "$STATE_REPO/state/$HOST/board.tsv"

echo "sync"
SYNC="$SB/work/hq/bin/sync"
check "sync pushes state" "$SYNC"
check "remote has the state files" bash -c 'git --git-dir="$1" ls-tree -r --name-only main | grep -q "board.tsv"' _ "$SB/remote.git"
check "app copy never committed to the state repo" bash -c '! git --git-dir="$1" ls-tree -r --name-only main | grep -q "^bin/"' _ "$SB/remote.git"
check "second sync is a no-op" bash -c '"$1" | grep -q "up to date"' _ "$SYNC"
FAKE="ghp_$(printf 'A%.0s' $(seq 1 36))"
echo "token=$FAKE" > "$STATE_REPO/state/$HOST/briefs/leak.md"
refuse "sync refuses a credential" "$SYNC"
check "refused change left uncommitted" bash -c '[ -n "$(git -C "$1" status --porcelain)" ]' _ "$STATE_REPO"
rm "$STATE_REPO/state/$HOST/briefs/leak.md"
check "sync works again once removed" "$SYNC"
mkdir -p "$SB/cfg2/hq" "$SB/work/hq/state/x"
printf 'HQ_SYNC=on\nHQ_STATE_DIR=%s\n' "$SB/work/hq/state/x" > "$SB/cfg2/hq/env"
git -C "$SB/work/hq" init -q
refuse "sync refuses state inside the app repo" env XDG_CONFIG_HOME="$SB/cfg2" "$SYNC"
check "HQ_SYNC=off is a no-op" env HQ_SYNC=off "$SYNC"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" = 0 ]
