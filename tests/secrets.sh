#!/usr/bin/env bash
# Secret-disclosure tests. Usage: tests/secrets.sh
#  1. the credential patterns catch real-looking secrets and ignore benign text
#  2. secrets present in the environment never reach files, process args, tmux, command output or the synced remote
#  3. the tools themselves never print a secret they detect
#  4. state and ~/.claude.json keep restrictive permissions
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
PATTERNS="$HQ_SRC/secret-patterns.txt"
rep() { local n=$2 out="" i; for ((i=0;i<n;i++)); do out="$out$1"; done; printf '%s' "$out"; }   # rep <char> <count>
matches() { printf '%s\n' "$1" | grep -qE -f "$PATTERNS"; }

echo "patterns: must match (samples are assembled at runtime so this file holds no real-looking secret)"
for sample in \
  "ghp_$(rep a 36)" "gho_$(rep B 36)" "ghs_$(rep c 40)" "github_pat_$(rep 1 22)_$(rep Z 40)" "glpat-$(rep q 20)" \
  "AKIA$(rep A 16)" "xoxb-$(rep 1 12)-$(rep a 12)" "sk-ant-api03-$(rep x 40)" "sk-$(rep k 48)" "AIza$(rep d 35)" \
  "-----BEGIN ""RSA PRIVATE KEY-----" "-----BEGIN ""PRIVATE KEY-----" "-----BEGIN ""OPENSSH PRIVATE KEY-----" \
  "api_key = \"$(rep f 24)\"" "API-KEY: $(rep g 30)" "password=$(rep h 22)" "secret: '$(rep i 25)'" "token=$(rep j 32)" \
  "https://user:$(rep p 12)@example.net/repo.git" "git clone http://bot:$(rep t 10)@host/x"; do
  matches "$sample" && ok "detects: ${sample:0:14}..." || bad "pattern missed: ${sample:0:14}..."
done
echo "patterns: must NOT match (false positives would block sync and CI)"
for sample in \
  "the token is stored in the keychain" "ghp_short" "sk-learn is a library" "risk-assessment-for-the-quarter" "task-$(rep 1 45)" \
  "https://github.com/ag237/hq" "ssh://git@host/owner/repo.git" "TOKEN=" "password=CHANGEME" "api_key: <your key here>" \
  "6bfd6a1c-1f3a-4a77-9c1e-0a5f2d3c9b11" "$(rep a 40)" "BEGIN the migration" "ANTHROPIC_API_KEY unset" "export TOKEN=\$GITHUB_TOKEN"; do
  matches "$sample" && bad "false positive: ${sample:0:30}" || ok "ignores: ${sample:0:30}"
done

echo "environment secrets never reach disk, argv, tmux, output or the remote"
S1="sk-ant-api03-$(rep E 40)"; S2="ghp_$(rep G 36)"; S3="$(rep W 40)wJalrXUtnFEMI"; S4="lin_api_$(rep L 40)"
export ANTHROPIC_API_KEY="$S1" GITHUB_TOKEN="$S2" AWS_SECRET_ACCESS_KEY="$S3" LINEAR_API_KEY="$S4" GH_TOKEN="$S2"
leak() { grep -rIlF -e "$S1" -e "$S2" -e "$S3" -e "$S4" "$@" 2>/dev/null; }
OUT="$SB/all-output.log"; : > "$OUT"
run() { "$@" >> "$OUT" 2>&1; }
HQ="$SB/work/hq/bin/hq"; S="$SB/work/hq/bin/spawn-worker"; STATE_REPO="$SB/work/hq-state"
git init -q --bare "$SB/remote.git"
run "$HQ" init --name t --team TST --user-name Tess --state-repo "$STATE_REPO" --remote "$SB/remote.git"
git init -q "$SB/work/demo"; (cd "$SB/work/demo" && git commit -q --allow-empty -m init)
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$SB/work/demo" > "$CLAUDE_JSON"
run "$HQ" up; sleep 1
run "$S" --ops OPS-1 "investigate the failing job"
run "$S" --plan demo WT-1 "fix the chart"; sleep 1
run "$HQ" status; run "$HQ" config; run "$HQ" doctor; run "$HQ" find job
run "$HQ" park OPS-1; run "$HQ" revive OPS-1; sleep 1
run "$SB/work/hq/bin/sync"
run "$SB/work/hq/bin/reap-worker" WT-1
run "$SB/work/hq/bin/sync"
# positive control: the detector itself must work, or the checks below prove nothing
echo "$S2" > "$SB/control.txt"; [ -n "$(leak "$SB/control.txt")" ] && ok "leak detector finds a planted secret" || bad "leak detector is blind"; rm -f "$SB/control.txt"
[ -z "$(leak "$OUT")" ]               && ok "no secret in any command output" || bad "secret printed in command output"
[ -z "$(leak "$SB/work" --exclude-dir=.git)" ] && ok "no secret in generated config, state, briefs or logs" || bad "secret written to disk" "$(leak "$SB/work" --exclude-dir=.git)"
[ -z "$(leak "$SB/claude.log")" ]     && ok "no secret in claude's argv" || bad "secret passed on claude's command line"
printf '%s\n' "$S1" "$S2" "$S3" "$S4" > "$SB/needles"     # via a file: the grep's own argv must not contain the secrets
[ -z "$(ps -eo args 2>/dev/null | grep -F -f "$SB/needles")" ] && ok "no secret in any process command line" || bad "secret visible in ps"
panes="$(tmux -L "$SOCK" list-panes -a -F '#{pane_start_command} #{window_name}' 2>/dev/null)"
case "$panes" in *"$S1"*|*"$S2"*|*"$S3"*|*"$S4"*) bad "secret in tmux pane commands";; *) ok "no secret in tmux pane commands";; esac
rm -rf "$SB/verify"; git clone -q "$SB/remote.git" "$SB/verify" 2>/dev/null
[ -d "$SB/verify/state" ] && ok "synced remote cloned for inspection" || bad "could not clone the remote"
[ -z "$(leak "$SB/verify")" ] && ok "no secret in the synced remote" || bad "secret pushed to the remote"
[ -z "$(cd "$SB/verify" && git log -p --all 2>/dev/null | grep -F -e "$S1" -e "$S2" -e "$S3" -e "$S4")" ] && ok "no secret in the remote's history" || bad "secret in the remote's history"

echo "tools never echo a secret they detect"
FAKE="ghp_$(rep Q 36)"
echo "token=$FAKE" > "$STATE_REPO/state/$(hostname -s)/briefs/leak.md"
out="$("$SB/work/hq/bin/sync" 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok "sync blocks the credential" || bad "sync let a credential through"
case "$out" in *"$FAKE"*) bad "sync printed the secret it blocked";; *) ok "sync's refusal does not print the secret";; esac
[ -z "$(git -C "$STATE_REPO" log -p --all 2>/dev/null | grep -F "$FAKE")" ] && ok "blocked secret never entered the state repo's history" || bad "blocked secret was committed"
git -C "$STATE_REPO" reset -q; rm -f "$STATE_REPO/state/$(hostname -s)/briefs/leak.md"
rm -rf "$SB/lintcopy"; mkdir -p "$SB/lintcopy"; (cd "$HQ_SRC" && tar cf - --exclude=.git --exclude=worktrees .) | (cd "$SB/lintcopy" && tar xf -)
echo "key = $FAKE" > "$SB/lintcopy/NOTES.md"
out="$(cd "$SB/lintcopy" && XDG_CONFIG_HOME="$SB/none" tests/lint.sh 2>&1)"; rc=$?
[ "$rc" != 0 ] && ok "lint fails on a committed credential" || bad "lint passed a leaked credential"
case "$out" in *"$FAKE"*) bad "lint printed the secret (CI logs of a public repo are public)";; *) ok "lint output withholds the secret";; esac
case "$out" in *NOTES.md*) ok "lint still says which file";; *) bad "lint did not name the file";; esac

PW="$(rep p 12)"
# a stub ssh that fails at once and echoes a credentialed URL, as some git/transport errors do (a real network is slow and flaky in CI)
printf '#!/bin/sh\necho "fatal: unable to access ssh://bot:%s@example.invalid/x.git" >&2\nexit 255\n' "$PW" > "$SB/stubs/failssh"; chmod +x "$SB/stubs/failssh"
git -C "$STATE_REPO" remote set-url origin "ssh://bot@example.invalid/x.git"
out="$(GIT_SSH_COMMAND="$SB/stubs/failssh" "$HQ" doctor 2>&1)"; rc=$?
git -C "$STATE_REPO" remote set-url origin "$SB/remote.git"
[ "$rc" != 0 ] && ok "doctor's push check fails when origin cannot be reached" || bad "doctor passed an unreachable remote"
case "$out" in *"unable to access"*) ok "the stub's error reached the diagnosis (so the masking check below is not vacuous)";; *) bad "diagnosis did not include git's error";; esac
case "$out" in *"$PW"*) bad "doctor's push check printed the password from a URL";; *) ok "push check masks credentials in URLs";; esac

echo "permissions"
ST="$STATE_REPO/state/$(hostname -s)"
[ "$(mode "$ST")" = 700 ] && ok "state dir is owner-only (700)" || bad "state dir is not 700"
[ -z "$(find "$ST" -perm -o+w 2>/dev/null)" ] && ok "nothing in state is world-writable" || bad "world-writable state files"
chmod 600 "$CLAUDE_JSON"
printf '{"projects":{"%s":{"hasTrustDialogAccepted":true},"/other/project":{"oauth":"%s"}}}\n' "$SB/work/demo" "$S2" > "$CLAUDE_JSON"
git -C "$SB/work/demo" worktree add -q "$SB/work/wt-x" -b x 2>/dev/null
out="$("$SB/work/hq/bin/trust-path" "$SB/work/wt-x" "$SB/work/demo" 2>&1)"
[ "$(mode "$CLAUDE_JSON")" = 600 ] && ok "claude.json stays 600 after trust-path" || bad "claude.json mode changed"
case "$out" in *"$S2"*|*oauth*) bad "trust-path printed other entries of ~/.claude.json";; *) ok "trust-path prints nothing from ~/.claude.json";; esac
[ -z "$(find "$HOME" -maxdepth 1 -name '.claude.json.*')" ] && ok "no temp copies of ~/.claude.json left behind" || bad "stray ~/.claude.json temp file"
contains "$CLAUDE_JSON" "/other/project" && ok "other entries preserved" || bad "trust-path dropped other entries"

finish
